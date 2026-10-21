import SwiftUI

/// The colour table `C` from `docs/mock/front.html`, ported value for value.
/// Light Tesla-clay world; the alert colours are the only saturated things on screen.
enum Palette {
    static let ground = Color(hex: 0xE9ECF0)
    static let blockTop = Color(hex: 0xF2F0EC)
    static let blockSide = Color(hex: 0xDAD5CE)
    static let blockBack = Color(hex: 0xCDC8C0)
    static let park = Color(hex: 0xCFE4C1)
    static let parkEdge = Color(hex: 0xB9D4A8)
    static let coneTint = Color.white.opacity(0.2)
    static let label = Color.white
    static let labelInk = Color(hex: 0x3B4250)
    static let labelRoute = Color(hex: 0x0A6CDF)
    static let road = Color(hex: 0xDEE3E8)
    /// Live map: real streets read darker than the mock's so the white paint shows.
    static let street = Color(hex: 0xC7CED6)
    static let kerb = Color(hex: 0xB2BAC3)
    static let sidewalk = Color(hex: 0xFFFFFF)
    static let bikeLane = Color(hex: 0x9ED3A6)
    static let liveGround = Color(hex: 0xE0E4E9)
    static let sidewalkEdge = Color(hex: 0xC9D0D8)
    /// Time-to-arrive, the Google Maps green that stays legible on white.
    static let eta = Color(hex: 0x188038)
    static let parkBay = Color(hex: 0xD9DEE4)
    static let cone = Color.white.opacity(0.5)
    static let body = Color(hex: 0xC3C9D1)
    static let bodyEdge = Color(hex: 0xAEB5BE)
    static let roof = Color(hex: 0xD9DEE4)
    static let glass = Color(hex: 0x9AA3AD)
    static let parkedBody = Color(hex: 0xCCD2D9)
    static let parkedRoof = Color(hex: 0xDEE3E8)
    static let shadow = Color(hex: 0x161C23).opacity(0.2)
    static let lane = Color.white
    static let routeCore = Color(hex: 0x1C8CFF)
    static let routeCase = Color(hex: 0x0A54BE)
    static let puck = Color(hex: 0x0A84FF)
    static let text = Color.white

    static let amber = Color(hex: 0xF5A623)
    static let amberEdge = Color(hex: 0xC9820F)
    static let amberRoof = Color(hex: 0xFFC65C)
    static let red = Color(hex: 0xE8453C)
    static let redEdge = Color(hex: 0xB52F27)
    static let redRoof = Color(hex: 0xFF7A72)

    /// Vehicle fills by threat level: the vehicle itself carries the alert.
    struct VehiclePaint {
        let body, edge, roof, glass: Color
    }

    static func paint(_ level: Int) -> VehiclePaint {
        if level >= 3 {
            return VehiclePaint(body: red, edge: redEdge, roof: redRoof,
                                glass: Color(hex: 0x6E1A16).opacity(0.45))
        }
        if level == 2 {
            return VehiclePaint(body: amber, edge: amberEdge, roof: amberRoof,
                                glass: Color(hex: 0x784808).opacity(0.38))
        }
        return VehiclePaint(body: body, edge: bodyEdge, roof: roof, glass: glass)
    }

    /// People and cyclists: a white halo pass keeps them legible on light ground.
    enum VRU {
        static let body = Color(hex: 0x5F6873)
        static let limb = Color(hex: 0x3E454E)
        static let head = Color(hex: 0x9AA2AC)
        static let halo = Color.white
        /// True size. The mock's 1.6x stood a person 2.7 m tall, and because the figure
        /// stands up the screen toward the rider, someone 4 m back had their head on the
        /// puck. Distance is read from the feet; the figure must not reach forward.
        static let scale = 1.0
    }

    static func vruColour(_ level: Int) -> (body: Color, limb: Color) {
        if level >= 3 { return (red, redEdge) }
        if level == 2 { return (amber, amberEdge) }
        return (VRU.body, VRU.limb)
    }
}

/// The front phone's light palette, Apple Maps' daytime look, for every screen but the ride
/// view's black banner. Contrast-checked on white:
/// `dim` 5.9:1, `green` 4.6:1, `red` 4.5:1.
enum Light {
    static let sheet = Color(hex: 0xF4F5F7)
    static let field = Color(hex: 0xE8EBEF)
    static let ink = Color(hex: 0x111418)
    static let dim = Color(hex: 0x5B616B)
    static let faint = Color(hex: 0xB4BAC3)
    static let line = Color(hex: 0xECEEF1)
    static let handle = Color(hex: 0xC9CED6)
    static let blue = Color(hex: 0x0A6CDF)
    static let blueSoft = Color(hex: 0xDFE8F5)
    static let green = Color(hex: 0x1E7A37)
    static let red = Color(hex: 0xD93025)
    /// Amber that still reads on white (the map's amber is for dark and coloured grounds).
    static let amber = Color(hex: 0xB86E00)
    static let shadow = Color(hex: 0x0C121A).opacity(0.14)
}
