// 4sight ward explorer: the 25 wards shaded by one measure. Every clickable thing (ward, close-pass
// street, close-pass point, City injury point) opens a small page in the sheet with its own hash
// (#ward=10, #street=Bloor%20Street%20West, #pass=43.66195,-79.36707, #injury=12), so links share.
(async function () {
  const BLUE_SOFT = [0xDF, 0xE8, 0xF5], BLUE = [0x0A, 0x6C, 0xDF];
  const COL = { ink: "#111418", red: "#D93025", green: "#1E7A37", blue: "#0A6CDF", pass: "#F5A623", amber: "#B86E00", imminent: "#E8453C" };
  const reduced = matchMedia("(prefers-reduced-motion: reduce)").matches;
  const $ = (id) => document.getElementById(id);
  const fmt = (x, d = 1) => x.toFixed(d);
  const esc = (s) => String(s).replace(/[&<>"]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[c]));
  const plural = (n, one, many) => `${n} ${n === 1 ? one : many}`;
  const hourLabel = (h) => `${String(h).padStart(2, "0")}:00`;
  const VEHICLE = { car: "Car", truck: "Truck", bus: "Bus", motorcycle: "Motorcycle", bicycle: "Bicycle", person: "Person" };
  const LANE = { protected: "Protected bike lane", painted: "Painted bike lane", shared: "Shared road markings", none: "No bike lane" };
  const source = (p) => p.synthetic ? ["Example data", ""] : p.demo ? ["Test ride", ""] : ["Real ride", " real"];
  const tag = (p) => { const [t, c] = source(p); return `<span class="tag${c}">${t}</span>`; };
  const EXAMPLE_NOTE = `<p class="note"><strong>Example data:</strong> computer-generated near misses that show how the map will work. Not real rides yet.</p>`;

  const MEASURES = {
    ksi: { get: (w) => w.ksi, d: 0, unit: "" },
    lanes: { get: (w) => w.lanes, d: 1, unit: " km" },
    planned: { get: (w) => w.planned, d: 1, unit: " km" },
    passes: { get: (w) => w.passes, d: 0, unit: "" },
  };

  // Live 4sight layer, falling back to the static files next to the site.
  const live = await fetch("https://4sight-server.vercel.app/v1/city-risk.geojson")
    .then((r) => r.ok ? r.json() : null).catch(() => null);
  const [wardsFC, ksiFC, events] = await Promise.all([
    fetch("../../data/city/wards.geojson").then((r) => r.json()),
    fetch("../../data/city/cyclist_ksi_2022_2026.geojson").then((r) => r.json()),
    live ? null : fetch("../../data/events.geojson").then((r) => r.json()).catch(() => ({ features: [] })),
  ]);
  const passPts = live ? live.features.filter((f) => f.properties.kind === "pass") : events.features;
  const segments = live ? live.features.filter((f) => f.geometry.type === "LineString") : [];
  const passStreets = segments.filter((f) => f.properties.passes > 0);
  ksiFC.features.forEach((f, i) => { f.properties.i = i; });

  // Point in polygon (ray casting); wards are all single Polygons with an outer ring and holes.
  const inRing = ([x, y], ring) => {
    let inside = false;
    for (let i = 0, j = ring.length - 1; i < ring.length; j = i++) {
      const [xi, yi] = ring[i], [xj, yj] = ring[j];
      if ((yi > y) !== (yj > y) && x < (xj - xi) * (y - yi) / (yj - yi) + xi) inside = !inside;
    }
    return inside;
  };
  const bboxOf = (ring) => ring.reduce((b, [x, y]) => [Math.min(b[0], x), Math.min(b[1], y), Math.max(b[2], x), Math.max(b[3], y)], [180, 90, -180, -90]);
  const inWard = (w, p) => p[0] >= w.bbox[0] && p[0] <= w.bbox[2] && p[1] >= w.bbox[1] && p[1] <= w.bbox[3]
    && inRing(p, w.rings[0]) && !w.rings.slice(1).some((h) => inRing(p, h));
  // shortcut: a line counts as in the ward if its first, middle or last vertex is, and is drawn
  // unclipped, so lines crossing a border poke out a little; clip with turf if that looks wrong.
  const lineIn = (w, f) => {
    const c = f.geometry.type === "MultiLineString" ? f.geometry.coordinates.flat() : f.geometry.coordinates;
    return [c[0], c[c.length >> 1], c[c.length - 1]].some((p) => inWard(w, p));
  };

  const wards = wardsFC.features.map((f) => {
    const p = f.properties;
    return {
      n: +p.ward, name: p.ward_name, feature: f, rings: f.geometry.coordinates, bbox: bboxOf(f.geometry.coordinates[0]),
      ksi: +p.cyclist_ksi, fatal: +p.fatal, si: +p.seriously_injured,
      prot: +p.protected_km, paint: +p.painted_km, lanes: +p.protected_km + +p.painted_km, planned: +p.planned_km,
    };
  }).sort((a, b) => a.n - b.n);
  for (const w of wards) {
    w.pts = passPts.filter((f) => inWard(w, f.geometry.coordinates));
    for (const f of w.pts) f.ward = w;
    w.passes = w.pts.length;
    w.synth = w.pts.filter((f) => f.properties.synthetic).length;
  }
  const byN = new Map(wards.map((w) => [w.n, w]));
  const wardLink = (w) => `<a href="#ward=${w.n}">${esc(w.name)}</a>`;

  // State: the measure shades the map, orders the pick list and sorts the table.
  let measure = "ksi", sortKey = "ksi", sortDir = -1, current = null;

  // Map.
  const map = L.map("map", { zoomControl: false, zoomSnap: 0.25, scrollWheelZoom: false, renderer: L.canvas({ tolerance: 4 }) });
  L.control.zoom({ position: "topright" }).addTo(map);
  map.createPane("labels").style.zIndex = 450;
  map.getPane("labels").style.pointerEvents = "none";
  const esri = "https://server.arcgisonline.com/ArcGIS/rest/services/Canvas/";
  L.tileLayer(esri + "World_Light_Gray_Base/MapServer/tile/{z}/{y}/{x}", { maxZoom: 16, attribution: "Basemap © Esri · City of Toronto" }).addTo(map);
  L.tileLayer(esri + "World_Light_Gray_Reference/MapServer/tile/{z}/{y}/{x}", { maxZoom: 16, pane: "labels" }).addTo(map);

  const desktop = () => matchMedia("(min-width: 821px)").matches;
  const pad = () => desktop() ? { paddingTopLeft: [430, 70], paddingBottomRight: [40, 40] } : { padding: [16, 16] };
  const wardLayer = L.geoJSON(wardsFC, {
    style: () => ({ weight: 1, color: "#FFFFFF", fillOpacity: 0.8 }),
    onEachFeature: (f, layer) => {
      layer.on("click", () => go(`ward=${f.properties.ward}`));
      layer.on("mouseover", () => layer.setStyle({ weight: 3, color: COL.ink }));
      layer.on("mouseout", () => styleWards());
    },
  }).addTo(map);
  const home = wardLayer.getBounds();
  const detail = L.layerGroup().addTo(map), focusLayer = L.layerGroup().addTo(map);

  const mix = (t) => `rgb(${BLUE_SOFT.map((c, i) => Math.round(c + (BLUE[i] - c) * t)).join(",")})`;
  function styleWards() {
    const get = MEASURES[measure].get, max = Math.max(1e-9, ...wards.map(get)), m = MEASURES[measure];
    wardLayer.eachLayer((layer) => {
      const w = byN.get(+layer.feature.properties.ward), sel = current === w;
      layer.setStyle(current
        ? { fillColor: mix(get(w) / max), fillOpacity: sel ? 0 : 0.35, weight: sel ? 2.5 : 1, color: sel ? COL.ink : "#FFFFFF", dashArray: sel ? "6 5" : null }
        : { fillColor: mix(get(w) / max), fillOpacity: 0.8, weight: 1, color: "#FFFFFF", dashArray: null });
      layer.bindTooltip(`<strong>${esc(w.name)}</strong><br>${fmt(get(w), m.d)}${m.unit} ${label(measure, get(w))}`, { sticky: true });
    });
    $("ramp-max").textContent = fmt(max, m.d) + m.unit;
  }
  const label = (k, v) => ({
    ksi: v === 1 ? "cyclist killed or seriously injured" : "cyclists killed or seriously injured",
    lanes: "of protected and painted lanes", planned: "of lanes planned", passes: (v === 1 ? "close pass" : "close passes") + " (example data)",
  }[k]);

  // Pick list.
  function drawList() {
    const q = $("q").value.trim().toLowerCase(), m = MEASURES[measure];
    const rows = wards.filter((w) => !q || w.name.toLowerCase().includes(q) || String(w.n) === q)
      .sort((a, b) => m.get(b) - m.get(a) || a.n - b.n);
    $("ward-list").innerHTML = rows.map((w) => `<li><button type="button" data-ward="${w.n}">`
      + `<span class="n">${w.n}</span><span>${esc(w.name)}</span>`
      + `<span class="v">${fmt(m.get(w), m.d)}<small>${m.unit}</small></span></button></li>`).join("")
      || `<li class="none">No ward matches “${esc(q)}”.</li>`;
  }
  $("ward-list").addEventListener("click", (e) => { const b = e.target.closest("[data-ward]"); if (b) go(`ward=${b.dataset.ward}`); });
  $("q").addEventListener("input", drawList);
  $("q").addEventListener("keydown", (e) => {
    const first = $("ward-list").querySelector("[data-ward]");
    if (e.key === "Enter" && first) go(`ward=${first.dataset.ward}`);
  });

  // Table.
  function drawTable() {
    const keyGet = sortKey === "ward" ? (w) => w.n : MEASURES[sortKey].get;
    const rows = [...wards].sort((a, b) => sortDir * (keyGet(a) - keyGet(b)) || a.n - b.n);
    document.querySelector("#wards-table tbody").innerHTML = rows.map((w) => `<tr${current === w ? ' class="sel"' : ""}>`
      + `<th scope="row"><button type="button" data-ward="${w.n}"><span class="n">${w.n}</span> ${esc(w.name)}</button></th>`
      + ["ksi", "lanes", "planned", "passes"].map((k) =>
        `<td class="num${k === measure ? " on" : ""}">${fmt(MEASURES[k].get(w), MEASURES[k].d)}</td>`).join("") + "</tr>").join("");
    for (const th of document.querySelectorAll("#wards-table thead th")) {
      if (th.dataset.key === sortKey) th.setAttribute("aria-sort", sortDir < 0 ? "descending" : "ascending");
      else th.removeAttribute("aria-sort");
    }
  }
  document.querySelector("#wards-table thead").addEventListener("click", (e) => {
    const th = e.target.closest("th[data-key]");
    if (!th) return;
    const k = th.dataset.key;
    sortDir = k === sortKey ? -sortDir : k === "ward" ? 1 : -1;
    sortKey = k;
    if (k !== "ward") setMeasure(k, false);
    drawTable();
  });
  document.querySelector("#wards-table tbody").addEventListener("click", (e) => {
    const b = e.target.closest("[data-ward]");
    if (!b) return;
    go(`ward=${b.dataset.ward}`);
    document.querySelector(".explore").scrollIntoView({ behavior: reduced ? "auto" : "smooth" });
  });

  function setMeasure(k, sortToo = true) {
    measure = k;
    $("measure").value = k;
    if (sortToo) { sortKey = k; sortDir = -1; }
    styleWards(); drawList(); drawTable();
  }
  $("measure").addEventListener("change", (e) => setMeasure(e.target.value));

  // Views. Each returns what the sheet shows, which ward gives it context, and where the map goes.
  const ord = (n) => n + (n % 100 >= 11 && n % 100 <= 13 ? "th" : ["th", "st", "nd", "rd"][n % 10] || "th");
  function rank(w, get) {
    const v = get(w), above = wards.filter((x) => get(x) > v).length, same = wards.filter((x) => get(x) === v).length;
    const tied = same > 1 ? "tied for " : "";
    if (above === 0) return `${tied}the most of any ward`;
    if (above + same === wards.length) return `${tied}the fewest of any ward`;
    const below = wards.filter((x) => get(x) < v).length;
    return above < below ? `${tied}${ord(above + 1)} most of 25 wards` : `${tied}${ord(below + 1)} fewest of 25 wards`;
  }
  const streetHash = (name) => `street=${encodeURIComponent(name)}`;
  const facts = (rows) => `<dl class="facts">${rows.filter(Boolean).map(([k, v]) => `<div><dt>${k}</dt><dd>${v}</dd></div>`).join("")}</dl>`;
  const mostCommon = (xs) => { const c = {}; let best = null; for (const x of xs) if (x != null && (c[x] = (c[x] || 0) + 1) > (c[best] || 0)) best = x; return best; };

  function wardView(w) {
    const streets = {};
    for (const f of w.pts) if (f.properties.street) streets[f.properties.street] = (streets[f.properties.street] || 0) + 1;
    const top = Object.entries(streets).sort((a, b) => b[1] - a[1]).slice(0, 3);
    const passTag = w.passes && w.synth === 0 ? `<span class="tag real">Real rides</span>` : `<span class="tag">${w.synth && w.synth < w.passes ? "Includes example data" : "Example data"}</span>`;
    return {
      ward: w, eyebrow: `Ward ${w.n}`, title: w.name, back: ["", "All wards"],
      fit: () => map.flyToBounds(L.geoJSON(w.feature).getBounds(), { ...pad(), animate: !reduced, duration: 0.8 }),
      html: `<dl class="stats">
          <div><dt>cyclists killed or seriously injured, 2022–Oct 2026</dt><dd>${w.ksi}</dd><dd class="sub">${w.fatal} killed · ${w.si} seriously injured</dd></div>
          <div><dt>km of protected and painted lanes</dt><dd>${fmt(w.lanes)}</dd><dd class="sub">${fmt(w.prot)} protected · ${fmt(w.paint)} painted</dd></div>
          <div><dt>km of lanes planned 2025–2027</dt><dd>${fmt(w.planned)}</dd></div>
          <div><dt>close passes on 4sight's map</dt><dd>${w.passes}</dd><dd class="sub">${passTag}</dd></div>
        </dl>
        <p class="sentence">${esc(w.name)} had ${plural(w.ksi, "cyclist", "cyclists")} killed or seriously injured from 2022 to October 2026,
        ${rank(w, (x) => x.ksi)}. It has ${fmt(w.lanes)} km of protected and painted lanes (${rank(w, (x) => x.lanes)}),
        and the City plans ${fmt(w.planned)} km more by 2027 (${rank(w, (x) => x.planned)}).
        These are counts, not rates: wards where more people ride will see more injuries.</p>
        ${top.length ? `<h3>Streets with the most close passes <span class="tag">Example data</span></h3><ol class="streets">`
          + top.map(([s, n]) => `<li><a href="#${streetHash(s)}">${esc(s)}</a> <span>${plural(n, "close pass", "close passes")}</span></li>`).join("") + "</ol>" : ""}
        <p class="hint">Select any dot or street on the map for its own page.</p>
        <ul class="key" aria-label="Map key">
          <li><span class="k-dot"></span>Cyclist seriously injured</li>
          <li><span class="k-dot killed"></span>Cyclist killed</li>
          <li><span class="k-line prot"></span>Protected lane</li>
          <li><span class="k-line paint"></span>Painted lane</li>
          <li><span class="k-line pass"></span>Street with close passes</li>
          <li><span class="k-ring"></span>Close pass (example)</li>
        </ul>
        <p class="credit">Injuries and lanes: City of Toronto, Vision Zero and Cycling Network. Close passes: 4sight.</p>`,
    };
  }

  function streetView(name) {
    const segs = segments.filter((f) => f.properties.street === name);
    const pts = passPts.filter((f) => f.properties.street === name);
    if (!segs.length && !pts.length) return null;
    // Whole-street totals from the server (every segment, short ones too); sums are the fallback.
    const t = segs[0]?.properties ?? {};
    const km = t.street_km ?? segs.reduce((a, f) => a + f.properties.km, 0);
    const passes = t.street_passes ?? (segs.length ? segs.reduce((a, f) => a + f.properties.passes, 0) : pts.length);
    const rate = t.street_per_100km ?? (km ? 100 * passes / km : 0);
    const inWards = wards.filter((w) => segs.some((f) => lineIn(w, f)) || pts.some((f) => f.ward === w));
    const ward = mostCommon(pts.map((f) => f.ward)) || inWards[0] || null;
    const hour = mostCommon(pts.map((f) => f.properties.hour)), cls = mostCommon(pts.map((f) => f.properties.cls));
    const lanes = [...new Set(segs.map((f) => f.properties.lane_type).concat(pts.map((f) => f.properties.lane_type)).filter(Boolean))];
    const bounds = L.geoJSON({ type: "FeatureCollection", features: segs.length ? segs : pts }).getBounds();
    focusLayer.addLayer(L.geoJSON({ type: "FeatureCollection", features: segs }, { interactive: false, style: { color: COL.ink, weight: 12, opacity: 0.85, lineCap: "round" } }));
    focusLayer.addLayer(L.geoJSON({ type: "FeatureCollection", features: segs }, { interactive: false, style: { color: COL.pass, weight: 7, opacity: 1, lineCap: "round" } }));
    const allExample = pts.every((f) => f.properties.synthetic) && segs.every((f) => f.properties.synthetic_share >= 0.5);
    return {
      ward, eyebrow: "Street", title: name, back: ward ? [`ward=${ward.n}`, ward.name] : ["", "All wards"],
      fit: () => map.flyToBounds(bounds, { ...pad(), maxZoom: 16, animate: !reduced, duration: 0.8 }),
      html: `<dl class="stats">
          <div><dt>close passes</dt><dd>${passes}</dd><dd class="sub">${allExample ? `<span class="tag">Example data</span>` : ""}</dd></div>
          ${km ? `<div><dt>per 100 km ridden</dt><dd>${fmt(rate)}</dd><dd class="sub">over ${fmt(km)} km of riding</dd></div>` : ""}
        </dl>
        <p class="sentence">${km ? `Riders logged ${fmt(km)} km on ${esc(name)} and were` : `Riders on ${esc(name)} were`} passed too close
        ${plural(passes, "time", "times")}${hour != null ? `, most often around ${hourLabel(hour)}` : ""}${cls ? `, usually by a ${(VEHICLE[cls] || cls).toLowerCase()}` : ""}.</p>
        ${facts([
          lanes.length && ["Bike lane", lanes.map((t) => LANE[t] || t).join(", ")],
          inWards.length && [inWards.length > 1 ? "Wards" : "Ward", inWards.map(wardLink).join(", ")],
        ])}
        ${allExample ? EXAMPLE_NOTE : ""}`,
    };
  }

  function passView(key) {
    const f = passPts.find((x) => passKey(x) === key);
    if (!f) return null;
    const p = f.properties, ll = [f.geometry.coordinates[1], f.geometry.coordinates[0]];
    focusLayer.addLayer(L.circleMarker(ll, { radius: 14, color: COL.ink, weight: 3, fill: false, interactive: false }));
    return {
      ward: f.ward || null, eyebrow: p.street || "Near miss", title: p.level >= 3 ? "Very close pass" : "Close pass",
      back: p.street ? [streetHash(p.street), p.street] : f.ward ? [`ward=${f.ward.n}`, f.ward.name] : ["", "All wards"],
      fit: () => map.flyTo(ll, 16, { animate: !reduced, duration: 0.8 }),
      html: `<p class="sentence">A ${(VEHICLE[p.cls] || "vehicle").toLowerCase()} overtook the rider too close${p.hour != null ? ` around ${hourLabel(p.hour)}` : ""}${p.street ? ` on ${esc(p.street)}` : ""}.
        ${p.level >= 3 ? "The camera rated it imminent: the highest alert level." : ""}</p>
        ${facts([
          ["Vehicle", esc(VEHICLE[p.cls] || p.cls || "Unknown")],
          p.hour != null && ["Time of day", `around ${hourLabel(p.hour)}`],
          p.street && ["Street", `<a href="#${streetHash(p.street)}">${esc(p.street)}</a>`],
          p.lane_type && ["Bike lane", LANE[p.lane_type] || esc(p.lane_type)],
          f.ward && ["Ward", wardLink(f.ward)],
          ["Source", tag(p)],
        ])}
        ${p.synthetic ? EXAMPLE_NOTE : ""}`,
    };
  }

  const titleCase = (s) => s.toLowerCase().replace(/\b[a-z]+/g, (w) => w.length === 1 ? w.toUpperCase() : w[0].toUpperCase() + w.slice(1));
  function injuryView(i) {
    const f = ksiFC.features[i];
    if (!f) return null;
    const p = f.properties, w = byN.get(+p.ward), ll = [f.geometry.coordinates[1], f.geometry.coordinates[0]];
    const killed = p.outcome === "killed";
    const date = new Date(`${p.date}T12:00`).toLocaleDateString("en-CA", { day: "numeric", month: "long", year: "numeric" });
    focusLayer.addLayer(L.circleMarker(ll, { radius: 14, color: COL.ink, weight: 3, fill: false, interactive: false }));
    return {
      ward: w || null, eyebrow: "City of Toronto record", title: killed ? "Cyclist killed" : "Cyclist seriously injured",
      back: w ? [`ward=${w.n}`, w.name] : ["", "All wards"],
      fit: () => map.flyTo(ll, 16, { animate: !reduced, duration: 0.8 }),
      html: `<p class="sentence">A cyclist was ${killed ? "killed" : "seriously injured"} at ${esc(titleCase(p.location))} on ${date}.
        ${w ? `This is one of ${w.ksi} cyclists killed or seriously injured in ${esc(w.name)} from 2022 to October 2026.` : ""}</p>
        ${facts([
          ["Date", date], p.time && ["Time", esc(p.time)], ["Location", esc(titleCase(p.location))],
          w && ["Ward", wardLink(w)], ["Source", "City of Toronto, Vision Zero"],
        ])}`,
    };
  }

  // Ward context layers: injury points, lanes, close-pass streets and points. Lanes are 3 MB, so
  // they load on the first ward that needs them.
  let lanesP = null, drawnFor = null;
  async function drawDetail(w) {
    if (drawnFor === w) return;
    drawnFor = w;
    detail.clearLayers();
    if (!w) return;
    lanesP ||= fetch("../../data/city/bike_lanes.geojson").then((r) => r.json()).catch(() => ({ features: [] }));
    const lanes = await lanesP;
    if (drawnFor !== w) return;
    L.geoJSON({ type: "FeatureCollection", features: lanes.features.filter((f) =>
      (f.properties.lane_type === "protected" || f.properties.lane_type === "painted") && lineIn(w, f)) }, {
      interactive: false, style: (f) => ({ color: f.properties.lane_type === "protected" ? COL.green : COL.blue, weight: 3, opacity: 0.95 }),
    }).addTo(detail);
    L.geoJSON({ type: "FeatureCollection", features: passStreets.filter((f) => lineIn(w, f)) }, {
      style: { color: COL.pass, weight: 9, opacity: 0.55, lineCap: "round" },
      onEachFeature: (f, l) => l.on("click", () => go(streetHash(f.properties.street)))
        .bindTooltip(`<strong>${esc(f.properties.street)}</strong><br>${plural(f.properties.passes, "close pass", "close passes")} · select for details`, { sticky: true }),
    }).addTo(detail);
    for (const f of w.pts) {
      const p = f.properties;
      L.circleMarker([f.geometry.coordinates[1], f.geometry.coordinates[0]], { radius: 5, weight: 2, fill: true, fillOpacity: 0, color: p.level >= 3 ? COL.imminent : COL.amber })
        .on("click", () => go(`pass=${passKey(f)}`))
        .bindTooltip(`${p.level >= 3 ? "Very close pass" : "Close pass"} · ${esc(VEHICLE[p.cls] || p.cls)} · ${source(p)[0]}`).addTo(detail);
    }
    const ksi = ksiFC.features.filter((f) => +f.properties.ward === w.n)
      .sort((a, b) => (a.properties.outcome === "killed") - (b.properties.outcome === "killed"));
    for (const f of ksi) {
      const p = f.properties, killed = p.outcome === "killed";
      L.circleMarker([f.geometry.coordinates[1], f.geometry.coordinates[0]], killed
        ? { radius: 8, color: "#fff", weight: 2, fillColor: COL.red, fillOpacity: 1 }
        : { radius: 5.5, color: "#fff", weight: 1.5, fillColor: COL.ink, fillOpacity: 1 })
        .on("click", () => go(`injury=${p.i}`))
        .bindTooltip(`<strong>Cyclist ${killed ? "killed" : "seriously injured"}</strong><br>${esc(p.date)} · ${esc(titleCase(p.location))}`).addTo(detail);
    }
  }
  const passKey = (f) => `${f.geometry.coordinates[1].toFixed(5)},${f.geometry.coordinates[0].toFixed(5)}`;

  // Hash routing; Back works because every view is a hashchange. Hashes without "=" are plain
  // in-page anchors (#how, #data) and leave the view alone.
  function go(hash) { location.hash = hash; }
  let shown = null, backTo = "";
  function route(first) {
    const raw = location.hash.slice(1);
    if (raw && !raw.includes("=") && !first) return;
    const h = new URLSearchParams(raw);
    focusLayer.clearLayers();
    const view = h.has("ward") ? byN.has(+h.get("ward")) && wardView(byN.get(+h.get("ward")))
      : h.has("street") ? streetView(h.get("street"))
      : h.has("pass") ? passView(h.get("pass"))
      : h.has("injury") ? injuryView(+h.get("injury"))
      : null;
    const missing = !view && [...h.keys()].some((k) => ["ward", "street", "pass", "injury"].includes(k));
    current = view ? view.ward : null;
    styleWards(); drawTable(); drawDetail(current);
    $("pick").hidden = !!(view || missing);
    $("view").hidden = !(view || missing);
    if (view || missing) {
      const v = view || { eyebrow: "", title: "Not on the map", back: ["", "All wards"], html: `<p class="sentence">This link points to something that is no longer on the map. Pick a ward to start again.</p>` };
      $("v-eyebrow").textContent = v.eyebrow;
      $("v-title").textContent = v.title;
      $("v-body").innerHTML = v.html;
      [backTo] = v.back;
      $("back-label").textContent = v.back[1];
      $("copy-status").textContent = "";
      v.fit?.();
      if (raw !== shown) $("v-title").focus({ preventScroll: true });
      document.title = `${v.title} · Cycling Safety by Ward · 4sight`;
    } else {
      map.flyToBounds(home, { ...pad(), animate: !reduced && shown != null && shown !== "", duration: 0.8 });
      if (shown) $("q").focus({ preventScroll: true });
      document.title = "Cycling Safety by Ward · 4sight";
    }
    shown = raw;
  }
  $("back").addEventListener("click", () => {
    if (backTo) return go(backTo);
    history.pushState(null, "", location.pathname + location.search);
    route();
  });
  $("copy").addEventListener("click", async () => {
    const status = $("copy-status");
    try {
      await navigator.clipboard.writeText(location.href);
      status.textContent = "Link copied.";
    } catch {
      status.textContent = `Copy this link: ${location.href}`;
    }
  });
  addEventListener("hashchange", () => route());

  map.fitBounds(home, pad());
  drawList();
  route(true);
})();
