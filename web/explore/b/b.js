// Design B: story page with one map. Close passes come from the live 4sight server, falling back
// to the static files; City of Toronto layers come from data/city/ and are shown as published.
const LIVE = "https://4sight-server.vercel.app/v1/city-risk.geojson";
const DATA = "../../data/";
const TORONTO = [[43.58, -79.64], [43.86, -79.11]];
const TILES = "https://server.arcgisonline.com/ArcGIS/rest/services/Canvas/";
const C = { dim: "#5B616B", amber: "#F5A623", red: "#E8453C", ink: "#111418", blue: "#0A6CDF", green: "#1E7A37", white: "#FFFFFF", killed: "#D93025" };
const NAMES = { car: "Car", truck: "Truck", bus: "Bus", motorcycle: "Motorcycle", bicycle: "Bicycle", person: "Person" };
const EXAMPLE = "Example data: computer-generated near misses that show how the map will work. Not real rides yet.";

const $ = (id) => document.getElementById(id);
const esc = (s) => String(s ?? "").replace(/[&<>"]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" })[c]);
const getJSON = (u) => fetch(u, { signal: AbortSignal.timeout(12000) }).then((r) => r.ok ? r.json() : Promise.reject(new Error(`${u}: ${r.status}`)));
const sum = (xs, f) => xs.reduce((a, x) => a + (+f(x) || 0), 0);
const fmt = (n, d = 0) => n == null ? "–" : n.toLocaleString("en-CA", { minimumFractionDigits: d, maximumFractionDigits: d });
const hour = (h) => h == null ? "" : `${(h % 12) || 12} ${h < 12 ? "am" : "pm"}`;
// The code keeps the server's field names; visible text never says "synthetic" or "demo".
const source = (p) => p.demo || p.test_ride ? "Test ride" : p.synthetic ? "Example data" : "Real ride";
// Every clickable thing has its own URL; detail.js opens the view on hashchange.
const LINK = {
  street: (s) => "#street=" + encodeURIComponent(s),
  ward: (n) => "#ward=" + n,
  pass: ([lon, lat]) => `#pass=${lat.toFixed(5)},${lon.toFixed(5)}`,
  injury: (i) => "#injury=" + i,
};
const go = (hash) => { location.hash = hash; };
const once = (f) => { let p; return () => p ||= f().catch((e) => { p = null; throw e; }); };
// _i keeps each injury's place in the City's file, so #injury=<index> stays stable.
const ksiData = once(() => getJSON(DATA + "city/cyclist_ksi_2022_2026.geojson")
  .then((fc) => fc.features.map((f, i) => ({ ...f, properties: { ...f.properties, _i: i } }))));
const wardsData = once(() => getJSON(DATA + "city/wards.geojson").then((fc) => fc.features.sort((a, b) => a.properties.ward - b.properties.ward)));

function basemap(map, labels = true) {
  L.tileLayer(TILES + "World_Light_Gray_Base/MapServer/tile/{z}/{y}/{x}", { maxZoom: 16, attribution: "Basemap © Esri · Streets © OpenStreetMap contributors" }).addTo(map);
  if (labels) L.tileLayer(TILES + "World_Light_Gray_Reference/MapServer/tile/{z}/{y}/{x}", { maxZoom: 16 }).addTo(map);
  return map;
}

// Decorative map behind the hero, like the app's role screen.
basemap(L.map("hero-map", { zoomControl: false, attributionControl: false, dragging: false, scrollWheelZoom: false,
  doubleClickZoom: false, boxZoom: false, keyboard: false, touchZoom: false }).setView([43.655, -79.39], 14), false);

