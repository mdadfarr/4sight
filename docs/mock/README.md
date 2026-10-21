# Front screen design mock

`front.html` is the front-phone screen drawn in Canvas2D, from the Tesla surround-view and
Google Maps night-nav references. It is the design source of truth: the SwiftUI under
`4sight/Front/` is a translation of it, not the other way round.

Canvas2D on purpose — every call has a direct SwiftUI `GraphicsContext` equivalent
(`fill`, `stroke`, `draw(Text)`, gradients, `clip`), so the agreed picture ports instead of
being re-invented. The projection constants (`CAM`, `ROAD`) and the scenario table must stay
identical on both sides.

Open `front.html` in any browser and drag the slider.
