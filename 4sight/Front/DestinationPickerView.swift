import Combine
import MapKit
import SwiftUI

/// Search field + completer results. Rows are ≥ 56 pt for gloved taps.
struct DestinationPickerView: View {
    let onPick: (MKMapItem) -> Void
    @Environment(\.dismiss) private var dismiss
    @StateObject private var completer = Completer()
    @State private var busy = false

    var body: some View {
        VStack(spacing: 0) {
            TextField("Where to?", text: $completer.query)
                .font(.system(size: 22, weight: .semibold, design: .rounded))
                .foregroundStyle(Light.ink)
                .padding(16)
                .frame(minHeight: 56)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 14))
                .padding(16)
                .autocorrectionDisabled()
            List(completer.results, id: \.self) { r in
                Button { pick(r) } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(r.title).font(.system(size: 20, weight: .semibold, design: .rounded))
                            .foregroundStyle(Light.ink)
                        Text(r.subtitle).font(.system(size: 15, design: .rounded))
                            .foregroundStyle(Light.dim)
                    }
                    .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
                }
                .listRowBackground(Light.sheet)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
        .background(Light.sheet)
        .overlay { if busy { ProgressView().tint(Light.ink) } }
        .preferredColorScheme(.light)
    }

    private func pick(_ completion: MKLocalSearchCompletion) {
        busy = true
        Task {
            defer { busy = false }
            if let item = await Self.resolve(completion) {
                onPick(item)
                dismiss()
            }
        }
    }

    static func resolve(_ completion: MKLocalSearchCompletion) async -> MKMapItem? {
        try? await MKLocalSearch(request: MKLocalSearch.Request(completion: completion)).start().mapItems.first
    }

    final class Completer: NSObject, ObservableObject, MKLocalSearchCompleterDelegate {
        @Published var query = "" { didSet { completer.queryFragment = query } }
        @Published var results: [MKLocalSearchCompletion] = []
        private let completer = MKLocalSearchCompleter()

        override init() {
            super.init()
            completer.delegate = self
            completer.resultTypes = [.address, .pointOfInterest]
        }

        func completerDidUpdateResults(_ c: MKLocalSearchCompleter) { results = c.results }
    }
}
