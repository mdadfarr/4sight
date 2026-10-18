// Detail cards: every street, close pass, City injury and ward has its own URL (#street=<name>,
// #pass=<lat>,<lon>, #injury=<index in the City's file>, #ward=<n>). The card opens over the map
// (below it on phones) from the hash on load and on hashchange, so a shared link opens the same card
// and the browser's Back button closes it. Uses the globals from b.js (map, show, passes, LINK, ...).
const D = { view: $("detail"), title: $("detail-title"), kicker: $("detail-kicker"), body: $("detail-body"), badge: $("detail-badge") };
const LANE_WORDS = { protected: "Protected bike lane", painted: "Painted bike lane", shared: "Shared road, no bike lane", none: "No bike lane", trail: "Trail" };
const NEAR_M = 250;
let highlight, before, returnFocus, cameInPage = false, token = 0;

const dateText = (d) => new Date(`${d}T12:00`).toLocaleDateString("en-CA", { day: "numeric", month: "long", year: "numeric" });
// Equirectangular distance: shortcut: fine at city scale (error well under 1%), not across the globe.
const metres = ([lon1, lat1], [lon2, lat2]) => {
  const k = Math.PI / 180, x = (lon2 - lon1) * k * Math.cos((lat1 + lat2) / 2 * k), y = (lat2 - lat1) * k;
  return 6371000 * Math.hypot(x, y);
};
const mostCommon = (xs) => {
  const by = new Map();
  for (const x of xs) if (x != null) by.set(x, (by.get(x) || 0) + 1);
  return [...by].sort((a, b) => b[1] - a[1])[0]?.[0];
};
const facts = (rows) => `<dl class="facts">${rows.filter(Boolean).map(([k, v]) => `<div><dt>${k}</dt><dd>${v}</dd></div>`).join("")}</dl>`;
const stats = (rows) => `<dl class="ward-grid three">${rows.map(([k, v, s]) => `<div><dt>${k}</dt><dd>${v}<small>${s || ""}</small></dd></div>`).join("")}</dl>`;
const vehicle = (p) => esc(NAMES[p.cls] || p.cls || "Vehicle");
const wardOf = (wards, pt) => wards.find((w) => inPolygon(pt, w.geometry));
const wardLink = (w) => w ? `<a href="${LINK.ward(w.properties.ward)}">Ward ${esc(w.properties.ward)} · ${esc(w.properties.ward_name)}</a>` : "Outside the City's wards";
const sourceLine = (example) => example ? `<p class="cap">${EXAMPLE}</p>` : "";
const latlng = (f) => [f.geometry.coordinates[1], f.geometry.coordinates[0]];
const ring = (f, r = 12) => L.circleMarker(latlng(f), { radius: r, color: C.blue, weight: 3, fill: false, interactive: false });

