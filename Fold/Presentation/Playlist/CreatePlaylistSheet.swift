import SwiftUI

/// Shared native sheet for collection creation from either entry point.
struct CreatePlaylistSheet: View {
    @Environment(\.dismiss) private var dismiss
    @FocusState private var nameFocused: Bool
    @State private var name = ""
    let onCreate: (String) -> Void

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 24) {
                Text(String(localized: "cinema_collections_eyebrow"))
                    .font(.caption.weight(.semibold)).tracking(2).foregroundStyle(.secondary)
                TextField(String(localized: "playlist_name_placeholder"), text: $name)
                    .textFieldStyle(.plain).font(.body).padding(16)
                    .background(StreamingStyle.surface, in: .rect(cornerRadius: 12))
                    .focused($nameFocused).submitLabel(.done).onSubmit(create)
                    .accessibilityLabel(String(localized: "playlist_name_placeholder"))
                    .accessibilityIdentifier("playlist.create.name")
                Button(action: create) {
                    Label(String(localized: "playlist_create_confirm"), systemImage: "plus")
                        .frame(maxWidth: .infinity, minHeight: 28)
                }.foldAction(prominent: true)
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityIdentifier("playlist.create.confirm")
                Spacer(minLength: 0)
            }
            .padding(StreamingStyle.gutter).background(StreamingStyle.background)
            .navigationTitle(String(localized: "playlist_create"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) {
                Button(String(localized: "cancel")) { dismiss() }
                    .accessibilityLabel(String(localized: "cancel"))
            } }
            .task { nameFocused = true }
        }
        .presentationDetents([.medium, .large]).presentationDragIndicator(.visible)
    }

    private func create() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        nameFocused = false
        onCreate(trimmed)
        dismiss()
    }
}
