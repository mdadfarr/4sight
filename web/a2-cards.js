// 4sight map A2: shared helpers and the detail cards (street, ward, close pass, injury, lane).
// Cards join the layers: City injuries near a street, close passes near an injury site.
const esc = (s) => String(s ?? "").replace(/[&<>"]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" })[c]);
const fmt = (x, d = 1) => x == null || !isFinite(x) ? "–" : x.toFixed(d);
const titleCase = (s) => String(s ?? "").toLowerCase().replace(/\b[a-z]/g, (c) => c.toUpperCase());
// One key per street however it is spelled: "Bloor St W" (City) = "Bloor Street West" (4sight).
const ABBR = { street: "st", avenue: "ave", road: "rd", east: "e", west: "w", north: "n", south: "s", trail: "trl", boulevard: "blvd", drive: "dr", crescent: "cres" };
const mostOf = (o) => Object.entries(o).sort((a, b) => b[1] - a[1])[0]?.[0];
const key = (n) => String(n ?? "").toLowerCase().replace(/\./g, "").replace(/\b[a-z]+\b/g, (w) => ABBR[w] || w).replace(/\s+/g, " ").trim();

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

// Metres on a flat local projection; good to a few metres across Toronto.
const KX = 111320 * Math.cos(43.7 * Math.PI / 180), KY = 110540;
const lines = (g) => g.type === "LineString" ? [g.coordinates] : g.type === "MultiLineString" ? g.coordinates : [];
function metres([x, y], [x2, y2]) { return Math.hypot((x - x2) * KX, (y - y2) * KY); }
function metresToLines([x, y], ls) {
  let best = Infinity;
  for (const l of ls) for (let i = 1; i < l.length; i++) {
    const ax = (l[i - 1][0] - x) * KX, ay = (l[i - 1][1] - y) * KY, bx = (l[i][0] - x) * KX, by = (l[i][1] - y) * KY;
    const dx = bx - ax, dy = by - ay, len = dx * dx + dy * dy;
    const t = len ? Math.max(0, Math.min(1, -(ax * dx + ay * dy) / len)) : 0;
    best = Math.min(best, Math.hypot(ax + t * dx, ay + t * dy));
  }
  return best;
}