const PAGES = {
  async street(name) {
    const [{ pts, segs }, wards] = await Promise.all([passes, wardsData().catch(() => [])]);
    const sp = pts.filter((f) => f.properties.street === name), ss = segs.filter((f) => f.properties.street === name);
    if (!sp.length && !ss.length) return null;
    // Whole-street totals from the server; every segment of a street carries the same set.
    const { street_km: km, street_passes: n, street_per_100km: rate } = ss[0]?.properties || {};
    const lanes = [...new Set([...ss, ...sp].map((f) => f.properties.lane_type).filter(Boolean))];
    const inWards = [...new Set([...ss.map((f) => f.geometry.coordinates[0]), ...sp.map((f) => f.geometry.coordinates)]
      .map((c) => wardOf(wards, c)).filter(Boolean))];
    const h = mostCommon(sp.map((f) => f.properties.hour));
    const example = anyExample(sp) || ss.some((f) => f.properties.synthetic_share >= 0.5);
    return {
      layer: "passes", kicker: "Street", title: esc(name), example,
      body: (km ? stats([
        ["Km ridden", fmt(km, 1), "by 4sight riders"],
        ["Close passes", fmt(n), "on this street"],
        ["Per 100 km", fmt(rate, 1), "close passes"],
      ]) : "") + facts([
        ["Bike lane", lanes.length ? lanes.map((t) => LANE_WORDS[t] || esc(t)).join(", ") + (lanes.length > 1 ? " (it changes along the street)" : "") : "Not known"],
        inWards.length && [inWards.length > 1 ? "Wards" : "Ward", inWards.map(wardLink).join("<br>")],
        h != null && ["Busiest time", `Around ${hour(h)}`],
      ]) + sourceLine(example),
      layers: [L.geoJSON({ type: "FeatureCollection", features: ss }, { style: { color: C.blue, weight: 7, opacity: 0.8 }, interactive: false }), ...sp.map((f) => ring(f, 9))],
    };
  },

  async pass(value) {
    const [lat, lon] = value.split(",").map(Number);
    if (!Number.isFinite(lat) || !Number.isFinite(lon)) return null;
    const [{ pts }, wards, ksi] = await Promise.all([passes, wardsData().catch(() => []), ksiData().catch(() => [])]);
    // The link keeps 5 decimals (about 1 m), so match within that rounding.
    const here = pts.filter((f) => Math.abs(f.geometry.coordinates[1] - lat) < 6e-6 && Math.abs(f.geometry.coordinates[0] - lon) < 6e-6);
    if (!here.length) return null;
    const p = here[0].properties, at = here[0].geometry.coordinates, big = p.level >= 3;
    const near = ksi.map((f) => [metres(at, f.geometry.coordinates), f]).sort((a, b) => a[0] - b[0])[0];
    return {
      layer: "passes", kicker: p.street ? esc(p.street) : "Close pass", example: anyExample(here),
      title: here.length > 1 ? `${here.length} close passes at this spot` : big ? "Very close pass" : "Close pass",
      body: facts([
        ["What happened", "A vehicle overtook the rider too close, detected by the rear-facing camera on the bike."],
        ["How close", big ? "Very close: the camera's highest alert" : "Close: the camera's warning alert"],
        ["Vehicle", vehicle(p)],
        p.hour != null && ["Time of day", `Around ${hour(p.hour)}`],
        p.street && ["Street", `<a href="${LINK.street(p.street)}">${esc(p.street)}</a>`],
        p.lane_type && ["Bike lane here", LANE_WORDS[p.lane_type] || esc(p.lane_type)],
        ["Ward", wardLink(wardOf(wards, at))],
        near && ["Nearest City injury record", `<a href="${LINK.injury(near[1].properties._i)}">${near[0] < 10 ? "Under 10" : fmt(Math.round(near[0] / 10) * 10)} m away</a>`],
        ["Recorded by", source(p)],
      ]) + sourceLine(anyExample(here)),
      layers: here.map((f) => ring(f)),
    };
  },

  async injury(i) {
    const [ksi, wards] = await Promise.all([ksiData(), wardsData().catch(() => [])]);
    const f = /^\d+$/.test(i) ? ksi[+i] : null;
    if (!f) return null;
    const p = f.properties, killed = p.outcome === "killed";
    return {
      layer: "ksi", kicker: "City injury record", title: killed ? "Cyclist killed" : "Cyclist seriously injured", example: false,
      body: facts([
        ["Date", esc(dateText(p.date)) + (p.time ? `, ${esc(p.time)}` : "")],
        ["Outcome", killed ? "Killed" : "Seriously injured"],
        ["Where", esc(p.location)],
        ["Ward", wardLink(wards.find((w) => w.properties.ward === p.ward))],
        ["Source", "City of Toronto, Vision Zero"],
      ]) + `<p class="cap">One of 155 cyclists killed or seriously injured in Toronto from 2022 to mid-October 2026. The City counts injuries, not how many people ride here.</p>`,
      layers: [ring(f, 13)],
    };
  },

  async ward(n) {
    const [wards, data] = await Promise.all([wardsData(), passes.catch(() => null)]);
    const w = wards.find((x) => String(x.properties.ward) === n);
    if (!w) return null;
    const p = w.properties, ours = ourCount(w, data?.pts), top = topStreets(ours.inside, 3);
    return {
      layer: null, kicker: "Ward", title: `Ward ${esc(p.ward)} · ${esc(p.ward_name)}`, example: anyExample(ours.inside),
      body: wardFacts(p, ours) + facts([
        top.length && ["Most close passes", top.map(([s, c]) => `<a href="${LINK.street(s)}">${esc(s)}</a> (${fmt(c)})`).join("<br>")],
      ]) + `<p class="src">City figures: City of Toronto. Totals, not rates per rider.</p>` + sourceLine(anyExample(ours.inside)),
      layers: [L.geoJSON(w, { style: { color: C.blue, weight: 3, fillColor: C.blue, fillOpacity: 0.08 }, interactive: false })],
    };
  },
};

