import Combine
import CoreLocation
import MapKit
import SwiftUI

/// Where the rider is in the pre-ride flow. The follow view is one phase of this, not
/// the whole app: everything before `riding` is done at a standstill.
@MainActor
final class RideFlow: ObservableObject {
    enum Phase: Equatable {
        case home
        case preview(RoutePlan)
        case riding
        case arrived(RideSummary)
    }

    @Published var phase: Phase = .home
    @Published var picking = false
    /// Set when the picker was opened from a Places circle: the pick is saved there
    /// instead of starting a route.
    @Published var pickingFor: SavedPlaces.Slot?
    @Published private(set) var recents = RecentPlaces.load()
    @Published private(set) var saved = SavedPlaces.load()

    func save(_ item: MKMapItem, as slot: SavedPlaces.Slot) {
        let place = RecentPlace(item)
        switch slot {
        case .home: saved.home = place
        case .work: saved.work = place
        case .extra: saved.extra = saved.extra.filter { $0.id != place.id } + [place]
        }
        saved.save()
    }

    /// Metres from the destination at which the ride is called done. A cyclist stops
    /// short of the pin more often than on it.
    static let arrivalRadius = 30.0

    func remember(_ item: MKMapItem) {
        recents = recents.adding(RecentPlace(item))
        recents.save()
    }
}

// MARK: - Places

struct RecentPlace: Codable, Identifiable, Equatable {
    let name: String
    let subtitle: String
    let lat, lon: Double

    var id: String { "\(name)|\(lat),\(lon)" }
    var coordinate: CLLocationCoordinate2D { .init(latitude: lat, longitude: lon) }

    var mapItem: MKMapItem {
        let item = MKMapItem(placemark: MKPlacemark(coordinate: coordinate))
        item.name = name
        return item
    }

    init(_ item: MKMapItem) {
        name = item.name ?? "Dropped pin"
        let mark = item.placemark
        subtitle = [mark.thoroughfare, mark.locality].compactMap { $0 }.joined(separator: ", ")
        lat = mark.coordinate.latitude
        lon = mark.coordinate.longitude
    }
}

/// The last few destinations, on this phone only. Nothing is uploaded.
struct RecentPlaces: Codable {
    var items: [RecentPlace] = []
    static let max = 6
    private static let key = "recentPlaces"

    func adding(_ place: RecentPlace) -> RecentPlaces {
        RecentPlaces(items: ([place] + items.filter { $0.id != place.id }).prefix(Self.max).map { $0 })
    }

    static func load() -> RecentPlaces {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode(RecentPlaces.self, from: data)
        else { return RecentPlaces() }
        return decoded
    }

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        UserDefaults.standard.set(data, forKey: Self.key)
    }
}

// MARK: - Routes

/// One cycling route offered for a destination, with only what MapKit can actually
/// tell us about it.
///
/// Lane coverage is deliberately absent: MapKit exposes no cycling-infrastructure
/// data, and a percentage with nothing behind it is worse than no percentage.
struct RoutePlan: Equatable, Identifiable {
    let id: Int
    let name: String
    let seconds: Double
    let metres: Double
    let destination: String
    let coordinates: [CLLocationCoordinate2D]
    let steps: [NavStep]

    static func == (a: RoutePlan, b: RoutePlan) -> Bool { a.id == b.id && a.destination == b.destination }

    var minutes: Int { max(1, Int((seconds / 60).rounded())) }

    var distanceText: String {
        metres < 1000 ? "\(Int(metres.rounded())) m" : String(format: "%.1f km", metres / 1000)
    }

    init(id: Int, route: MKRoute, destination: String) {
        self.id = id
        self.destination = destination
        name = route.name
        seconds = route.expectedTravelTime
        metres = route.distance
        steps = route.steps.filter { $0.distance > 0 || $0 == route.steps.last }.map(NavStep.init)
        let count = route.polyline.pointCount
        coordinates = (0..<count).map { route.polyline.points()[$0].coordinate }
    }
}

// MARK: - Summary

struct RideSummary: Equatable {
    let destination: String
    let seconds: Double
    let metres: Double
    let closePasses: Int
    let imminent: Int

    var minutes: Int { max(1, Int((seconds / 60).rounded())) }
    var distanceText: String {
        metres < 1000 ? "\(Int(metres.rounded())) m" : String(format: "%.1f km", metres / 1000)
    }
}

/// Home, Work and any added places, on this phone only, like recents.
struct SavedPlaces: Codable {
    enum Slot: Equatable { case home, work, extra }

    var home: RecentPlace?
    var work: RecentPlace?
    var extra: [RecentPlace] = []
    private static let key = "savedPlaces"

    static func load() -> SavedPlaces {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode(SavedPlaces.self, from: data) else { return SavedPlaces() }
        return decoded
    }

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        UserDefaults.standard.set(data, forKey: Self.key)
    }
}
