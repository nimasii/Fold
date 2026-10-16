import SwiftUI

struct VideoCardView: View {
    let video: Video
    var onChannelTap: ((String) -> Void)? = nil
    var localArtwork: LocalVideoArtwork? = nil
    var supplementaryText: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Thumbnail with overlays
            ZStack(alignment: .bottom) {
                AuthenticatedAsyncImage(url: video.thumbUrl, localFileURL: localArtwork?.thumbnail, localRevision: localArtwork?.revision ?? 0)
                    .aspectRatio(16.0 / 9.0, contentMode: .fit)
                    .background(Color(.secondarySystemBackground))
                    .clipped()

                // Overlay badges
                HStack(alignment: .bottom) {
                    QualityBadge(streams: video.streams)

                    Spacer()

                    VStack(alignment: .trailing, spacing: 4) {
                        // Duration badge
                        Text(video.durationStr)
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.black.opacity(0.7))
                            .clipShape(RoundedRectangle(cornerRadius: 4))

                        // Date badge
                        if !video.publishedShort.isEmpty {
                            Text(video.publishedShort)
                                .font(.caption2)
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(.black.opacity(0.7))
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                        }
                    }
                }
                .padding(8)

                // Progress bar
                if video.progress > 0 && !video.watched {
                    GeometryReader { geo in
                        VStack {
                            Spacer()
                            Rectangle()
                                .fill(Color.accentColor)
                                .frame(width: geo.size.width * video.progress / 100, height: 3)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            // Allow the title to grow with Dynamic Type and localized text.
            Text(video.title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)

            // Channel info
            Group {
                if let onChannelTap, !video.channelId.isEmpty {
                    Button { onChannelTap(video.channelId) } label: { channelLabel }
                        .buttonStyle(.plain).accessibilityLabel(video.channelName)
                } else { channelLabel }
            }
            if let supplementaryText {
                Text(supplementaryText).font(.caption).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(video.title), \(video.channelName), \(video.durationStr)")
    }
    private var channelLabel: some View {
        HStack(spacing: 8) {
            AuthenticatedAsyncImage(
                url: video.channelThumbUrl,
                placeholderColor: Color(.tertiarySystemBackground),
                localFileURL: localArtwork?.channel, localRevision: localArtwork?.revision ?? 0
            )
            .frame(width: 20, height: 20)
            .clipShape(Circle())

            Text(video.channelName)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }
}