const wide = () => matchMedia("(min-width: 861px)").matches;
function openView() {
  if (!D.view.hidden) return;
  returnFocus = document.activeElement;
  before = { center: map.getCenter(), zoom: map.getZoom() };
  D.view.hidden = false;
}
function closeView() {
  if (D.view.hidden) return;
  D.view.hidden = true;
  highlight?.remove();
  if (before) map.setView(before.center, before.zoom);
  show(document.querySelector("#layer-pick input:checked").value);
  (returnFocus && document.contains(returnFocus) && returnFocus !== document.body ? returnFocus : $("map")).focus({ preventScroll: true });
}

async function render() {
  const q = new URLSearchParams(location.hash.slice(1));
  const kind = Object.keys(PAGES).find((k) => q.has(k));
  if (!kind) return closeView();
  const t = ++token;
  openView();
  const card = $("map-section").getBoundingClientRect();
  if (card.top < 0 || card.top > innerHeight / 2) $("map-section").scrollIntoView();
  D.kicker.textContent = "";
  D.title.textContent = "Loading…";
  D.body.innerHTML = "";
  D.badge.hidden = true;
  $("map-badge").hidden = true;
  let page = null;
  try { page = await PAGES[kind](q.get(kind)); } catch (e) { console.error(e); }
  if (t !== token) return;
  page ||= { kicker: "", title: "We couldn't find this", body: `<p class="cap">The link may be incomplete, or the data behind it has changed.</p>`, layers: [] };
  if (page.layer) {
    document.querySelector(`#layer-pick input[value=${page.layer}]`).checked = true;
    await show(page.layer);
    $("map-badge").hidden = true;
  }
  D.kicker.innerHTML = page.kicker;
  D.title.innerHTML = page.title;
  D.body.innerHTML = page.body;
  D.badge.hidden = !page.example;
  $("detail-link").value = location.href;
  $("detail-status").textContent = "";
  highlight?.remove();
  highlight = L.featureGroup(page.layers).addTo(map);
  // Keep the highlighted thing clear of the card, which covers the map's right side on wide screens.
  if (page.layers.length) map.fitBounds(highlight.getBounds(), { maxZoom: 15, paddingTopLeft: [40, 40], paddingBottomRight: [wide() ? 460 : 40, 40] });
  D.view.scrollTop = 0;
  D.title.focus({ preventScroll: wide() });
}

function back() {
  if (cameInPage) return history.back();
  // Opened from a shared link: there is no page behind it in this tab's history, so clear the hash in place.
  history.replaceState(null, "", location.pathname + location.search);
  render();
}
window.addEventListener("hashchange", () => { cameInPage = true; render(); });
$("detail-back").addEventListener("click", back);
D.view.addEventListener("keydown", (e) => { if (e.key === "Escape") back(); });

$("detail-copy").addEventListener("click", async () => {
  const input = $("detail-link");
  try { await navigator.clipboard.writeText(input.value); } catch {
    input.select();
    if (!document.execCommand("copy")) return void ($("detail-status").textContent = "Select the link above and copy it.");
  }
  $("detail-status").textContent = "Link copied.";
});

render();
