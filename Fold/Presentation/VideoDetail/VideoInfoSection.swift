import SwiftUI

struct VideoInfoSection: View {
    let video: Video
    var onChannelTap: ((String) -> Void)? = nil
    var localArtwork: LocalVideoArtwork? = nil
    var showsStatistics = true
    var onPlay: (() -> Void)? = nil
    var showsDownload = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(video.title).font(.title.weight(.bold)).fixedSize(horizontal: false, vertical: true)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) { metadata }
                VStack(alignment: .leading, spacing: 6) { metadata }
            }.font(.subheadline).foregroundStyle(.secondary)
            FoldGlassGroup {
                HStack(spacing: 12) {
                    if let onPlay {
                        Button(action: onPlay) {
                            Label(String(localized: video.position > 0 ? "cinema_resume" : "video_detail_play"), systemImage: "play.fill")
                                .font(.headline).frame(maxWidth: .infinity, minHeight: 28)
                        }.foldAction(prominent: true)
                        .accessibilityIdentifier("video.play-action")
                        .accessibilityLabel(String(localized: video.position > 0 ? "cinema_resume" : "video_detail_play") + ", " + video.title)
                    }
                    if showsDownload { OfflineDownloadButton(video: video, compact: true) }
                }
            }
            if let onChannelTap, !video.channelId.isEmpty {
                Button { onChannelTap(video.channelId) } label: { channelLabel }
                    .buttonStyle(.plain).accessibilityLabel(video.channelName)
                    .accessibilityHint(String(localized: "stream_open_channel"))
            } else { channelLabel }
        }.padding(.horizontal, StreamingStyle.gutter)
    }

    @ViewBuilder private var metadata: some View {
        Text(video.durationStr).monospacedDigit()
        if !video.publishedShort.isEmpty { Text(video.publishedShort) }
        if video.watched { Label(String(localized: "filter_watched"), systemImage: "checkmark.circle") }
    }

    private var channelLabel: some View {
        HStack(spacing: 12) {
            AuthenticatedAsyncImage(url: video.channelThumbUrl, placeholderColor: StreamingStyle.surface,
                localFileURL: localArtwork?.channel, localRevision: localArtwork?.revision ?? 0)
                .frame(width: 36, height: 36).clipShape(.circle).accessibilityHidden(true)
            Text(video.channelName).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
            if onChannelTap != nil {
                Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(.secondary).accessibilityHidden(true)
            }
        }.frame(minHeight: 44).contentShape(Rectangle())
    }
}

struct VideoTechnicalDetails: View {
    let video: Video
    var showsStatistics = true
    var body: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 12) {
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
            .font(.subheadline).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
            .padding(16).background(StreamingStyle.surface, in: .rect(cornerRadius: 18)).padding(.top, 12)
        } label: {
            Text(String(localized: "stream_video_details")).frame(minHeight: 44, alignment: .leading)
        }
        .font(.subheadline.weight(.medium)).padding(.horizontal, StreamingStyle.gutter)
    }
}
