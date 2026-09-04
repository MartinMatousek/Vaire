import SwiftUI
import VaireKit

/// Searchable picker for choosing which 1Password item is the timesheet login.
/// Shows titles only, never a secret value — this view never touches
/// `op item get`, only `op item list`.
struct OnePasswordItemPickerView: View {
    let onSelect: (OnePasswordItem) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var items: [OnePasswordItem] = []
    @State private var searchText = ""
    @State private var isLoading = true
    @State private var loadError: String?

    private var filteredItems: [OnePasswordItem] {
        guard !searchText.isEmpty else { return items }
        return items.filter { $0.title.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(Strings.onePasswordPickerTitle)
                .font(.headline)

            TextField(Strings.onePasswordPickerSearch, text: $searchText)
                .textFieldStyle(.roundedBorder)

            if isLoading {
                ProgressView()
            } else if let loadError {
                Text(loadError)
                    .font(.caption)
                    .foregroundStyle(.red)
            } else {
                List(filteredItems) { item in
                    Button(item.title) {
                        onSelect(item)
                        dismiss()
                    }
                    .buttonStyle(.plain)
                }
                .frame(minHeight: 200, maxHeight: 320)
            }

            HStack {
                Spacer()
                Button(Strings.cancel) { dismiss() }
            }
        }
        .padding()
        .frame(width: 360)
        .onAppear(perform: load)
    }

    private func load() {
        isLoading = true
        loadError = nil
        Task {
            do {
                let fetched = try await OnePasswordCLI.listItems()
                await MainActor.run {
                    items = fetched.sorted { $0.title < $1.title }
                    isLoading = false
                }
            } catch {
                await MainActor.run {
                    loadError = error.localizedDescription
                    isLoading = false
                }
            }
        }
    }
}
