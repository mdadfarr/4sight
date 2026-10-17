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
                .foregroundStyle(Theme.text)
                .padding(16)
                .frame(minHeight: 56)
                .background(Theme.ground, in: RoundedRectangle(cornerRadius: 14))
                .padding(16)
                .autocorrectionDisabled()
            List(completer.results, id: \.self) { r in
                Button { pick(r) } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(r.title).font(.system(size: 20, weight: .semibold, design: .rounded))
                            .foregroundStyle(Theme.text)
                        Text(r.subtitle).font(.system(size: 15, design: .rounded))
                            .foregroundStyle(Theme.textDim)
                    }
                    .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
                }
                .listRowBackground(Theme.bg)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
        .background(Theme.bg)
        .overlay { if busy { ProgressView().tint(Theme.text) } }
        .preferredColorScheme(.dark)
    }

    private func pick(_ completion: MKLocalSearchCompletion) {
        busy = true
        Task {
            defer { busy = false }
            let search = MKLocalSearch(request: MKLocalSearch.Request(completion: completion))
            if let item = try? await search.start().mapItems.first {
                onPick(item)
                dismiss()
            }
        }
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