// Returns { pts, segs, withLane, without }: segs are the server's street segments (none in the
// fallback); rates are close passes per 100 km ridden.
// "With a bike lane" means protected or painted, matching web/app.js.
const passes = (async () => {
  const lane = (t) => t === "protected" || t === "painted";
  try {
    const fc = await getJSON(LIVE);
    const seg = fc.features.filter((f) => f.geometry.type === "LineString").map((f) => f.properties);
    const rate = (yes) => {
      const s = seg.filter((p) => lane(p.lane_type) === yes), km = sum(s, (p) => p.km);
      return km ? 100 * sum(s, (p) => p.passes) / km : null;
    };
    return { pts: fc.features.filter((f) => f.properties.kind === "pass"),
      segs: fc.features.filter((f) => f.geometry.type === "LineString"), withLane: rate(true), without: rate(false) };
  } catch (e) {
    console.warn("Live data unavailable, using the static files.", e);
    const [ev, rides] = await Promise.all([getJSON(DATA + "events.geojson"), getJSON(DATA + "rides.geojson")]);
    const km = sum(rides.features, (f) => f.properties.km), kmLane = sum(rides.features, (f) => f.properties.km_bike);
    const onLane = ev.features.filter((f) => f.properties.bike_lane).length;
    return { pts: ev.features, segs: [], withLane: kmLane ? 100 * onLane / kmLane : null,
      without: km > kmLane ? 100 * (ev.features.length - onLane) / (km - kmLane) : null };
  }
})();
const anyExample = (pts) => pts.some((f) => f.properties.synthetic);

// ---- The map: one layer at a time ----
const map = basemap(L.map("map", { zoomSnap: 0.25, scrollWheelZoom: false, renderer: L.canvas({ tolerance: 4 }) }).fitBounds(TORONTO));
map.on("focus click", () => map.scrollWheelZoom.enable());
map.on("blur mouseout", () => map.scrollWheelZoom.disable());

const sw = (color, cls = "", border = "") => `<i class="sw ${cls}" style="background:${color};${border}"></i>`;
const LAYERS = {
  passes: {
    async build() {
      const { pts, segs } = await passes;
      const big = (f) => f.properties.level >= 3;
      const streets = L.geoJSON({ type: "FeatureCollection", features: segs }, {
        style: (f) => f.properties.passes ? { color: C.amber, weight: 6, opacity: 0.4 } : { color: C.dim, weight: 4, opacity: 0.25 },
        onEachFeature: (f, l) => l.bindTooltip(`<strong>${esc(f.properties.street)}</strong><br>${fmt(f.properties.passes)} close passes on this stretch<br><em>Click for the street page</em>`, { sticky: true })
          .on("click", () => go(LINK.street(f.properties.street))),
      });
      return L.featureGroup([streets, L.geoJSON({ type: "FeatureCollection", features: [...pts].sort((a, b) => big(a) - big(b)) }, {
        pointToLayer: (f, ll) => L.circleMarker(ll, {
          radius: big(f) ? 7 : 5, weight: source(f.properties) === "Test ride" ? 2.5 : 1.5,
          color: source(f.properties) === "Test ride" ? C.blue : C.white,
          fillColor: big(f) ? C.red : C.amber, fillOpacity: 0.95 }),
        onEachFeature: (f, l) => l.bindTooltip(() => {
          const p = f.properties;
          return `<strong>${big(f) ? "Very close pass" : "Close pass"}</strong><br>${esc(NAMES[p.cls] || p.cls || "Vehicle")}`
            + `${p.hour != null ? ` · around ${hour(p.hour)}` : ""}${p.street ? `<br>${esc(p.street)}` : ""}<br><em>${source(p)}</em>`;
        }).on("click", (e) => { L.DomEvent.stop(e); go(LINK.pass(f.geometry.coordinates)); }),
      })]);
    },
    legend: async () => {
      const { pts } = await passes;
      return `<span>${sw(C.amber)} Close pass</span><span>${sw(C.red)} Very close pass</span>`
        + (pts.some((f) => source(f.properties) === "Test ride") ? `<span>${sw(C.amber, "", `box-shadow:0 0 0 2.5px ${C.blue}`)} Test ride</span>` : "");
    },
    note: async () => {
      const { pts } = await passes;
      return `${fmt(pts.length)} close passes from 4sight.${anyExample(pts) ? " " + EXAMPLE : ""}`;
    },
  },
  ksi: {
    async build() {
      const features = await ksiData();
      const killed = (f) => f.properties.outcome === "killed";
      return L.geoJSON({ type: "FeatureCollection", features: [...features].sort((a, b) => killed(a) - killed(b)) }, {
        pointToLayer: (f, ll) => L.circleMarker(ll, killed(f)
          ? { radius: 8, color: C.white, weight: 2, fillColor: C.killed, fillOpacity: 1 }
          : { radius: 5, color: C.white, weight: 1.5, fillColor: C.ink, fillOpacity: 0.85 }),
        onEachFeature: (f, l) => l.bindTooltip(() => {
          const p = f.properties;
          return `<strong>${killed(f) ? "Cyclist killed" : "Cyclist seriously injured"}</strong><br>${esc(p.date)}`
            + `<br>${esc(p.location)}<br>Ward ${esc(p.ward)}<br><em>Click for details</em>`;
        }).on("click", () => go(LINK.injury(f.properties._i))),
      });
    },
    legend: async () => `<span>${sw(C.killed)} Cyclist killed</span><span>${sw(C.ink)} Cyclist seriously injured</span>`,
    note: async () => "155 cyclists killed or seriously injured, 2022 to mid-October 2026. City of Toronto, Vision Zero. Counts, not rates per rider.",
  },
  lanes: {
    async build() {
      const fc = await getJSON(DATA + "city/bike_lanes.geojson");
      return L.geoJSON(fc, {
        filter: (f) => f.properties.lane_type === "protected" || f.properties.lane_type === "painted",
        style: (f) => f.properties.lane_type === "protected" ? { color: C.green, weight: 3.5, opacity: 0.95 } : { color: C.blue, weight: 2.5, opacity: 0.9 },
        onEachFeature: (f, l) => l.bindTooltip(() => `<strong>${esc(f.properties.street)}</strong><br>${f.properties.lane_type === "protected" ? "Protected lane" : "Painted lane"}`, { sticky: true }),
      });
    },
    legend: async () => `<span>${sw(C.green, "line")} Protected lane</span><span>${sw(C.blue, "line")} Painted lane</span>`,
    note: async () => "Existing bike lanes. City of Toronto cycling network. Shared roads and park trails are not shown.",
  },
};