window.makeCards = function (c) {
  const { streets, wards, wardAt, risk, ksiFC, lanesFC, segs, share, LANE, VEHICLE, passKey } = c;
  const killed = (f) => f.properties.outcome === "killed";
  const hour = (h) => `${String(h).padStart(2, "0")}:00`;
  const day = (d, month = "long") => new Date(`${d}T12:00`).toLocaleDateString("en-CA", { year: "numeric", month, day: "numeric" });
  const tag = (sh) => sh > 0 ? `<span class="pill">Example data</span>` : `<span class="pill real">Real rides</span>`;
  const city = `<span class="pill city">City of Toronto</span>`;
  const group = (title, pill, items) => `<h3 class="group">${title} ${pill}</h3><ul class="facts">${items.filter(Boolean).join("")}</ul>`;
  const link = (go, text) => `<button type="button" data-go="${esc(go)}">${esc(text)}</button>`;
  const wardLink = (w) => w && `<li>In ${link(`ward=${w.ward}`, `Ward ${w.ward}, ${w.ward_name}`)}</li>`;
  const ring = (ll) => L.circleMarker(ll, { radius: 13, color: "#0A6CDF", weight: 3, fill: false, interactive: false });
  // Test rides first: they are never example data or real riding.
  const sourceNote = (p) => p.demo ? `<p class="note"><span class="pill test">Test ride</span> A practice run or stage showing, not real riding.</p>`
    : p.synthetic ? `<p class="note"><span class="pill">Example data</span> Computer-generated to show how the map will work, not a real ride.</p>` : `<p class="note"><span class="pill real">Real ride</span></p>`;
  const exampleLine = (sh) => sh > 0 ? `<p class="note">Example data: computer-generated near misses that show how the map will work. Real rides are labelled Real ride.</p>` : "";

  // City lane types per street, matched by name.
  const cityLanes = {};
  for (const f of lanesFC?.features || []) (cityLanes[key(f.properties.street)] ||= new Set()).add(f.properties.lane_type);
  const laneWords = (types = new Set()) => [
    types.has("protected") && "Protected lane on part of it",
    types.has("painted") && "Painted lane on part of it",
    !types.has("protected") && !types.has("painted") && (types.has("shared") ? "Shared route only, no bike lane" : "No bike lane in the City's network"),
  ].filter(Boolean).map((t) => `<li>${t}</li>`).join("");
  const segLines = (k) => risk.segments.filter((f) => key(f.properties.street) === k).flatMap((f) => lines(f.geometry));
  const streetLink = (s) => link(`street=${s.name}`, s.name);

  return {
    street(name) {
      const s = streets[key(name)];
      if (!s?.key) return null;
      const ls = segLines(s.key), h = mostOf(s.hours), v = mostOf(s.cls);
      const near = (ksiFC?.features || []).filter((f) => metresToLines(f.geometry.coordinates, ls) <= 50)
        .sort((a, b) => a.properties.date.localeCompare(b.properties.date));
      // Ring the injuries the card lists, so they stand out on the map.
      const mark = L.featureGroup(near.map((f) => L.circleMarker([f.geometry.coordinates[1], f.geometry.coordinates[0]],
        { radius: 9, color: "#0A6CDF", weight: 2.5, fill: false, interactive: false })));
      return { layer: "passes", kicker: "Street", title: s.name, mark,
        bounds: L.featureGroup(segs.getLayers().filter((l) => key(l.feature.properties.street) === s.key)).getBounds(),
        html: `<p class="stat"><b>${fmt(s.rate)}</b><span>close passes for every 100 km ridden</span></p>
        ${group("Close passes", tag(s.share) + (s.test ? ` <span class="pill test">Test ride</span>` : ""), [
          `<li>${s.passes} close pass${s.passes === 1 ? "" : "es"} in ${fmt(s.km, 0)} km of riding</li>`,
          s.imminent && `<li>${s.imminent} of them very close (the camera's strongest warning)</li>`,
          s.test && `<li>${s.test} of them from test rides</li>`,
          h != null && `<li>Most often around ${hour(h)}</li>`,
          VEHICLE[v] && `<li>Mostly ${VEHICLE[v][0]}</li>`,
          s.short && `<li>Only ${fmt(s.km, 0)} km ridden here so far, too little to compare with other streets</li>`])}
        ${group("Injuries and bike lanes", city, [
          `<li>Cyclists killed or seriously injured within 50 m of this street since 2022: <b>${near.length}</b>
            ${near.length ? `<span class="dates">${near.map((f) => link(`injury=${f.id}`, `${day(f.properties.date, "short")}${killed(f) ? " (killed)" : ""}`)).join("")}</span>` : ""}</li>`,
          laneWords(cityLanes[s.key])])}
        <p class="note">Injury counts are totals, not per rider.</p>` };
    },
    ward(n) {
      const w = wards.find((w) => w.ward === +n);
      if (!w) return null;
      const mark = L.geoJSON(w.f, { interactive: false, style: { color: "#111418", weight: 2.5, opacity: 0.8, dashArray: "6 5", fillColor: "#0A6CDF", fillOpacity: 0.05 } });
      return { kicker: `Ward ${w.ward}`, title: w.ward_name, bounds: mark.getBounds(), mark,
        html: group("Close passes", tag(share), [`<li><b>${w.passes}</b> close passes recorded in this ward</li>`])
        + group("Injuries and bike lanes", city, [
          `<li><b>${esc(w.cyclist_ksi)}</b> cyclists killed or seriously injured, 2022 to October 2026 (${esc(w.fatal)} killed)</li>`,
          `<li>${esc(w.protected_km)} km protected and ${esc(w.painted_km)} km painted bike lanes</li>`,
          `<li>${esc(w.planned_km)} km of cycling projects planned for 2025 to 2027</li>`])
        + `${exampleLine(share)}<p class="note">City figures are totals, not per rider.</p>` };
    },
    pass(v) {
      const f = risk.passes.find((f) => passKey(f) === v);
      if (!f) return null;
      const p = f.properties, ll = L.latLng(f.geometry.coordinates[1], f.geometry.coordinates[0]), s = streets[key(p.street)];
      return { layer: "passes", kicker: p.level >= 3 ? "Very close pass" : "Close pass", zoom: 16, bounds: L.latLngBounds([ll, ll]), mark: ring(ll),
        title: `${VEHICLE[p.cls]?.[1] || "A vehicle"} passed too close${p.street ? ` on ${p.street}` : ""}`,
        html: `<ul class="facts">${[
          p.level >= 3 && "<li>Very close: the camera's strongest warning</li>",
          p.hour != null && `<li>Around ${hour(p.hour)}</li>`,
          `<li>${LANE[p.lane_type] ? `On a ${esc(LANE[p.lane_type][1].toLowerCase())}` : p.lane_type === "lane" ? "On a bike lane" : "No bike lane here"}</li>`,
          s?.key && `<li>On ${streetLink(s)}: ${fmt(s.rate)} close passes per 100 km</li>`,
          wardLink(wardAt(f.geometry.coordinates))].filter(Boolean).join("")}</ul>${sourceNote(p)}` };
    },
    injury(i) {
      const f = /^\d+$/.test(i) && ksiFC?.features[+i];
      if (!f) return null;
      const p = f.properties, pt = f.geometry.coordinates, ll = L.latLng(pt[1], pt[0]);
      const close = risk.passes.filter((q) => metres(q.geometry.coordinates, pt) <= 250).length;
      let nearest = null, best = Infinity;
      for (const s of Object.values(streets)) {
        if (!s.key || !s.passes) continue;
        const d = metresToLines(pt, segLines(s.key));
        if (d < best) [best, nearest] = [d, s];
      }
      const away = best < 1000 ? `${Math.max(10, Math.round(best / 10) * 10)} m away` : `${fmt(best / 1000)} km away`;
      return { layer: "injuries", kicker: "City of Toronto, Vision Zero", zoom: 16, bounds: L.latLngBounds([ll, ll]), mark: ring(ll),
        title: `Cyclist ${killed(f) ? "killed" : "seriously injured"}`,
        html: group("What the City recorded", city, [
          `<li>${esc(day(p.date))}${p.time ? `, around ${esc(p.time)}` : ""}</li>`,
          `<li>${esc(titleCase(p.location))}</li>`,
          wardLink(wards.find((w) => w.ward === +p.ward))])
        + group("Close passes nearby", tag(share), [
          `<li>Close passes within 250 m: <b>${close}</b></li>`,
          nearest && `<li>Nearest street with close passes: ${streetLink(nearest)}, ${away}</li>`])
        + `<p class="note">The City's record does not say how the crash happened.</p>` };
    },
    lane(i) {
      const f = /^\d+$/.test(i) && lanesFC?.features[+i];
      if (!f) return null;
      const p = f.properties, mark = L.geoJSON(f, { interactive: false, style: { color: "#0A6CDF", weight: 12, opacity: 0.25 } });
      return { layer: "lanes", kicker: "City of Toronto cycling network", title: p.street || "Bike route", bounds: mark.getBounds(), mark,
        html: `<ul class="facts"><li>${esc(LANE[p.lane_type]?.[1] || "Bike route")}${p.city_infra_type ? ` (${esc(p.city_infra_type)})` : ""}</li>
        ${p.from_street || p.to_street ? `<li>${esc([p.from_street, p.to_street].filter(Boolean).join(" to "))}</li>` : ""}
        ${+p.installed ? `<li>Installed ${esc(p.installed)}${+p.upgraded ? `, upgraded ${esc(p.upgraded)}` : ""}</li>` : ""}</ul>` };
    },
  };
};
