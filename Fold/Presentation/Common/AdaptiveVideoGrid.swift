import SwiftUI

private extension View {
    @ViewBuilder
    func `if`<Content: View>(_ condition: Bool, transform: (Self) -> Content) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
}

struct AdaptiveVideoGrid: View {
    let videos: [Video]
    var onVideoTap: (String) -> Void
    var onChannelTap: ((String) -> Void)? = nil
    var onToggleWatched: ((String) -> Void)? = nil
    var onNearEnd: (() -> Void)? = nil
    var localArtwork: [String: LocalVideoArtwork] = [:]
    var supplementaryText: [String: String] = [:]
    var onRemoveLocalCopy: ((String) -> Void)? = nil
    var onRefreshLocalDetails: ((String) -> Void)? = nil
    var refreshableLocalIDs: Set<String> = []
    var onPrepareLocalArtwork: ((String) async -> Void)? = nil
    var artworkRequestRevision = ""

    var isSelecting: Bool = false
    var selectedIds: Set<String> = []
    var onEnterSelection: ((String) -> Void)? = nil
    var onToggleSelection: ((String) -> Void)? = nil

    @Environment(\.dynamicTypeSize) private var typeSize
    private var columns: [GridItem] { [GridItem(.adaptive(minimum: typeSize.isAccessibilitySize ? 300 : 160), spacing: 16)] }

    var body: some View {
        let nearEnd = Set(videos.suffix(5).map(\.id))
        LazyVGrid(columns: columns, alignment: .leading, spacing: 24) {
            ForEach(videos) { video in
                VideoCardView(video: video, onChannelTap: isSelecting ? nil : onChannelTap,
                              localArtwork: localArtwork[video.id], supplementaryText: supplementaryText[video.id],
                              onOpen: {
                                  if isSelecting { onToggleSelection?(video.id) }
                                  else { onVideoTap(video.id) }
                              }, isSelected: isSelecting && selectedIds.contains(video.youtubeId),
                              onSelect: onEnterSelection != nil ? { if !isSelecting { onEnterSelection?(video.youtubeId) } } : nil)
                    .contentShape(Rectangle())
                    .overlay {
                        if isSelecting {
                            ZStack(alignment: .topLeading) {
                                Color.black.opacity(selectedIds.contains(video.youtubeId) ? 0.15 : 0)
                                Image(systemName: selectedIds.contains(video.youtubeId) ? "checkmark.circle.fill" : "circle")
                                    .font(.title2)
                                    .foregroundStyle(selectedIds.contains(video.youtubeId) ? Color.accentColor : .white)
                                    .shadow(radius: 2)
                                    .padding(8)
                            }.allowsHitTesting(false).accessibilityHidden(true)
                        }
                    }
                    .if(onEnterSelection == nil) { view in
                        view.contextMenu {
                            if let onRemoveLocalCopy {
                                Button(role: .destructive) { onRemoveLocalCopy(video.id) } label: {
                                    Label(String(localized: "offline_remove"), systemImage: "trash")
                                }
                                .accessibilityLabel(String(localized: "offline_remove"))
                            }
                            if let onRefreshLocalDetails, refreshableLocalIDs.contains(video.id) {
                                Button { onRefreshLocalDetails(video.id) } label: {
                                    Label(String(localized: "offline_refresh_details"), systemImage: "arrow.clockwise")
                                }
                                .accessibilityLabel(String(localized: "offline_refresh_details"))
                            }
                            if let onToggleWatched {
                                Button {
                                    onToggleWatched(video.youtubeId)
                                } label: {
                                    Label(
                                        video.watched
                                            ? String(localized: "video_mark_unwatched")
                                            : String(localized: "video_mark_watched"),
                                        systemImage: video.watched ? "eye.slash" : "eye"
                                    )
                                }
                            }
                        }
                    }
                    .task(id: artworkRequestRevision) { await onPrepareLocalArtwork?(video.id) }
                    .onAppear {
                        if nearEnd.contains(video.id) {
                            onNearEnd?()
                        }
                    }
            }
        }
        .padding(.horizontal, StreamingStyle.gutter)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("video.grid")
    }
}
