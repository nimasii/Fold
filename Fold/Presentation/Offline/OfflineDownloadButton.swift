import SwiftUI

struct OfflineDownloadButton: View {
    let video: Video
    @Environment(OfflineLibrary.self) private var library
    @Environment(AppRouter.self) private var router

    var body: some View {
        let record = library.record(for: video)
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Button {
                    if record?.status == .ready { router.navigate(to: .offlineDownloads) }
                    else { library.enqueue(video) }
                } label: {
                    Label(String(localized: record?.status == .ready ? "offline_downloaded" : "offline_download_action"),
                          systemImage: record?.status == .ready ? "checkmark.circle.fill" : "arrow.down.circle")
                }
                .buttonStyle(.bordered).controlSize(.large).buttonBorderShape(.capsule)
                .disabled(record?.status.isActive == true)
                .accessibilityLabel(String(localized: record?.status == .ready ? "offline_downloaded" : "offline_download_action"))
                Spacer(minLength: 4)
                if record?.status.isActive == true {
                    Button(String(localized: "offline_cancel"), systemImage: "stop.circle") {
                        if let record { library.cancel(record.id) }
                    }
                    .labelStyle(.iconOnly)
                    .accessibilityLabel(String(localized: "offline_cancel"))
                }
            }
            if let record, record.status.isActive {
                Text(record.status.label).font(.footnote).foregroundStyle(.secondary)
                ProgressView(value: record.status == .preparing ? record.attempt.flatMap { library.preparationProgress[$0] } : (record.totalBytes > 0 ? min(1, Double(record.bytes) / Double(record.totalBytes)) : nil))
                    .accessibilityLabel(String(localized: "offline_progress"))
            }
            if let message = record?.failure?.message ?? library.storageError {
                Text(message).font(.footnote).foregroundStyle(.secondary)
            }
            Text(String(localized: "offline_prepare_help")).font(.caption).foregroundStyle(.secondary)
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
    }
}
