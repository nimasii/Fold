import SwiftUI

struct VideoInfoSection: View {
    let video: Video
    var onChannelTap: ((String) -> Void)? = nil
    var localArtwork: LocalVideoArtwork? = nil
    var showsStatistics: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(video.title).font(.title.bold()).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 12) {
                Text(video.durationStr).monospacedDigit()
                if !video.publishedShort.isEmpty { Text(video.publishedShort) }
                if video.watched { Label(String(localized: "filter_watched"), systemImage: "checkmark.circle") }
            }
            .font(.subheadline).foregroundStyle(.secondary)
            if let onChannelTap, !video.channelId.isEmpty {
                Button { onChannelTap(video.channelId) } label: { channelLabel }
                    .buttonStyle(.plain).accessibilityLabel(video.channelName)
                    .accessibilityHint(String(localized: "stream_open_channel"))
            } else { channelLabel }
            DisclosureGroup(String(localized: "stream_video_details")) {
                VStack(alignment: .leading, spacing: 10) {
                    if showsStatistics {
                        HStack(spacing: 20) {
                            Label("\(video.viewCount)", systemImage: "eye")
                            Label("\(video.likeCount)", systemImage: "hand.thumbsup")
                        }
                    }
                    if !video.published.isEmpty { Text(String(localized: "video_detail_published \(video.published)")) }
                    if !video.downloaded.isEmpty { Text(String(localized: "video_detail_downloaded \(video.downloaded)")) }
                    ForEach(video.streams, id: \.self) { stream in
                        Text([stream.type.capitalized, stream.codec,
                              stream.width.flatMap { w in stream.height.map { "\(w) × \($0)" } } ?? "",
                              stream.bitrate > 0 ? "\(stream.bitrate / 1000) kbps" : ""].filter { !$0.isEmpty }.joined(separator: " · "))
                    }
                    Text(String(localized: "video_detail_file_size \(FormattedFileSize.format(video.mediaSize))"))
                }
                .font(.footnote).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading).padding(.top, 12)
            }
            .font(.subheadline.weight(.medium))
        }
        .padding(.horizontal, StreamingStyle.gutter)
    }
    private var channelLabel: some View {
        HStack(spacing: 12) {
            AuthenticatedAsyncImage(url: video.channelThumbUrl, placeholderColor: Color(.tertiarySystemBackground),
                localFileURL: localArtwork?.channel, localRevision: localArtwork?.revision ?? 0)
                .frame(width: 44, height: 44).clipShape(.circle).accessibilityHidden(true)
            Text(video.channelName).font(.headline).foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
            if onChannelTap != nil {
                Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(.secondary).accessibilityHidden(true)
            }
        }.frame(minHeight: 48).contentShape(Rectangle())
    }
}
