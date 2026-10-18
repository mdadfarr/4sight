// 4sight close-pass map: loads data/*.geojson (tools/build_site_data.py), filters in the
// browser and recomputes every number from the filtered features, so the sidebar and the
// map always describe the same set.
(async function () {
  const css = getComputedStyle(document.documentElement);
  const C = (name) => css.getPropertyValue(name).trim();
  const LEVEL = { 2: C("--serious"), 3: C("--critical") };
  const NAMES = { car: "Car", truck: "Truck", bus: "Bus", motorcycle: "Motorcycle", bicycle: "Bicycle", person: "Person", unknown: "Unknown" };

  // Live from the 4sight server (GET /v1/city-risk.geojson) when API is set, else the static
  // files. ?api=<base> overrides it, ?demo=1 adds demo rides. Falls back to the static files
  // if the server does not answer.
  const params = new URLSearchParams(location.search);
  const API = params.get("api") ?? "";
  const live = API && await fetch(`${API}/v1/city-risk.geojson${params.get("demo") === "1" ? "?demo=1" : ""}`)
    .then((r) => r.ok ? r.json() : null).catch(() => null);
  const [events, rides] = live ? fromServer(live) : await Promise.all(
    ["data/events.geojson", "data/rides.geojson"].map((u) => fetch(u).then((r) => r.json())));

  // The server's segments stand in for rides and its passes for events. shortcut: segments
  // carry no hour and only a synthetic share (>= half counts as synthetic), and passes are
  // the newest 500, so hour filters drop the km and rates undercount past 500 passes;
  // add per-hour, per-source totals to the GET if the site needs exact live numbers.
  function fromServer(fc) {
    const lane = (t) => t === "protected" || t === "painted";
    const seg = fc.features.filter((f) => f.geometry.type === "LineString");
    const pts = fc.features.filter((f) => f.properties.kind === "pass");
    return [
      { type: "FeatureCollection", features: pts.map((f) => ({ ...f, properties: {
        ...f.properties, bike_lane: lane(f.properties.lane_type), street: f.properties.street || "Other streets" } })) },
      { type: "FeatureCollection", features: seg.map((f) => ({ ...f, properties: {
        street: f.properties.street, km: f.properties.km, km_bike: lane(f.properties.lane_type) ? f.properties.km : 0,
        synthetic: f.properties.synthetic_share >= 0.5, hour: null } })) },
    ];
  }

  const form = document.getElementById("filters");
  const hours = [...Array(24).keys()];
  const hourLabel = (h) => `${String(h).padStart(2, "0")}:00`;
  for (const [name, init] of [["from", 0], ["to", 23]]) {
    form[name].innerHTML = hours.map((h) => `<option value="${h}"${h === init ? " selected" : ""}>${hourLabel(h)}</option>`).join("");
  }
  const classes = [...new Set(events.features.map((f) => f.properties.cls))].sort();
  form.cls.insertAdjacentHTML("beforeend", classes.map((c) => `<option value="${c}">${NAMES[c] || c}</option>`).join(""));

  // Created once layout has settled, so the first fit uses the map's real height.
  await document.fonts.ready;
  await new Promise(requestAnimationFrame);
  // One canvas for every vector layer (City layers included); tolerance makes thin lines hoverable.
  const map = L.map("map", { renderer: L.canvas({ tolerance: 4 }), zoomControl: true });
  if (events.features.length) map.fitBounds(L.geoJSON(events).getBounds(), { padding: [30, 30] });
  else map.setView([43.705, -79.33], 12);
  const esri = "https://server.arcgisonline.com/ArcGIS/rest/services/Canvas/";
  L.tileLayer(esri + "World_Dark_Gray_Base/MapServer/tile/{z}/{y}/{x}", {
    maxZoom: 16, attribution: "Basemap © Esri · Streets © OpenStreetMap contributors",
  }).addTo(map);
  const labels = L.tileLayer(esri + "World_Dark_Gray_Reference/MapServer/tile/{z}/{y}/{x}", { maxZoom: 16, pane: "overlayPane" });
  const city = window.cityLayers?.(map);
  let rideLayer, pointLayer, heatLayer;

  function state() {
    const f = new FormData(form);
    return {
      real: form.real.checked, synthetic: form.synthetic.checked, cls: f.get("cls"),
      level: +f.get("level"), from: +f.get("from"), to: +f.get("to"), view: f.get("view"),
    };
  }
  // A range that wraps midnight (22:00 to 05:00) is allowed.
  const inHours = (h, s) => h == null ? s.from === 0 && s.to === 23
    : s.from <= s.to ? h >= s.from && h <= s.to : h >= s.from || h <= s.to;
  const sourceOK = (p, s) => p.synthetic ? s.synthetic : s.real;

  function render() {
    const s = state();
    const ev = events.features.filter((f) => {
      const p = f.properties;
      return sourceOK(p, s) && (!s.cls || p.cls === s.cls) && p.level >= s.level && inHours(p.hour, s);
    });
    const rd = rides.features.filter((f) => sourceOK(f.properties, s) && inHours(f.properties.hour, s));
    drawMap(ev, rd, s);
    drawStats(ev, rd, s);
    city?.update(ev);
  }

  function drawMap(ev, rd, s) {
    for (const l of [rideLayer, pointLayer, heatLayer]) if (l) map.removeLayer(l);
    rideLayer = L.geoJSON({ type: "FeatureCollection", features: rd }, {
      interactive: false,
      style: (f) => f.properties.synthetic
        ? { color: C("--ride"), weight: 2, opacity: 0.4 }
        : { color: C("--series"), weight: 3, opacity: 0.85 },
    }).addTo(map);
    labels.addTo(map);
    if (s.view === "heat") {
      heatLayer = L.heatLayer(ev.map((f) => [f.geometry.coordinates[1], f.geometry.coordinates[0], f.properties.level >= 3 ? 1 : 0.6]),
        { radius: 18, blur: 16, maxZoom: 15, gradient: { 0.3: "#7a3b22", 0.6: C("--serious"), 1: C("--critical") } }).addTo(map);
      return;
    }
    // Imminent drawn last so it sits on top.
    const sorted = [...ev].sort((a, b) => a.properties.level - b.properties.level);
    pointLayer = L.geoJSON({ type: "FeatureCollection", features: sorted }, {
      pointToLayer: (f, ll) => {
        const p = f.properties, colour = LEVEL[Math.min(p.level, 3)];
        return L.circleMarker(ll, p.synthetic
          ? { radius: p.level >= 3 ? 6 : 5, color: colour, weight: 2, fillOpacity: 0 }
          : { radius: 7, color: C("--surface"), weight: 2, fillColor: colour, fillOpacity: 1 });
      },
      onEachFeature: (f, layer) => layer.bindPopup(popup(f.properties)),
    }).addTo(map);
  }

  function popup(p) {
    const what = p.level >= 3 ? "Imminent" : "Close pass";
    const rows = [
      `<strong>${what}</strong> · ${NAMES[p.cls] || p.cls}${p.side === "right" ? " (right hook)" : ""}`,
      p.street,
      [p.gap_m != null && `${p.gap_m.toFixed(2)} m gap`, p.ttc_s != null && `${p.ttc_s.toFixed(1)} s to contact`].filter(Boolean).join(" · "),
      [p.hour != null && hourLabel(p.hour), p.bike_lane ? "bike lane" : "no bike lane"].filter(Boolean).join(" · "),
      p.synthetic ? `<span style="color:${C("--synthetic")}">Synthetic</span>` : p.demo ? "Demo ride" : p.test_ride ? "Real · test ride" : "Real ride",
    ];
    return rows.filter(Boolean).join("<br>");
  }

  const fmt = (x, d = 1) => x == null || !isFinite(x) ? "–" : x.toFixed(d);

  function drawStats(ev, rd, s) {
    const km = rd.reduce((a, f) => a + f.properties.km, 0);
    const kmBike = rd.reduce((a, f) => a + f.properties.km_bike, 0);
    const synth = ev.filter((f) => f.properties.synthetic).length;
    document.getElementById("rate").textContent = km ? fmt(100 * ev.length / km) : "–";
    document.getElementById("rate-detail").textContent =
      `${ev.length} close passes over ${fmt(km, 0)} km · ${ev.filter((f) => f.properties.level >= 3).length} imminent`;

    const badge = document.getElementById("badge");
    badge.classList.toggle("real-only", !s.synthetic);
    badge.querySelector("strong").textContent = s.synthetic ? "Includes synthetic data" : "Real rides only";
    document.getElementById("badge-detail").textContent = s.synthetic ? `· ${synth} of ${ev.length} close passes are modelled` : "";

    const yes = kmBike ? 100 * ev.filter((f) => f.properties.bike_lane).length / kmBike : null;
    const no = km - kmBike > 0 ? 100 * ev.filter((f) => !f.properties.bike_lane).length / (km - kmBike) : null;
    document.getElementById("lane-yes").textContent = fmt(yes);
    document.getElementById("lane-no").textContent = fmt(no);
    document.getElementById("lane-finding").innerHTML = yes > 0 && no > 0
      ? (no >= yes
        ? `Riders were close-passed <strong>${fmt(no / yes)}×</strong> as often per km on streets without a bike lane.`
        : `Close passes per km were <strong>${fmt(yes / no)}×</strong> higher with a bike lane in this selection.`)
      : "Not enough riding in this selection to compare.";

    drawHours(ev);
    drawStreets(ev, rd);
    const counts = {};
    for (const f of ev) counts[f.properties.cls] = (counts[f.properties.cls] || 0) + 1;
    document.getElementById("classes").innerHTML = Object.entries(counts).sort((a, b) => b[1] - a[1])
      .map(([c, n]) => `<li>${NAMES[c] || c} <b>${n}</b> <span class="muted">${fmt(100 * n / ev.length, 0)}%</span></li>`).join("")
      || `<li class="muted">None</li>`;
  }

  // One series, so no legend: the heading names it. Hover shows the exact count.
  function drawHours(ev) {
    const n = hours.map((h) => ev.filter((f) => f.properties.hour === h).length);
    const max = Math.max(1, ...n), W = 360, H = 130, top = 8, bottom = 18, bw = W / 24;
    const y = (v) => top + (H - top - bottom) * (1 - v / max);
    const bars = n.map((v, h) => {
      const x = h * bw + 1, yy = y(v), hh = H - bottom - yy;
      return `<rect class="hit" x="${h * bw}" y="${top}" width="${bw}" height="${H - top - bottom}" fill="transparent" data-tip="${hourLabel(h)} · ${v} close pass${v === 1 ? "" : "es"}"></rect>`
        + (v ? `<path class="bar" d="M${x},${H - bottom} V${yy + 3} q0,-3 3,-3 h${bw - 8} q3,0 3,3 V${H - bottom} Z"></path>` : "");
    }).join("");
    const ticks = [0, 6, 12, 18, 23].map((h) => `<text class="tick" x="${h * bw + bw / 2}" y="${H - 4}" text-anchor="middle">${hourLabel(h).slice(0, 2)}</text>`).join("");
    const el = document.getElementById("hours");
    el.innerHTML = `<svg viewBox="0 0 ${W} ${H}" aria-hidden="true"><line class="grid" x1="0" x2="${W}" y1="${y(max)}" y2="${y(max)}"></line>`
      + `<text class="tick" x="0" y="${y(max) - 3}">${max}</text>${bars}<line class="base" x1="0" x2="${W}" y1="${H - bottom}" y2="${H - bottom}"></line>${ticks}</svg>`;
    const peak = n.indexOf(Math.max(...n));
    el.setAttribute("aria-label", `Close passes by hour of day; most at ${hourLabel(peak)} (${n[peak]}).`);
  }

  function drawStreets(ev, rd) {
    const st = {};
    for (const f of rd) (st[f.properties.street] ||= { km: 0, n: 0 }).km += f.properties.km;
    for (const f of ev) (st[f.properties.street] ||= { km: 0, n: 0 }).n += 1;
    const ranked = Object.entries(st).filter(([name, v]) => v.km >= 10 && name !== "Other streets")
      .map(([name, v]) => ({ name, km: v.km, n: v.n, rate: 100 * v.n / v.km }))
      .sort((a, b) => b.rate - a.rate).slice(0, 8);
    const max = Math.max(1e-9, ...ranked.map((r) => r.rate));
    document.getElementById("streets").innerHTML = ranked.map((r) =>
      `<li><span>${r.name}</span><span class="v">${fmt(r.rate)} <span class="n">${r.n} in ${fmt(r.km, 0)} km</span></span>`
      + `<span class="bar" aria-hidden="true"><span style="width:${(100 * r.rate / max).toFixed(1)}%"></span></span></li>`).join("")
      || `<li class="muted">No street has 10 km of riding in this selection.</li>`;
  }

  const tip = document.getElementById("tip");
  document.getElementById("hours").addEventListener("mousemove", (e) => {
    const t = e.target.closest("[data-tip]");
    if (!t) { tip.hidden = true; return; }
    tip.textContent = t.dataset.tip;
    tip.hidden = false;
    tip.style.left = `${e.clientX + 12}px`;
    tip.style.top = `${e.clientY - 30}px`;
  });
  document.getElementById("hours").addEventListener("mouseleave", () => { tip.hidden = true; });

  form.addEventListener("change", render);
  render();
})();
