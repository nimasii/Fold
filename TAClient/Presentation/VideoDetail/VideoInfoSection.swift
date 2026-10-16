import SwiftUI

struct VideoInfoSection: View {
    let video: Video
    var onChannelTap: ((String) -> Void)? = nil
    var localArtwork: LocalVideoArtwork? = nil
    var showsStatistics: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Title
            Text(video.title)
                .font(.title3.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)

            // Channel
            Group {
                if let onChannelTap, !video.channelId.isEmpty {
                    Button { onChannelTap(video.channelId) } label: { channelLabel }
                        .buttonStyle(.plain).accessibilityLabel(video.channelName)
                } else { channelLabel }
            }

            // Stats/dates + Media info
            ViewThatFits(in: .horizontal) {
                datesAndMedia(short: false)
                datesAndMedia(short: true)
            }
        }
        .padding(16)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.horizontal)
    }

    @ViewBuilder
    private func datesAndMedia(short: Bool) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                if showsStatistics {
                    HStack(spacing: 16) {
                        Label("\(video.viewCount)", systemImage: "eye")
                        Label("\(video.likeCount)", systemImage: "hand.thumbsup")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                if !video.published.isEmpty {
                    Text(String(localized: "video_detail_published \(short ? video.publishedShort : video.published)"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if !video.downloaded.isEmpty {
                    Text(String(localized: "video_detail_downloaded \(short ? video.downloadedShort : video.downloaded)"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if !video.streams.isEmpty {
                Spacer()
                mediaInfoSection
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private var mediaInfoSection: some View {
        VStack(alignment: .trailing, spacing: 4) {
            ForEach(video.streams, id: \.self) { stream in
                HStack(spacing: 4) {
                    Text(stream.type.capitalized)
                        .fontWeight(.medium)
                    Text(stream.codec)
                    if let w = stream.width, let h = stream.height {
                        Text("\(w)x\(h)")
                    }
                    if stream.bitrate > 0 {
                        Text("\(stream.bitrate / 1000)kbps")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize()
            }
            Text(String(localized: "video_detail_file_size \(FormattedFileSize.format(video.mediaSize))"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize()
        }
    }
    private var channelLabel: some View {
        HStack(spacing: 8) {
            AuthenticatedAsyncImage(
                url: video.channelThumbUrl,
                placeholderColor: Color(.tertiarySystemBackground),
                localFileURL: localArtwork?.channel, localRevision: localArtwork?.revision ?? 0
            )
            .frame(width: 32, height: 32)
            .clipShape(Circle())

            Text(video.channelName)
                .font(.subheadline)
                .foregroundStyle(.primary)
        }
    }
}
