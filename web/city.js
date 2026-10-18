// City of Toronto layers under the close-pass map: bike lanes, cyclists killed or seriously
// injured (KSI) and wards, from data/city/ (real City data, values shown as published).
// app.js calls cityLayers(map) once and passes each filtered event set to update(); a file
// that fails to load just leaves its layer out.
window.cityLayers = function (map) {
  const css = getComputedStyle(document.documentElement);
  const C = (name) => css.getPropertyValue(name).trim();
  const esc = (s) => String(s ?? "").replace(/[&<>"]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" })[c]);
  const form = document.getElementById("city-form");
  const TYPES = ["protected", "painted", "shared", "trail"];
  const lanes = {}, wardName = {};
  let ksi, wards, selected, max = 1, events = [];

  const get = (name) => fetch(`data/city/${name}.geojson`).then((r) => r.ok ? r.json() : null).catch(() => null);
  const show = (src) => {
    document.getElementById("city").hidden = false;
    form.querySelector(`[data-src="${src}"]`).hidden = false;
    sync();
  };

  get("bike_lanes").then((fc) => {
    if (!fc) return;
    for (const t of TYPES) lanes[t] = L.geoJSON(fc, {
      filter: (f) => f.properties.lane_type === t,
      style: { color: C(`--lane-${t}`), weight: t === "protected" ? 3 : 2, opacity: 0.9 },
      onEachFeature: (f, l) => l.bindTooltip(laneTip(f.properties), { sticky: true }),
    });
    show("lanes");
  });

  get("cyclist_ksi_2022_2026").then((fc) => {
    if (!fc) return;
    // Killed drawn last so they sit on top.
    const killed = (f) => f.properties.outcome === "killed";
    ksi = L.geoJSON({ ...fc, features: [...fc.features].sort((a, b) => killed(a) - killed(b)) }, {
      pointToLayer: (f, ll) => L.circleMarker(ll, killed(f)
        ? { radius: 7, color: C("--ink"), weight: 1.5, fillColor: C("--critical"), fillOpacity: 1 }
        : { radius: 4, color: C("--page"), weight: 1, fillColor: C("--ksi-injured"), fillOpacity: 0.95 }),
      onEachFeature: (f, l) => l.bindTooltip(() => ksiTip(f.properties)),
    });
    show("ksi");
  });

  get("wards").then((fc) => {
    if (!fc) return;
    for (const f of fc.features) wardName[f.properties.ward] = f.properties.ward_name;
    wards = L.geoJSON(fc, { style: wardStyle, onEachFeature: (f, l) => l.on("click", () => { selected = l; sync(); }) });
    show("wards");
  });

  const laneTip = (p) => `<strong>${esc(p.street)}</strong><br>${[p.from_street, p.to_street].filter(Boolean).map(esc).join(" to ")}`
    + `<br><span class="muted">${esc(p.city_infra_type)} · City of Toronto</span>`;
  const ksiTip = (p) => `<strong>${p.outcome === "killed" ? "Cyclist killed" : "Cyclist seriously injured"}</strong>`
    + `<br>${esc(p.date)} ${esc(p.time)}<br>${esc(p.location)}<br>Ward ${esc(p.ward)}${wardName[p.ward] ? ` · ${esc(wardName[p.ward])}` : ""}`
    + `<br><span class="muted">City of Toronto, Vision Zero</span>`;

  function wardStyle(f) {
    const key = form.choro.value, on = selected?.feature === f;
    return {
      color: C(on ? "--ink" : "--ink-2"), weight: on ? 3 : 1, opacity: on ? 1 : 0.6, dashArray: on ? null : "5 4",
      fillColor: C("--series"), fillOpacity: key ? 0.08 + 0.5 * (+f.properties[key] / max) : 0,
    };
  }

  // Choosing a shading turns the wards on.
  form.choro.addEventListener("change", () => { if (form.choro.value) form.wards.checked = true; });
  form.addEventListener("change", sync);

  function sync() {
    const on = (l, yes) => l && (yes ? l.addTo(map) : l.remove());
    for (const t of TYPES) on(lanes[t], form[t].checked);
    on(ksi, form.ksi.checked);
    on(wards, form.wards.checked);
    if (!form.wards.checked) selected = null;
    const key = form.choro.value;
    if (wards) {
      max = key ? Math.max(1e-9, ...wards.getLayers().map((l) => +l.feature.properties[key])) : 1;
      wards.setStyle(wardStyle);
    }
    document.getElementById("choro-key").textContent = key && wards
      ? `Shading from 0 (lightest) to ${max} ${key === "planned_km" ? "km" : "cyclists"} (darkest ward).` : "";
    // One canvas holds every layer (separate panes would hide these from the mouse), so order
    // it back to front: wards, lanes, KSI. app.js re-adds the close passes on every render, on top.
    for (const l of [ksi, ...TYPES.map((t) => lanes[t]), wards]) if (l && map.hasLayer(l)) l.bringToBack();
    panel();
  }

  function panel() {
    document.getElementById("ward").hidden = !selected;
    if (!selected) return;
    const p = selected.feature.properties;
    const inside = events.filter((f) => inPolygon(f.geometry.coordinates, selected.feature.geometry));
    const synth = inside.filter((f) => f.properties.synthetic).length;
    const demo = inside.filter((f) => f.properties.demo).length;
    const real = inside.length - synth - demo;
    document.getElementById("ward-body").innerHTML = `<p class="ward-name">Ward ${esc(p.ward)} · ${esc(p.ward_name)}</p>
      <dl class="ward-grid">
        <dt>Cyclists killed or seriously injured, 2022 to Oct 2026</dt>
        <dd><b>${esc(p.cyclist_ksi)}</b> <span class="muted">· ${esc(p.fatal)} killed · ${esc(p.seriously_injured)} seriously injured</span></dd>
        <dt>Cycling network, km</dt>
        <dd>${esc(p.protected_km)} protected · ${esc(p.painted_km)} painted · ${esc(p.shared_km)} shared · ${esc(p.trail_km)} trail</dd>
        <dt>Planned 2025 to 2027</dt>
        <dd>${esc(p.planned_km)} km</dd>
        <dt>Close passes in this ward <span class="muted">(current filters, 4sight)</span></dt>
        <dd><b>${inside.length}</b> ${!inside.length ? "" : [
          synth && `<span class="synth">· ${synth} synthetic (modelled)</span>`,
          demo && `<span class="muted">· ${demo} demo</span>`,
          real && `<span class="muted">· ${real} from real rides</span>`].filter(Boolean).join(" ")}</dd>
      </dl>
      <p class="src">Ward figures: City of Toronto. Totals, not rates per rider.</p>`;
  }

  return { update(ev) { events = ev; panel(); } };
};

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