const built = {};
let shown, wanted;
async function show(name) {
  wanted = name;
  const L_ = LAYERS[name];
  $("legend").innerHTML = await L_.legend().catch(() => "");
  $("map-note").textContent = await L_.note().catch(() => "");
  const data = await passes.catch(() => ({ pts: [] }));
  $("map-badge").hidden = name !== "passes" || !anyExample(data.pts);
  $("map-links").innerHTML = name !== "passes" ? "" : "Streets with the most close passes: " + topStreets(data.pts, 5)
    .map(([s, n]) => `<a href="${LINK.street(s)}">${esc(s)}</a> (${fmt(n)})`).join(", ");
  let layer;
  try { layer = await (built[name] ||= L_.build()); } catch (e) {
    built[name] = null;
    console.error(e);
    if (wanted === name) $("map-note").textContent = "This layer could not be loaded. Please try again later.";
    return;
  }
  if (wanted !== name) return;
  shown?.remove();
  shown = layer.addTo(map);
}
function topStreets(pts, n) {
  const by = new Map();
  for (const f of pts) if (f.properties.street) by.set(f.properties.street, (by.get(f.properties.street) || 0) + 1);
  return [...by].sort((a, b) => b[1] - a[1]).slice(0, n);
}
$("layer-pick").addEventListener("change", (e) => show(e.target.value));
show("passes");

// ---- Bars: with a bike lane vs without ----
passes.then(({ pts, withLane, without }) => {
  const max = Math.max(withLane || 0, without || 0) || 1;
  const row = (label, sub, v, color) => `<div class="bar-row">
      <div class="bar-label"><span>${label} <span class="src">${sub}</span></span><span class="bar-val">${fmt(v, 1)}</span></div>
      <div class="bar-track" role="img" aria-label="${label}: ${fmt(v, 1)} close passes per 100 km">
        <div class="bar-fill" style="width:${v == null ? 0 : (100 * v / max).toFixed(1)}%;background:${color}"></div></div></div>`;
  $("bars").innerHTML = row("With a bike lane", "protected or painted", withLane, C.blue)
    + row("Without a bike lane", "shared road or no lane", without, C.blue);
  $("bars-badge").hidden = !anyExample(pts);
  if (!anyExample(pts)) $("bars-note").textContent = "From real rides recorded with 4sight. Riders choose their routes, so this is a comparison, not proof that lanes cause the difference.";
}).catch(() => { $("bars").innerHTML = `<p class="cap">The comparison could not be loaded. Please try again later.</p>`; });

