// 4sight public map A2: one calm map with three layers on together (close passes, City
// injuries, City bike lanes), each switchable. The sheet sums up whatever is on, the list of
// streets and wards carries the same numbers off the map, and every card has its own URL:
// #street=, #ward=, #pass=lat,lon, #injury=, #lane=, plus &layers= when not all are on and
// &test=1 when test rides are included (the 4sight data is then refetched with ?demo=1).
// Helpers and cards live in a2-cards.js.
(async function () {
  const $ = (id) => document.getElementById(id);
  const DATA = "data/";
  const LIVE = "https://4sight-server.vercel.app/v1/city-risk.geojson";
  const ALL = ["passes", "injuries", "lanes"];
  const BAND = [[0, "#B4BAC3", "None yet"], [30, "#F5C46B", "Fewer than 30"], [60, "#F5A623", "30 to 60"], [Infinity, "#E8453C", "60 or more"]];
  const band = (r) => r <= 0 ? BAND[0] : BAND.find(([max], i) => i && r < max);
  const LANE = {
    protected: ["#1E7A37", "Protected lane"], painted: ["#0A6CDF", "Painted lane"],
    shared: ["#8C95A1", "Shared route"], trail: ["#7DB38C", "Trail"],
  };
  const VEHICLE = { car: ["cars", "A car"], truck: ["trucks", "A truck"], bus: ["buses", "A bus"], motorcycle: ["motorcycles", "A motorcycle"], bicycle: ["bicycles", "Another bike"] };
  const INK = "#111418", RED = "#D93025";
  const DOT_ZOOM = 14; // single close passes show from this zoom in
  const MIN_KM = 10; // under this many km ridden a street's rate is too noisy to rank
  // no-cache: revalidate every time, so a ride sent a moment ago shows on reload.
  const getJSON = (u) => fetch(u, { cache: "no-cache" }).then((r) => r.ok ? r.json() : null).catch(() => null);
  let test = new URLSearchParams(location.hash.slice(1)).get("test") === "1";

  // Map first so tiles load while the data does.
  const map = L.map("map", { renderer: L.canvas({ tolerance: 6 }), zoomControl: false, minZoom: 10, maxZoom: 17 })
    .setView([43.68, -79.39], 12);
  L.control.zoom({ position: "topright" }).addTo(map);
  const esri = "https://server.arcgisonline.com/ArcGIS/rest/services/Canvas/";
  L.tileLayer(esri + "World_Light_Gray_Base/MapServer/tile/{z}/{y}/{x}", {
    maxZoom: 17, maxNativeZoom: 16, attribution: "Basemap © Esri · Streets © OpenStreetMap contributors · City of Toronto",
  }).addTo(map);
  map.createPane("labels").style.zIndex = 450;
  map.getPane("labels").style.pointerEvents = "none";
  L.tileLayer(esri + "World_Light_Gray_Reference/MapServer/tile/{z}/{y}/{x}", { maxZoom: 17, maxNativeZoom: 16, pane: "labels" }).addTo(map);

  const [firstRisk, lanesFC, ksiFC, wardsFC] = await Promise.all([
    loadRisk(), getJSON(DATA + "city/bike_lanes.geojson"),
    getJSON(DATA + "city/cyclist_ksi_2022_2026.geojson"), getJSON(DATA + "city/wards.geojson"),
  ]);
  // File order is the stable id behind #injury= and #lane=.
  for (const fc of [lanesFC, ksiFC]) fc?.features.forEach((f, i) => { f.id = i; });

  // Live 4sight layer, else the static files mapped onto the same shape (one feature per street).
  async function loadRisk() {
    const live = await getJSON(test ? `${LIVE}?demo=1` : LIVE);
    if (live?.features?.length) return {
      segments: live.features.filter((f) => f.geometry.type !== "Point"),
      passes: live.features.filter((f) => f.properties.kind === "pass"),
    };
    const [ev, rides] = await Promise.all(["events", "rides"].map((n) => getJSON(`${DATA}${n}.geojson`)));
    if (!ev || !rides) return { segments: [], passes: [] };
    const by = {};
    for (const f of rides.features) {
      const s = (by[f.properties.street] ||= { km: 0, syn: 0, lane: false, lines: [] });
      s.km += f.properties.km; s.syn += f.properties.synthetic ? f.properties.km : 0;
      s.lane ||= f.properties.bike_lane; s.lines.push(f.geometry.coordinates);
    }
    const n = {};
    for (const f of ev.features) n[f.properties.street] = (n[f.properties.street] || 0) + 1;
    return {
      segments: Object.entries(by).map(([street, s]) => ({ type: "Feature", geometry: { type: "MultiLineString", coordinates: s.lines },
        properties: { street, km: s.km, passes: n[street] || 0, per_100km: 100 * (n[street] || 0) / s.km,
          lane_type: s.lane ? "lane" : "none", synthetic_share: s.syn / s.km } })),
      passes: ev.features.map((f) => ({ ...f, properties: { ...f.properties, lane_type: f.properties.bike_lane ? "lane" : "none" } })),
    };
  }

  // Wards: City totals, plus the close passes inside each one (counted in useRisk).
  const wards = (wardsFC?.features || []).map((f) => ({ f, ...f.properties, passes: 0 })).sort((a, b) => a.ward - b.ward);
  const wardAt = ([x, y]) => wards.find((w) => inPolygon([x, y], w.f.geometry));
  const sum = (k) => wards.reduce((a, w) => a + +w[k], 0);

  // Layers, back to front: lanes thin and light, close-pass streets, injury dots, single passes.
  let on = new Set(ALL), current = null, highlight = null;
  const solo = (name) => on.size === 1 && on.has(name);
  const isLane = (...t) => (f) => t.includes(f.properties.lane_type);
  const laneStyle = (f) => {
    const t = f.properties.lane_type, full = solo("lanes");
    return { color: LANE[t][0], weight: full ? (t === "protected" ? 4 : 3) : (t === "protected" ? 2.5 : 1.5),
      opacity: full ? 0.9 : t === "protected" ? 0.55 : 0.45, dashArray: t === "shared" ? "6 5" : null };
  };
  const laneLayer = (filter) => lanesFC && L.geoJSON(lanesFC, { filter, style: laneStyle,
    onEachFeature: (f, l) => l.on("click", () => go("lane", f.id)) });
  const lanesMain = laneLayer(isLane("protected", "painted"));
  const lanesExtra = laneLayer(isLane("shared", "trail")); // only when bike lanes are the only layer
  const killed = (f) => f.properties.outcome === "killed";
  // Injury dots grow with zoom, so 155 of them stay quiet at city scale.
  const ksiStyle = (f) => {
    const s = Math.min(1, Math.max(0.55, (map.getZoom() - 9) / 4));
    return killed(f) ? { radius: 5 * s, color: RED, weight: 2.5 * s, fillColor: INK, fillOpacity: 1 }
      : { radius: 3.5 * s, color: "#fff", weight: s, fillColor: INK, fillOpacity: 0.75 };
  };
  const ksi = ksiFC && L.geoJSON({ ...ksiFC, features: [...ksiFC.features].sort((a, b) => killed(a) - killed(b)) }, {
    pointToLayer: (f, ll) => L.circleMarker(ll, ksiStyle(f)),
    onEachFeature: (f, l) => {
      l.bindTooltip(() => `Cyclist ${killed(f) ? "killed" : "seriously injured"}, ${esc(f.properties.date)}`);
      l.on("click", () => go("injury", f.id));
    },
  });
  // Everything built from the 4sight data, rebuilt when test rides are switched on or off.
  let risk, streets, streetList, totKm, totPasses, share, casing, segs, dots, testDots, cards;
  const segStyle = (f) => {
    const any = current?.k === "street", hit = any && key(current.v) === key(f.properties.street);
    return { color: band(f.properties.per_100km)[1], weight: hit ? 7 : 4, opacity: any && !hit ? 0.35 : 1, lineCap: "round" };
  };
  const passKey = (f) => f.geometry.coordinates.slice(0, 2).reverse().map((c) => c.toFixed(5)).join(",");
  // With a street open, other streets' dots fade like their lines.
  const dotStyle = (f) => {
    const fade = current?.k === "street" && key(current.v) !== key(f.properties.street);
    return { radius: 4, color: "#fff", weight: 1.5, opacity: fade ? 0.3 : 1, fillOpacity: fade ? 0.3 : 1, fillColor: f.properties.level >= 3 ? "#E8453C" : "#F5A623" };
  };
  // Test rides: a blue ring, at every zoom, so the stage pass shows at city scale.
  const testStyle = (f) => ({ radius: 6.5, color: "#0A6CDF", weight: 3, fillOpacity: 1, fillColor: f.properties.level >= 3 ? "#E8453C" : "#F5A623" });
  function useRisk(r) {
    risk = r;
    // Per-street totals. The server's street_* fields total every segment of a street (short
    // ones too), so they match the dots; older data is summed here.
    streets = {};
    for (const f of risk.segments) {
      const p = f.properties, s = (streets[key(p.street)] ||= { name: p.street, km: 0, passes: 0, segKm: 0, syn: 0, totals: {}, hours: {}, cls: {}, imminent: 0, test: 0 });
      if (p.street.length > s.name.length) s.name = p.street;
      s.km += p.km; s.passes += p.passes; s.segKm += p.km; s.syn += p.synthetic_share * p.km;
      if (p.street_km != null) s.totals[p.street] = [p.street_km, p.street_passes];
    }
    for (const s of Object.values(streets)) {
      const t = Object.values(s.totals);
      if (t.length) [s.km, s.passes] = t.reduce(([k, n], [k2, n2]) => [k + k2, n + n2], [0, 0]);
    }
    for (const f of risk.passes) {
      const p = f.properties, s = streets[key(p.street)];
      if (!s) continue;
      if (p.level >= 3) s.imminent++;
      if (p.demo) s.test++;
      if (p.hour != null) s.hours[p.hour] = (s.hours[p.hour] || 0) + 1;
      if (p.cls) s.cls[p.cls] = (s.cls[p.cls] || 0) + 1;
    }
    streetList = Object.entries(streets).filter(([, s]) => s.km > 0)
      .map(([k, s]) => (streets[k] = { ...s, key: k, rate: 100 * s.passes / s.km, share: s.syn / s.segKm, short: s.km < MIN_KM }))
      .sort((a, b) => a.short - b.short || b.rate - a.rate);
    totKm = streetList.reduce((a, s) => a + s.km, 0); totPasses = streetList.reduce((a, s) => a + s.passes, 0);
    const segKm = streetList.reduce((a, s) => a + s.segKm, 0);
    share = segKm ? streetList.reduce((a, s) => a + s.syn, 0) / segKm : 0;
    for (const w of wards) w.passes = 0;
    for (const p of risk.passes) {
      const w = wardAt(p.geometry.coordinates);
      if (w) w.passes++;
    }
    for (const l of [casing, segs, dots, testDots]) l && map.removeLayer(l);
    const segsSorted = [...risk.segments].sort((a, b) => a.properties.per_100km - b.properties.per_100km);
    casing = L.geoJSON({ type: "FeatureCollection", features: segsSorted }, { interactive: false, style: { color: "#fff", weight: 7, opacity: 0.85 } });
    segs = L.geoJSON({ type: "FeatureCollection", features: segsSorted }, {
      style: segStyle,
      onEachFeature: (f, l) => {
        const s = streets[key(f.properties.street)];
        l.bindTooltip(() => `<b>${esc(s.name)}</b><br>${fmt(100 * s.passes / s.km)} close passes per 100 km`, { sticky: true });
        l.on("click", () => go("street", s.name));
      },
    });
    dots = L.geoJSON({ type: "FeatureCollection", features: risk.passes.filter((f) => !f.properties.demo).sort((a, b) => a.properties.level - b.properties.level) }, {
      pointToLayer: (f, ll) => L.circleMarker(ll, dotStyle(f)),
      onEachFeature: (f, l) => l.on("click", () => go("pass", passKey(f))),
    });
    cards = makeCards({ streets, wards, wardAt, risk, ksiFC, lanesFC, segs, share, LANE, VEHICLE, passKey });
    testDots = L.geoJSON({ type: "FeatureCollection", features: risk.passes.filter((f) => f.properties.demo) }, {
      pointToLayer: (f, ll) => L.circleMarker(ll, testStyle(f)),
      onEachFeature: (f, l) => {
        l.bindTooltip("Test ride: close pass");
        l.on("click", () => go("pass", passKey(f)));
      },
    });
    const pill = share > 0 ? `<span class="pill">Example data</span>` : `<span class="pill real">Real rides</span>`;
    STAT.passes = [fmt(100 * totPasses / totKm), "close passes per 100 km ridden", pill];
    STORY.passes = [STAT.passes[0], "close passes for every 100 km ridden", `${PASS_TEXT} Red streets have the most for the distance ridden. Zoom in to see each one.`, pill, share > 0 ? EXAMPLE_TEXT : "Close passes from 4sight riders."];
  }

  function drawLayers() {
    const want = [
      on.has("lanes") && lanesMain, solo("lanes") && lanesExtra,
      on.has("passes") && casing, on.has("passes") && segs,
      on.has("injuries") && ksi, on.has("passes") && map.getZoom() >= DOT_ZOOM && dots, on.has("passes") && test && testDots,
    ].filter(Boolean);
    for (const l of [lanesMain, lanesExtra, casing, segs, ksi, dots, testDots]) l && map.removeLayer(l);
    for (const l of want) l.addTo(map);
    lanesMain?.setStyle(laneStyle);
    lanesExtra?.setStyle(laneStyle);
    highlight?.bringToFront();
  }
  map.on("zoomend", () => ksi?.setStyle(ksiStyle));
  map.on("zoomend", () => { if (on.has("passes") && (map.getZoom() >= DOT_ZOOM) !== map.hasLayer(dots)) drawLayers(); });

  // Sheet summary: one story for one layer, a row of three stats for several, a hint for none.
  const cityPill = `<span class="pill city">City of Toronto</span>`;
  const ksiCount = ksiFC?.features.length, killedCount = ksiFC?.features.filter(killed).length;
  const protectedKm = wards.length ? Math.round(sum("protected_km")) : null;
  const PASS_TEXT = "A close pass is when a vehicle overtakes a rider too close, detected by a rear-facing camera on the bike.";
  const EXAMPLE_TEXT = "Computer-generated near misses that show how the map will work. The first real rides are in, labelled Real ride.";
  const STAT = {
    passes: null, // set by useRisk
    injuries: [ksiCount ?? "–", "cyclists killed or seriously injured since 2022", cityPill],
    lanes: [protectedKm ?? "–", "km of protected bike lanes", cityPill],
  };
  const STORY = {
    passes: null, // set by useRisk
    injuries: [STAT.injuries[0], "cyclists killed or seriously injured", ksiFC ? `On Toronto streets, 2022 to October 2026. ${killedCount} were killed. These are totals, not rates per rider: far more people ride downtown.` : "City injury data could not be loaded.", cityPill, "Vision Zero, 2022 to October 2026."],
    lanes: [STAT.lanes[0], "km of protected bike lanes", wards.length ? `Plus about ${Math.round(sum("painted_km"))} km of painted lanes, ${Math.round(sum("shared_km"))} km of shared routes and ${Math.round(sum("trail_km"))} km of trails.` : "City bike lane data could not be loaded.", cityPill, "Cycling network, October 2026. Lengths are approximate."],
  };
  const LEGEND = {
    passes: ["Close passes per 100 km", BAND.map(([, c, label]) => `<li><i style="background:${c}"></i>${label}</li>`)],
    injuries: ["Cyclists killed or seriously injured", [`<li><i class="dot killed"></i>Killed</li>`, `<li><i class="dot" style="background:${INK}"></i>Seriously injured</li>`]],
    lanes: ["City bike lanes", []], // filled per render: shared routes and trails only when lanes are alone
  };
  function renderSummary() {
    const layers = ALL.filter((l) => on.has(l));
    let html;
    if (!layers.length) html = `<p class="lede">All layers are off. Turn one on to see it on the map.</p>`;
    else if (layers.length === 1) {
      const [num, unit, text, pill, source] = STORY[layers[0]];
      html = `<p class="big"><span class="num">${num}</span> <span class="unit">${unit}</span></p><p class="lede">${text}</p><p class="source">${pill} <span>${source}</span></p>`;
    } else {
      html = `<ul class="stats">${layers.map((l) => `<li><b>${STAT[l][0]}</b><span>${STAT[l][1]}</span>${STAT[l][2]}</li>`).join("")}</ul>`
        + (on.has("passes") ? `<p class="lede">${PASS_TEXT}${share > 0 ? " Most are example data: computer-generated near misses that show how the map will work; the first real rides are in." : ""}</p>` : "");
    }
    const nTest = test ? risk.passes.filter((f) => f.properties.demo).length : 0;
    if (on.has("passes") && test) html += `<p class="lede">Including test rides: ${nTest} close pass${nTest === 1 ? "" : "es"} from test rides, ringed in blue.</p>`;
    LEGEND.passes[1] = BAND.map(([, c, label]) => `<li><i style="background:${c}"></i>${label}</li>`)
      .concat(test ? [`<li><i class="dot test"></i>Test ride</li>`] : []);
    LEGEND.lanes = ["City bike lanes", Object.entries(LANE).filter(([t]) => solo("lanes") || t === "protected" || t === "painted")
      .map(([, [c, label]]) => `<li><i style="background:${c}"></i>${label}</li>`)];
    html += layers.length ? `<div class="legend" aria-label="Map key">${layers.map((l) =>
      `<div><h3>${LEGEND[l][0]}</h3><ul>${LEGEND[l][1].join("")}</ul></div>`).join("")}</div>` : "";
    $("story").innerHTML = html;
    document.querySelectorAll(".chip").forEach((b) => b.setAttribute("aria-pressed", String(on.has(b.dataset.layer))));
    $("test").checked = test;
  }

  // URL: #<card>=<value>&layers=a,b. No layers parameter means all on.
  const enc = (v) => encodeURIComponent(v).replace(/%2C/g, ",");
  const hashFor = (k, v, layers = on, t = test) => {
    const q = [k && `${k}=${enc(v)}`, layers.size !== ALL.length && `layers=${ALL.filter((l) => layers.has(l)).join(",")}`, t && "test=1"].filter(Boolean);
    return q.length ? `#${q.join("&")}` : location.pathname + location.search;
  };
  const readHash = () => {
    const q = new URLSearchParams(location.hash.slice(1));
    const k = Object.keys(cards).find((c) => q.has(c));
    return { k, v: k && q.get(k), test: q.get("test") === "1", layers: new Set(q.has("layers") ? q.get("layers").split(",").filter((l) => ALL.includes(l)) : ALL) };
  };
  function setLayers(layers) {
    on = layers;
    drawLayers();
    renderSummary();
    renderList();
  }
  function toggle(layer) {
    const next = new Set(on);
    next.has(layer) ? next.delete(layer) : next.add(layer);
    history.replaceState(history.state, "", hashFor(current?.k, current?.v, next));
    routed = location.hash;
    setLayers(next);
  }

  // Router: the hash is the only state; Back, reloads and shared links all land here.
  const baseTitle = document.title;
  let routed = null;
  function go(k, v) {
    const h = hashFor(k, v);
    if (h === location.hash) return;
    history.pushState({ app: true }, "", h);
    route();
  }
  function route() {
    if (location.hash === routed) return;
    const wasDetail = !$("detail").hidden;
    const r = readHash();
    if (r.test !== test) return switchTest(r.test);
    const d = r.k && cards[r.k](r.v);
    if (d?.layer && !r.layers.has(d.layer)) r.layers.add(d.layer); // a card always shows its own layer
    current = d ? { k: r.k, v: r.v } : null;
    const want = hashFor(current?.k, current?.v, r.layers);
    if (want !== (location.hash || location.pathname + location.search)) history.replaceState(history.state, "", want);
    routed = location.hash;
    if (highlight) map.removeLayer(highlight);
    highlight = null;
    setLayers(r.layers);
    segs.setStyle(segStyle);
    dots.setStyle(dotStyle);
    $("home").hidden = !!d;
    $("detail").hidden = !d;
    $("copy-status").textContent = "";
    $("sheet").scrollTop = 0;
    document.title = d ? `${d.title} · 4sight` : baseTitle;
    if (!d) return wasDetail && $("home-title").focus({ preventScroll: true });
    $("detail-kicker").textContent = d.kicker;
    $("detail-title").textContent = d.title;
    $("detail-body").innerHTML = d.html;
    highlight = d.mark?.addTo(map) || null;
    fit(d.bounds, d.zoom);
    $("detail-title").focus({ preventScroll: true });
  }
  // Test rides on or off: refetch the 4sight layer, rebuild, then route again with the new data.
  let loading = 0;
  async function switchTest(t) {
    const mine = ++loading;
    test = t;
    $("test").checked = t;
    $("sheet").setAttribute("aria-busy", "true");
    const r = await loadRisk();
    if (mine !== loading) return; // a newer switch won
    useRisk(r);
    $("sheet").removeAttribute("aria-busy");
    routed = null;
    route();
  }
  $("test").addEventListener("change", (e) => {
    history.replaceState(history.state, "", hashFor(current?.k, current?.v, on, e.target.checked));
    switchTest(e.target.checked);
  });
  addEventListener("hashchange", route);
  addEventListener("popstate", route);
  $("back").addEventListener("click", () => {
    if (history.state?.app) return history.back();
    history.pushState(null, "", hashFor(null, null)); // arrived by a shared link
    route();
  });
  $("detail").addEventListener("click", (e) => {
    const b = e.target.closest("[data-go]");
    if (!b) return;
    const i = b.dataset.go.indexOf("=");
    go(b.dataset.go.slice(0, i), b.dataset.go.slice(i + 1));
  });
  $("copy").addEventListener("click", async () => {
    try { await navigator.clipboard.writeText(location.href); $("copy-status").textContent = "Copied"; }
    catch { $("copy-status").textContent = location.href; } // no clipboard access: show it to copy by hand
  });

  // Click on the map away from anything clickable: the ward under it.
  map.on("click", (e) => {
    const w = wardAt([e.latlng.lng, e.latlng.lat]);
    if (w) go("ward", w.ward);
  });

  // List of streets and wards: the non-map way to the same numbers.
  function renderList() {
    const q = $("q").value.trim().toLowerCase();
    const st = streetList.filter((s) => s.name.toLowerCase().includes(q));
    const wd = wards.filter((w) => w.ward_name.toLowerCase().includes(q) || `ward ${w.ward}`.includes(q) || String(w.ward) === q);
    const wardFacts = (w) => [`${w.passes} close passes`, `${w.cyclist_ksi} killed or injured`, `${fmt(+w.protected_km)} km protected`];
    $("results").innerHTML = (st.length ? `<h3>Streets · close passes per 100 km</h3><ul>${st.map((s) =>
      `<li><a class="row" href="${esc(hashFor("street", s.name))}"><span class="sw" style="background:${band(s.rate)[1]}"></span>
        <span class="name">${esc(s.name)}<small>${fmt(s.km, 0)} km ridden${s.short ? ", too little to compare" : ""}</small></span>
        <span class="val">${fmt(s.rate)}<small>${s.passes} passes</small></span></a></li>`).join("")}</ul>` : "")
      + (wd.length ? `<h3>Wards</h3><ul>${wd.map((w) =>
      `<li><a class="row" href="${esc(hashFor("ward", w.ward))}"><span class="name">${esc(w.ward_name)}<small>Ward ${w.ward} · ${esc(wardFacts(w).join(" · "))}</small></span></a></li>`).join("")}</ul>` : "")
      || `<p class="empty">No street or ward matches “${esc(q)}”.</p>`;
  }
  $("q").addEventListener("input", renderList);
  // Rows are real links (open in a new tab works); a plain click goes through the router.
  $("results").addEventListener("click", (e) => {
    const a = e.target.closest("a.row");
    if (!a || e.metaKey || e.ctrlKey || e.shiftKey || e.altKey) return;
    e.preventDefault();
    const r = new URLSearchParams(a.getAttribute("href").slice(1));
    r.has("street") ? go("street", r.get("street")) : go("ward", r.get("ward"));
  });
  document.querySelectorAll(".chip").forEach((b) => b.addEventListener("click", () => toggle(b.dataset.layer)));
  document.querySelectorAll("[data-dialog]").forEach((b) => b.addEventListener("click", () => $(b.dataset.dialog).showModal()));
  $("handle").addEventListener("click", () => {
    const open = $("sheet").dataset.open !== "true";
    $("sheet").dataset.open = String(open);
    $("handle").setAttribute("aria-expanded", String(open));
  });

  // Keep what we zoom to clear of the sheet.
  function fit(bounds, maxZoom = 15) {
    if (!bounds?.isValid()) return;
    const stage = map.getContainer().getBoundingClientRect(), sheet = $("sheet").getBoundingClientRect();
    map.fitBounds(bounds, innerWidth <= 760
      ? { paddingTopLeft: [24, 24], paddingBottomRight: [24, stage.bottom - sheet.top + 24], maxZoom }
      : { paddingTopLeft: [sheet.right - stage.left + 32, 32], paddingBottomRight: [72, 32], maxZoom });
  }

  useRisk(firstRisk);
  if (risk.segments.length) fit(casing.getBounds());
  route();
})();
