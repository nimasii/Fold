import SwiftUI

struct VideoCardView: View {
    let video: Video
    @Environment(\.playbackCoordinator) private var history
    private var displayed: Video { history?.project(video) ?? video }
    var onChannelTap: ((String) -> Void)? = nil
    var localArtwork: LocalVideoArtwork? = nil
    var supplementaryText: String? = nil
    private var artwork: LocalVideoArtwork? { localArtwork ?? history?.artwork(for: video) }
    var onOpen: (() -> Void)? = nil
    var isSelected: Bool = false
    var onSelect: (() -> Void)? = nil
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if onOpen != nil { selectableButton } else { posterAndTitle }
            if let onChannelTap, !displayed.channelId.isEmpty {
                Button { onChannelTap(displayed.channelId) } label: { channelLabel }
                    .buttonStyle(.plain).accessibilityLabel(displayed.channelName)
                    .accessibilityHint(String(localized: "stream_open_channel"))
            } else { channelLabel }
            if let supplementaryText {
                Text(supplementaryText).font(.caption).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .contain)
    }
    @ViewBuilder private var selectableButton: some View {
        if let onSelect {
            actionButton.highPriorityGesture(
                LongPressGesture(minimumDuration: 0.5).exclusively(before: TapGesture()).onEnded { event in
                    switch event {
                    case .first: onSelect()
                    case .second: onOpen?()
                    }
                }
            )
        } else { actionButton }
    }
    private var actionButton: some View {
        Button { onOpen?() } label: { posterAndTitle }
            .buttonStyle(MediaPressStyle())
            .accessibilityLabel("\(displayed.title), \(displayed.channelName), \(displayed.durationStr)")
            .accessibilityHint(String(localized: "stream_open_video"))
            .accessibilityIdentifier("video.card." + displayed.id)
            .accessibilityAddTraits(isSelected ? .isSelected : [])
            .accessibilityActions {
                if let onSelect { Button(String(localized: "stream_select"), action: onSelect) }
            }
    }
    private var posterAndTitle: some View {
        VStack(alignment: .leading, spacing: 10) {
            Color(.secondarySystemBackground)
                .aspectRatio(16 / 9, contentMode: .fit)
                .overlay {
                    AuthenticatedAsyncImage(url: displayed.thumbUrl, localFileURL: artwork?.thumbnail,
                                            localRevision: artwork?.revision ?? 0, serverVideoID: displayed.youtubeId)
                }
                .overlay(alignment: .bottomTrailing) {
                    Text(displayed.durationStr).font(.caption2.weight(.semibold)).monospacedDigit()
                        .foregroundStyle(.white).padding(.horizontal, 7).padding(.vertical, 4)
                        .background(.black.opacity(0.8), in: .rect(cornerRadius: 6)).padding(8)
                }
                .overlay(alignment: .topLeading) {
                    if displayed.watched {
                        Image(systemName: "checkmark.circle.fill").font(.caption)
                            .foregroundStyle(.white).padding(6).background(.black.opacity(0.8), in: .circle).padding(8)
                    }
                }
                .overlay(alignment: .bottomLeading) {
                    if displayed.progress > 0 && PlaybackCompletion.resumePosition(position: displayed.position, duration: Double(displayed.duration), watched: displayed.watched) > 0 {
                        GeometryReader { geometry in
                            Rectangle().fill(.tint)
                                .frame(width: geometry.size.width * min(100, max(0, displayed.progress)) / 100, height: 3)
                                .frame(maxHeight: .infinity, alignment: .bottom)
                        }
                    }
                }
                .clipShape(.rect(cornerRadius: StreamingStyle.corner))
                .accessibilityHidden(true)
            Text(displayed.title).font(.callout.weight(.semibold)).foregroundStyle(.primary)
                .lineLimit(typeSize.isAccessibilitySize ? nil : 3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }.contentShape(Rectangle())
    }
    private var channelLabel: some View {
        HStack(alignment: .center, spacing: 7) {
            AuthenticatedAsyncImage(url: displayed.channelThumbUrl, placeholderColor: Color(.tertiarySystemBackground),
                localFileURL: artwork?.channel, localRevision: artwork?.revision ?? 0)
                .frame(width: 22, height: 22).clipShape(.circle).accessibilityHidden(true)
            Text(displayed.channelName).font(.caption).foregroundStyle(.secondary)
                .lineLimit(typeSize.isAccessibilitySize ? nil : 2)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minHeight: onChannelTap == nil ? 22 : 44, alignment: .leading)
        .contentShape(Rectangle())
    }
}