// ---- Your ward: the non-map view of the same figures ----
// Close passes inside a ward, with a plain line saying where they came from.
function ourCount(w, pts) {
  if (!pts) return { n: "–", how: "Could not be loaded", inside: [] };
  const inside = pts.filter((f) => inPolygon(f.geometry.coordinates, w.geometry));
  const by = (s) => inside.filter((f) => source(f.properties) === s).length;
  const parts = [["Example data", by("Example data")], ["Test ride", by("Test ride")], ["Real rides", by("Real ride")]].filter(([, n]) => n);
  return { n: fmt(inside.length), inside, how: parts.length === 1 && parts[0][0] === "Example data" ? "All example data, not real rides yet"
    : parts.map(([s, n]) => `${fmt(n)} ${s.toLowerCase()}`).join(" · ") || "None recorded yet" };
}
const wardFacts = (p, ours) => `<dl class="ward-grid">
    <div><dt>Cyclists killed or seriously injured</dt><dd>${fmt(+p.cyclist_ksi)}<small>${fmt(+p.fatal)} killed · 2022 to Oct 2026</small></dd></div>
    <div><dt>Bike lanes</dt><dd>${fmt(+p.protected_km + +p.painted_km, 1)} km<small>${esc(p.protected_km)} protected · ${esc(p.painted_km)} painted</small></dd></div>
    <div><dt>Planned 2025 to 2027</dt><dd>${fmt(+p.planned_km, 1)} km<small>City cycling projects</small></dd></div>
    <div><dt>4sight close passes</dt><dd>${ours.n}<small>${ours.how}</small></dd></div>
  </dl>`;

(async () => {
  const wards = await wardsData();
  const pts = await passes.then((d) => d.pts).catch(() => null);
  const counts = new Map(wards.map((w) => [w, ourCount(w, pts)]));
  const pick = $("ward-pick");
  pick.innerHTML = wards.map((w, i) => `<option value="${i}">Ward ${w.properties.ward} · ${esc(w.properties.ward_name)}</option>`).join("");
  pick.value = String(wards.findIndex((w) => w.properties.ward === 10));

  const card = () => {
    const w = wards[+pick.value], p = w.properties;
    $("ward-card").innerHTML = `<h3>Ward ${esc(p.ward)} · ${esc(p.ward_name)}</h3>${wardFacts(p, counts.get(w))}
      <p class="src">City figures: City of Toronto. Totals, not rates per rider.</p>
      <p><a class="more" href="${LINK.ward(p.ward)}">Open this ward's page</a></p>`;
  };
  pick.addEventListener("change", card);
  card();

  $("ward-table").innerHTML = `<caption class="sr">City of Toronto figures and 4sight close passes for each ward</caption>
    <thead><tr><th scope="col">Ward</th><th scope="col">Killed or seriously injured</th><th scope="col">Killed</th>
    <th scope="col">Protected km</th><th scope="col">Painted km</th><th scope="col">Planned km</th><th scope="col">4sight close passes</th></tr></thead><tbody>`
    + wards.map((w) => { const p = w.properties; return `<tr><th scope="row"><a href="${LINK.ward(p.ward)}">${esc(p.ward)} · ${esc(p.ward_name)}</a></th><td>${esc(p.cyclist_ksi)}</td>
      <td>${esc(p.fatal)}</td><td>${esc(p.protected_km)}</td><td>${esc(p.painted_km)}</td><td>${esc(p.planned_km)}</td><td>${counts.get(w).n}</td></tr>`; }).join("")
    + `</tbody>`;
})().catch((e) => {
  console.error(e);
  $("ward-pick").innerHTML = "<option>Wards could not be loaded</option>";
});

// Even-odd ray cast over every ring, so holes and multipolygons count right (same as web/city.js).
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
console.assert(inPolygon([0.5, 0.5], { type: "Polygon", coordinates: [[[0, 0], [1, 0], [1, 1], [0, 1], [0, 0]]] })
  && !inPolygon([2, 0.5], { type: "Polygon", coordinates: [[[0, 0], [1, 0], [1, 1], [0, 1], [0, 0]]] }), "inPolygon");
