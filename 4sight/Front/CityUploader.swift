import Combine
import Foundation
import MapKit
import os
import Protocol
import SwiftUI

/// The 4sight server (docs/DATA_PIPELINE.md). Empty: rides are kept in the outbox but
/// nothing is sent, and the close-pass map shows only the rider's own events.
enum CityAPI {
    static let base = "https://4sight-server.vercel.app"
}

/// Sends finished rides to the city map. One JSON file per ride in Documents/outbox/,
/// sent at ride end and at launch. 200 deletes it; 400/413 are logged and deleted
/// (resending cannot fix them); 429, 5xx and no signal leave it for next time.
/// The only identifier ever sent is a random per-install UUID. No credentials.
final class CityUploader: ObservableObject {
    static let shared = CityUploader()
    /// After a ride, what happened to it, for about 3 s.
    @Published private(set) var note: String?

    static let app = "4sight/" + (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
    static var install: String {
        if let id = UserDefaults.standard.string(forKey: "installID") { return id }
        let id = UUID().uuidString.lowercased()
        UserDefaults.standard.set(id, forKey: "installID")
        return id
    }

    static let outbox = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("outbox", isDirectory: true)
    private static let log = Logger(subsystem: "com.zupersun.foursight", category: "upload")
    /// Sends run one after another, so a launch flush and a ride end never post a file twice.
    private var sending: Task<Set<String>, Never>?

    /// One ride, as one upload or (over 5.5 h) several consecutive ones.
    func submit(_ parts: [RideUpload]) {
        var names: [String] = []
        do {
            try FileManager.default.createDirectory(at: Self.outbox, withIntermediateDirectories: true)
            for part in parts {
                let name = "ride-\(Int(part.started.timeIntervalSince1970)).json"
                try part.json().write(to: Self.outbox.appendingPathComponent(name), options: .atomic)
                names.append(name)
            }
        } catch {
            return Self.log.error("outbox write failed: \(error.localizedDescription)")
        }
        let n = parts.reduce(0) { $0 + $1.events.count }
        Task {
            let sent = await flush().value
            guard n > 0 else { return }
            show(Set(names).isSubset(of: sent)
                 ? "\(n) near miss\(n == 1 ? "" : "es") added to Toronto\u{2019}s safety map"
                 : "Ride saved, will upload when online")
        }
    }

    /// Tries every file in the outbox; returns the names the server accepted.
    @discardableResult
    func flush() -> Task<Set<String>, Never> {
        let previous = sending
        let task = Task {
            _ = await previous?.value
            return await Self.sendAll()
        }
        sending = task
        return task
    }

    private func show(_ text: String) {
        withAnimation { note = text }
        Task {
            try? await Task.sleep(for: .seconds(3))
            if note == text { withAnimation { note = nil } }
        }
    }

    private static func sendAll() async -> Set<String> {
        guard let url = URL(string: CityAPI.base + "/v1/rides"), !CityAPI.base.isEmpty else { return [] }
        let files = (try? FileManager.default.contentsOfDirectory(at: outbox, includingPropertiesForKeys: nil)) ?? []
        var sent = Set<String>()
        for file in files.filter({ $0.pathExtension == "json" }).sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            guard let body = try? Data(contentsOf: file) else { continue }
            var req = URLRequest(url: url, timeoutInterval: 20)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = body
            // No signal: stop here, the rest would fail the same way.
            guard let (_, resp) = try? await URLSession.shared.data(for: req),
                  let code = (resp as? HTTPURLResponse)?.statusCode else { break }
            switch code {
            case 200:
                try? FileManager.default.removeItem(at: file)
                sent.insert(file.lastPathComponent)
            case 400, 413:
                log.error("ride \(file.lastPathComponent) rejected (\(code)), dropped")
                try? FileManager.default.removeItem(at: file)
            default:
                log.notice("ride \(file.lastPathComponent) kept for retry (\(code))")
            }
        }
        return sent
    }
}

/// Toronto's public close-pass layer from GET /v1/city-risk.geojson, cached to
/// Documents/city-risk.geojson so the map still has it offline.
struct CityLayer {
    struct Segment: Identifiable { let id: Int; let line: MKPolyline; let per100km: Double }
    struct Pass: Identifiable { let id: Int; let coordinate: CLLocationCoordinate2D; let level: Int; let demo: Bool }
    var segments: [Segment] = []
    var passes: [Pass] = []
    /// True when any of it is modelled rather than ridden; the map must say so.
    var synthetic = false

