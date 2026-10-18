// 4sight public map, variant A: a full-bleed light map plus one sheet, like the app's home
// screen. Three stories share the map (close passes, injuries, bike lanes); the sheet's list of
// streets and wards carries the same numbers as the map for anyone not using it. Everything
// clickable opens a detail view at its own URL (#street=, #ward=, #pass=lat,lon, #injury=, #lane=).
(async function () {
  const $ = (id) => document.getElementById(id);
  const esc = (s) => String(s ?? "").replace(/[&<>"]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" })[c]);
  const fmt = (x, d = 1) => x == null || !isFinite(x) ? "–" : x.toFixed(d);
  const DATA = "../../data/";
  const LIVE = "https://4sight-server.vercel.app/v1/city-risk.geojson";
  const BAND = [[0, "#B4BAC3", "None yet"], [30, "#F5C46B", "Fewer than 30"], [60, "#F5A623", "30 to 60"], [Infinity, "#E8453C", "60 or more"]];
  const band = (r) => r <= 0 ? BAND[0] : BAND.find(([max], i) => i && r < max);
  const LANE = {
    protected: ["#1E7A37", "Protected lane"], painted: ["#0A6CDF", "Painted lane"],
    shared: ["#8C95A1", "Shared route"], trail: ["#7DB38C", "Trail"],
  };
  const VEHICLE = { car: ["cars", "A car"], truck: ["trucks", "A truck"], bus: ["buses", "A bus"], motorcycle: ["motorcycles", "A motorcycle"], bicycle: ["bicycles", "Another bike"] };
  const DOT_ZOOM = 14; // single close passes show from this zoom in
  const getJSON = (u) => fetch(u).then((r) => r.ok ? r.json() : null).catch(() => null);

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

  const [risk, lanesFC, ksiFC, wardsFC] = await Promise.all([
    loadRisk(), getJSON(DATA + "city/bike_lanes.geojson"),
    getJSON(DATA + "city/cyclist_ksi_2022_2026.geojson"), getJSON(DATA + "city/wards.geojson"),
  ]);
  // File order is the stable id behind #injury= and #lane=.
  for (const fc of [lanesFC, ksiFC]) fc?.features.forEach((f, i) => { f.id = i; });

  // Live 4sight layer, else the static files mapped onto the same shape (one feature per street).
  async function loadRisk() {
    const live = await getJSON(LIVE);
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

  // Per-street totals for the list and detail views. The server's street_* fields total every
  // segment of a street (short ones too), so they match the dots; older data is summed here.
  // Names group on a normalised key so "Bloor St W" and "Bloor Street West" are one street.
  const key = (n) => String(n ?? "").toLowerCase().replace(/\./g, "").replace(/\bstreet\b/g, "st").replace(/\bavenue\b/g, "ave")
    .replace(/\broad\b/g, "rd").replace(/\beast\b/g, "e").replace(/\bwest\b/g, "w").replace(/\s+/g, " ").trim();
  const streets = {};
  for (const f of risk.segments) {
    const p = f.properties, s = (streets[key(p.street)] ||= { name: p.street, km: 0, passes: 0, segKm: 0, syn: 0, totals: {}, lanes: new Set(), hours: {}, cls: {}, imminent: 0 });
    if (p.street.length > s.name.length) s.name = p.street;
    s.km += p.km; s.passes += p.passes; s.segKm += p.km; s.syn += p.synthetic_share * p.km;
    if (p.street_km != null) s.totals[p.street] = [p.street_km, p.street_passes];
    if (p.lane_type && p.lane_type !== "none") s.lanes.add(p.lane_type);
  }
  for (const s of Object.values(streets)) {
    const t = Object.values(s.totals);
    if (t.length) [s.km, s.passes] = t.reduce(([k, n], [k2, n2]) => [k + k2, n + n2], [0, 0]);
  }
  for (const f of risk.passes) {
    const p = f.properties, s = streets[key(p.street)];
    if (!s) continue;
    if (p.level >= 3) s.imminent++;
    if (p.hour != null) s.hours[p.hour] = (s.hours[p.hour] || 0) + 1;
    if (p.cls) s.cls[p.cls] = (s.cls[p.cls] || 0) + 1;
  }
  // Under this many km ridden a rate is too noisy to rank, so those streets list last.
  const MIN_KM = 10;
  const top = (o) => Object.entries(o).sort((a, b) => b[1] - a[1])[0]?.[0];
  const streetList = Object.entries(streets).filter(([, s]) => s.km > 0)
    .map(([k, s]) => (streets[k] = { ...s, key: k, rate: 100 * s.passes / s.km, share: s.syn / s.segKm, short: s.km < MIN_KM }))
    .sort((a, b) => a.short - b.short || b.rate - a.rate);
  const totKm = streetList.reduce((a, s) => a + s.km, 0), totPasses = streetList.reduce((a, s) => a + s.passes, 0);
  const segKm = streetList.reduce((a, s) => a + s.segKm, 0);
  const share = segKm ? streetList.reduce((a, s) => a + s.syn, 0) / segKm : 0;

  // Wards: City totals plus the close passes that fall inside each one.
  const wards = (wardsFC?.features || []).map((f) => ({ f, ...f.properties, passes: 0 })).sort((a, b) => a.ward - b.ward);
  const wardAt = ([x, y]) => wards.find((w) => inPolygon([x, y], w.f.geometry));
  for (const p of risk.passes) {
    const w = wardAt(p.geometry.coordinates);
    if (w) w.passes++;
  }
  const sum = (k) => wards.reduce((a, w) => a + +w[k], 0);

  // Layers. One canvas; added back to front.
  let story = "passes", current = null, highlight = null;
  const faintLanes = lanesFC && L.geoJSON(lanesFC, {
    interactive: false, filter: (f) => f.properties.lane_type === "protected" || f.properties.lane_type === "painted",
    style: (f) => ({ color: LANE[f.properties.lane_type][0], weight: 2, opacity: 0.22 }),
  });
  const lanesFull = lanesFC && L.geoJSON(lanesFC, {
    style: (f) => {
      const t = f.properties.lane_type;
      return { color: LANE[t]?.[0] || "#8C95A1", weight: t === "protected" ? 4 : t === "painted" ? 3 : 2.5, opacity: 0.9, dashArray: t === "shared" ? "6 5" : null };
    },
    onEachFeature: (f, l) => l.on("click", () => go(`lane=${f.id}`)),
  });
  const segsSorted = [...risk.segments].sort((a, b) => a.properties.per_100km - b.properties.per_100km);
  const casing = L.geoJSON({ type: "FeatureCollection", features: segsSorted }, { interactive: false, style: { color: "#fff", weight: 8, opacity: 0.9 } });
  const segStyle = (f) => {
    const any = current?.k === "street", on = any && key(current.v) === key(f.properties.street);
    return { color: band(f.properties.per_100km)[1], weight: on ? 8 : 4.5, opacity: any && !on ? 0.35 : 1, lineCap: "round" };
  };
  const segs = L.geoJSON({ type: "FeatureCollection", features: segsSorted }, {
    style: segStyle,
    onEachFeature: (f, l) => {
      const s = streets[key(f.properties.street)];
      l.bindTooltip(() => `<b>${esc(s.name)}</b><br>${fmt(100 * s.passes / s.km)} close passes per 100 km`, { sticky: true });
      l.on("click", () => go(`street=${encodeURIComponent(s.name)}`));
    },
  });
  const passKey = (f) => f.geometry.coordinates.slice(0, 2).reverse().map((c) => c.toFixed(5)).join(",");
  const dots = L.geoJSON({ type: "FeatureCollection", features: [...risk.passes].sort((a, b) => a.properties.level - b.properties.level) }, {
    pointToLayer: (f, ll) => L.circleMarker(ll, { radius: 5, color: "#fff", weight: 1.5, fillOpacity: 1, fillColor: f.properties.level >= 3 ? "#E8453C" : "#F5A623" }),
    onEachFeature: (f, l) => l.on("click", () => go(`pass=${passKey(f)}`)),
  });
  const killed = (f) => f.properties.outcome === "killed";
  const ksi = ksiFC && L.geoJSON({ ...ksiFC, features: [...ksiFC.features].sort((a, b) => killed(a) - killed(b)) }, {
    pointToLayer: (f, ll) => L.circleMarker(ll, killed(f)
      ? { radius: 8, color: "#fff", weight: 2, fillColor: "#D93025", fillOpacity: 1 }
      : { radius: 5, color: "#fff", weight: 1.5, fillColor: "#F5A623", fillOpacity: 1 }),
    onEachFeature: (f, l) => l.on("click", () => go(`injury=${f.id}`)),
  });

  const STORIES = {
    passes: {
      layers: [faintLanes, casing, segs],
      num: fmt(100 * totPasses / totKm), unit: "close passes for every 100 km ridden",
      text: "A close pass is when a vehicle overtakes a rider too close, detected by a rear-facing camera on the bike. Red streets have the most for the distance ridden. Zoom in to see each one.",
      pill: share >= 0.999 ? ["Example data", ""] : share > 0 ? ["Includes example data", ""] : ["Real rides", "real"],
      source: share > 0 ? "Computer-generated near misses that show how the map will work. Not real rides yet." : "Close passes from 4sight riders.",
      legend: [...BAND.map(([, c, label]) => [c, label]), ["#0A6CDF", "Bike lane", 0.3]],
      ward: (w) => [w.passes, "close passes"],
    },
    injuries: {
      layers: [faintLanes, ksi],
      num: ksiFC ? String(ksiFC.features.length) : "–", unit: "cyclists killed or seriously injured",
      text: ksiFC ? `On Toronto streets, 2022 to October 2026. ${ksiFC.features.filter(killed).length} were killed. These are totals, not rates per rider: far more people ride downtown.` : "City injury data could not be loaded.",
      pill: ["City of Toronto", "city"], source: "Vision Zero, 2022 to October 2026.",
      legend: [["#D93025", "Killed", 1, "dot big"], ["#F5A623", "Seriously injured", 1, "dot"]],
      ward: (w) => [w.cyclist_ksi, "killed or injured"],
    },
    lanes: {
      layers: [lanesFull],
      num: wards.length ? String(Math.round(sum("protected_km"))) : "–", unit: "km of protected bike lanes",
      text: wards.length ? `Plus about ${Math.round(sum("painted_km"))} km of painted lanes, ${Math.round(sum("shared_km"))} km of shared routes and ${Math.round(sum("trail_km"))} km of trails.` : "City bike lane data could not be loaded.",
      pill: ["City of Toronto", "city"], source: "Cycling network, October 2026. Lengths are approximate.",
      legend: Object.values(LANE).map(([c, label]) => [c, label]),
      ward: (w) => [fmt(+w.protected_km), "km protected"],
    },
  };

  function setStory(name) {
    story = name;
    const s = STORIES[name];
    for (const l of [faintLanes, lanesFull, casing, segs, dots, ksi]) l && map.removeLayer(l);
    for (const l of s.layers) l?.addTo(map);
    syncDots();
    highlight?.bringToFront();
    document.querySelectorAll(".chip").forEach((b) => b.setAttribute("aria-pressed", String(b.dataset.story === name)));
    $("big-num").textContent = s.num;
    $("big-unit").textContent = s.unit;
    $("big-text").textContent = s.text;
    $("pill").textContent = s.pill[0];
    $("pill").className = "pill " + s.pill[1];
    $("source-text").textContent = s.source;
    $("legend").innerHTML = s.legend.map(([c, label, op = 1, cls = ""]) =>
      `<li><i class="${cls}" style="background:${c};opacity:${op}"></i>${esc(label)}</li>`).join("");
    renderList();
  }
  function syncDots() {
    const want = story === "passes" && map.getZoom() >= DOT_ZOOM;
    if (want !== map.hasLayer(dots)) want ? dots.addTo(map) : map.removeLayer(dots);
  }
  map.on("zoomend", syncDots);

  // Click on the map away from anything clickable: the ward under it.
  map.on("click", (e) => {
    const w = wardAt([e.latlng.lng, e.latlng.lat]);
    if (w) go(`ward=${w.ward}`);
  });

  // Each detail: { story, kicker, title, html, bounds, mark (layer to draw on top) }.
  const sourceNote = (p) => p.synthetic ? `<p class="note"><span class="pill">Example data</span> Computer-generated to show how the map will work, not a real ride.</p>`
    : p.demo ? `<p class="note"><span class="pill">Test ride</span> One of our own trial rides.</p>` : `<p class="note"><span class="pill real">Real ride</span></p>`;
  const exampleNote = (sh) => sh > 0 ? sourceNote({ synthetic: true }).replace("not a real ride", "not real rides yet") : "";
  const wardLink = (w) => w ? `<li>In <button type="button" data-go="ward=${w.ward}">Ward ${esc(w.ward)}, ${esc(w.ward_name)}</button></li>` : "";
  const ring = (ll) => L.circleMarker(ll, { radius: 13, color: "#0A6CDF", weight: 3, fill: false, interactive: false });
  const hour = (h) => `${String(h).padStart(2, "0")}:00`;
  const DETAIL = {
    street(name) {
      const s = streets[key(name)];
      if (!s?.key) return null;
      const h = top(s.hours), c = top(s.cls);
      const lanes = [...s.lanes].filter((t) => t !== "shared").map((t) => LANE[t]?.[1].toLowerCase() || "bike lane");
      return { story: "passes", kicker: "Street", title: s.name,
        bounds: L.featureGroup(segs.getLayers().filter((l) => key(l.feature.properties.street) === s.key)).getBounds(),
        html: `<p class="stat"><b>${fmt(s.rate)}</b><span>close passes for every 100 km ridden</span></p>
        <ul class="facts"><li>${s.passes} close pass${s.passes === 1 ? "" : "es"} in ${fmt(s.km, 0)} km of riding</li>
        ${s.imminent ? `<li>${s.imminent} of them very close (the camera's strongest warning)</li>` : ""}
        ${h != null ? `<li>Most often around ${hour(h)}</li>` : ""}
        ${VEHICLE[c] ? `<li>Mostly ${VEHICLE[c][0]}</li>` : ""}
        <li>${lanes.length ? `Bike lane on part of it: ${esc(lanes.join(", "))}` : s.lanes.has("shared") ? "Shared route only, no bike lane" : "No bike lane where riders went"}</li></ul>
        ${s.short ? `<p class="note">Only ${fmt(s.km, 0)} km ridden here so far, too little to compare with other streets.</p>` : ""}
        ${exampleNote(s.share)}` };
    },
    ward(n) {
      const w = wards.find((w) => w.ward === +n);
      if (!w) return null;
      const mark = L.geoJSON(w.f, { interactive: false, style: { color: "#111418", weight: 2.5, opacity: 0.8, dashArray: "6 5", fillColor: "#0A6CDF", fillOpacity: 0.05 } });
      return { kicker: `Ward ${w.ward}`, title: w.ward_name, bounds: mark.getBounds(), mark,
        html: `<p class="stat"><b>${w.passes}</b><span>close passes in this ward</span></p>
        <ul class="facts"><li>${esc(w.cyclist_ksi)} cyclists killed or seriously injured, 2022 to October 2026 (${esc(w.fatal)} killed)</li>
        <li>${esc(w.protected_km)} km protected and ${esc(w.painted_km)} km painted bike lanes</li>
        <li>${esc(w.planned_km)} km of cycling projects planned for 2025 to 2027</li></ul>
        ${exampleNote(share)}<p class="note">Injury and lane figures: City of Toronto. Totals, not per rider.</p>` };
    },
    pass(v) {
      const f = risk.passes.find((f) => passKey(f) === v);
      if (!f) return null;
      const p = f.properties, ll = L.latLng(f.geometry.coordinates[1], f.geometry.coordinates[0]), s = streets[key(p.street)];
      return { story: "passes", kicker: p.level >= 3 ? "Very close pass" : "Close pass", zoom: 16, bounds: L.latLngBounds([ll, ll]), mark: ring(ll),
        title: `${VEHICLE[p.cls]?.[1] || "A vehicle"} passed too close${p.street ? ` on ${p.street}` : ""}`,
        html: `<ul class="facts">${p.level >= 3 ? "<li>Very close: the camera's strongest warning</li>" : ""}
        ${p.hour != null ? `<li>Around ${hour(p.hour)}</li>` : ""}
        <li>${LANE[p.lane_type] ? `On a ${esc(LANE[p.lane_type][1].toLowerCase())}` : p.lane_type === "lane" ? "On a bike lane" : "No bike lane here"}</li>
        ${s ? `<li>On <button type="button" data-go="street=${esc(encodeURIComponent(s.name))}">${esc(s.name)}</button>: ${fmt(s.rate)} close passes per 100 km</li>` : ""}
        ${wardLink(wardAt(f.geometry.coordinates))}</ul>${sourceNote(p)}` };
    },
    injury(i) {
      const f = ksiFC?.features[+i];
      if (!f || !/^\d+$/.test(i)) return null;
      const p = f.properties, ll = L.latLng(f.geometry.coordinates[1], f.geometry.coordinates[0]);
      const day = new Date(`${p.date}T12:00`).toLocaleDateString("en-CA", { year: "numeric", month: "long", day: "numeric" });
      return { story: "injuries", kicker: "City of Toronto, Vision Zero", zoom: 16, bounds: L.latLngBounds([ll, ll]), mark: ring(ll),
        title: `Cyclist ${killed(f) ? "killed" : "seriously injured"}`,
        html: `<ul class="facts"><li>${esc(day)}${p.time ? `, around ${esc(p.time)}` : ""}</li><li>${esc(titleCase(p.location))}</li>
        ${wardLink(wards.find((w) => w.ward === +p.ward))}</ul>
        <p class="note">From the City's record of cyclists killed or seriously injured. It does not say how the crash happened.</p>` };
    },
    lane(i) {
      const f = lanesFC?.features[+i];
      if (!f || !/^\d+$/.test(i)) return null;
      const p = f.properties, mark = L.geoJSON(f, { interactive: false, style: { color: "#0A6CDF", weight: 12, opacity: 0.25 } });
      return { story: "lanes", kicker: "City of Toronto cycling network", title: p.street || "Bike route", bounds: mark.getBounds(), mark,
        html: `<ul class="facts"><li>${esc(LANE[p.lane_type]?.[1] || "Bike route")}${p.city_infra_type ? ` (${esc(p.city_infra_type)})` : ""}</li>
        ${p.from_street || p.to_street ? `<li>${esc([p.from_street, p.to_street].filter(Boolean).join(" to "))}</li>` : ""}
        ${+p.installed ? `<li>Installed ${esc(p.installed)}${+p.upgraded ? `, upgraded ${esc(p.upgraded)}` : ""}</li>` : ""}</ul>` };
    },
  };
  const titleCase = (s) => String(s ?? "").toLowerCase().replace(/\b[a-z]/g, (c) => c.toUpperCase());

  // Router: the hash is the only state; Back, reloads and shared links all land here.
  const baseTitle = document.title;
  let routed = null;
  function go(hash) {
    if (location.hash.slice(1) === hash) return;
    history.pushState({ app: true }, "", `#${hash}`);
    route();
  }
  function route() {
    if (location.hash === routed) return;
    const wasDetail = !$("detail").hidden;
    routed = location.hash;
    const m = location.hash.match(/^#(\w+)=(.+)$/);
    const d = m && DETAIL[m[1]] && DETAIL[m[1]](decodeURIComponent(m[2]));
    if (highlight) map.removeLayer(highlight);
    highlight = null;
    current = d ? { k: m[1], v: decodeURIComponent(m[2]) } : null;
    if (m && !d) history.replaceState(null, "", location.pathname + location.search);
    if (d?.story && d.story !== story) setStory(d.story);
    segs.setStyle(segStyle);
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
  addEventListener("hashchange", route);
  addEventListener("popstate", route);
  $("back").addEventListener("click", () => {
    if (history.state?.app) return history.back();
    history.pushState(null, "", location.pathname + location.search); // arrived by a shared link
    route();
  });
  $("detail").addEventListener("click", (e) => { const b = e.target.closest("[data-go]"); if (b) go(b.dataset.go); });
  $("copy").addEventListener("click", async () => {
    try { await navigator.clipboard.writeText(location.href); $("copy-status").textContent = "Copied"; }
    catch { $("copy-status").textContent = location.href; } // no clipboard access: show it to copy by hand
  });

  // List of streets and wards: the non-map way to the same numbers.
  function renderList() {
    const q = $("q").value.trim().toLowerCase();
    const st = streetList.filter((s) => s.name.toLowerCase().includes(q));
    const wd = wards.filter((w) => w.ward_name.toLowerCase().includes(q) || `ward ${w.ward}`.includes(q) || String(w.ward) === q);
    const wv = STORIES[story].ward;
    $("results").innerHTML = (st.length ? `<h3>Streets · close passes per 100 km</h3><ul>${st.map((s) =>
      `<li><a class="row" href="#street=${esc(encodeURIComponent(s.name))}"><span class="sw" style="background:${band(s.rate)[1]}"></span>
        <span class="name">${esc(s.name)}<small>${fmt(s.km, 0)} km ridden${s.short ? ", too little to compare" : ""}</small></span>
        <span class="val">${fmt(s.rate)}<small>${s.passes} passes</small></span></a></li>`).join("")}</ul>` : "")
      + (wd.length ? `<h3>Wards · ${esc(wv(wd[0])[1])}</h3><ul>${wd.map((w) =>
      `<li><a class="row" href="#ward=${w.ward}"><span class="name">${esc(w.ward_name)}<small>Ward ${w.ward}</small></span>
        <span class="val">${esc(wv(w)[0])}</span></a></li>`).join("")}</ul>` : "")
      || `<p class="empty">No street or ward matches “${esc(q)}”.</p>`;
  }
  $("q").addEventListener("input", renderList);
  // Rows are real links (open in a new tab works); a plain click goes through the router.
  $("results").addEventListener("click", (e) => {
    const a = e.target.closest("a.row");
    if (!a || e.metaKey || e.ctrlKey || e.shiftKey || e.altKey) return;
    e.preventDefault();
    go(a.getAttribute("href").slice(1));
  });
  document.querySelectorAll(".chip").forEach((b) => b.addEventListener("click", () => setStory(b.dataset.story)));
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

  setStory("passes");
  if (risk.segments.length) fit(casing.getBounds());
  route();
})();

// Even-odd ray cast over every ring, so holes and multipolygons count right.
function inPolygon([x, y], geom) {
  const rings = geom.type === "Polygon" ? geom.coordinates : geom.coordinates.flat();
  let inside = false;
  for (const ring of rings) {
    for (let i = 0, j = ring.length - 1; i < ring.length; j = i++) {
      const [xi, yi] = ring[i], [xj, yj] = ring[j];
      if ((yi > y) !== (yj > y) && x < (xj - xi) * (y - yi) / (yj - yi) + xi) inside = !inside;
    }
  }
  return inside;
}