    static let cache = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("city-risk.geojson")

    /// The live layer, else the cached one; nil with no server set or nothing cached.
    /// `testRides` adds test rides (practice and stage demos), which the public layer leaves out.
    static func load(testRides: Bool = false) async -> CityLayer? {
        guard !CityAPI.base.isEmpty,
              let url = URL(string: CityAPI.base + "/v1/city-risk.geojson" + (testRides ? "?demo=1" : "")) else { return nil }
        // Fresh every time the map opens, so a ride sent a moment ago is on it.
        let req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        if let (data, resp) = try? await URLSession.shared.data(for: req),
           (resp as? HTTPURLResponse)?.statusCode == 200, let layer = CityLayer(data) {
            try? data.write(to: cache, options: .atomic)
            return layer
        }
        return (try? Data(contentsOf: cache)).flatMap(CityLayer.init)
    }

    private struct Props: Decodable {
        let per_100km: Double?
        let synthetic_share: Double?
        let kind: String?
        let level: Int?
        let synthetic: Bool?
        let demo: Bool?
    }

    init?(_ data: Data) {
        guard let objects = try? MKGeoJSONDecoder().decode(data) else { return nil }
        for case let (i, feature as MKGeoJSONFeature) in objects.enumerated() {
            guard let p = feature.properties.flatMap({ try? JSONDecoder().decode(Props.self, from: $0) }) else { continue }
            if let line = feature.geometry.first as? MKPolyline, let rate = p.per_100km {
                segments.append(Segment(id: i, line: line, per100km: rate))
                synthetic = synthetic || (p.synthetic_share ?? 0) > 0
            } else if let point = feature.geometry.first as? MKPointAnnotation, p.kind == "pass" {
                passes.append(Pass(id: i, coordinate: point.coordinate, level: p.level ?? 2, demo: p.demo == true))
                synthetic = synthetic || p.synthetic == true
            }
        }
    }
}

/// The few seconds after a ride ends: whether its near misses reached the city map.
struct UploadNote: View {
    @ObservedObject var uploader: CityUploader

    var body: some View {
        if let note = uploader.note {
            Text(note)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(Light.ink)
                .padding(.horizontal, 16).padding(.vertical, 10)
                .background(.white.opacity(0.95), in: Capsule())
                .shadow(color: Light.shadow, radius: 12, y: 4)
                .padding(.top, 8).padding(.horizontal, 16)
                .transition(.move(edge: .top).combined(with: .opacity))
        }
    }
}

/// The City of Toronto's own layers, bundled (CityLayers.json from tools/city_app_layers.py):
/// protected and painted bike lanes, and every cyclist killed or seriously injured 2022 to
/// Oct 2026 (Vision Zero). Real City data, drawn under the near misses for context.
struct CityContext {
    struct Lane: Identifiable { let id: Int; let protected: Bool; let points: [CLLocationCoordinate2D] }
    struct KSI: Identifiable { let id: Int; let coordinate: CLLocationCoordinate2D; let killed: Bool }
    let lanes: [Lane]
    let ksi: [KSI]

    private struct File: Decodable {
        struct L: Decodable { let t: String; let p: [Double] }
        struct K: Decodable { let lat: Double; let lon: Double; let killed: Bool }
        let lanes: [L]
        let ksi: [K]
    }

    static let bundled: CityContext? = {
        guard let url = Bundle.main.url(forResource: "CityLayers", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let f = try? JSONDecoder().decode(File.self, from: data) else { return nil }
        return CityContext(
            lanes: f.lanes.enumerated().map { i, l in
                Lane(id: i, protected: l.t == "protected", points: stride(from: 0, to: l.p.count - 1, by: 2).map {
                    CLLocationCoordinate2D(latitude: l.p[$0], longitude: l.p[$0 + 1])
                })
            },
            ksi: f.ksi.enumerated().map { i, k in
                KSI(id: i, coordinate: CLLocationCoordinate2D(latitude: k.lat, longitude: k.lon), killed: k.killed)
            })
    }()
}
