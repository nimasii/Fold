import SwiftUI
import AVKit

/// The single inline player surface for server videos and private local copies.
/// Playback sources/lifecycles are injected; native AVKit and VLC controls stay identical.
struct VideoPlayerSurface<Overlay: View>: View {
    let video: Video
    let player: AVPlayer?
    let vlcURL: URL?
    @Binding var isFullScreen: Bool
    @Binding var isPiPActive: Bool
    var isBuffering = false
    var localArtworkURL: URL? = nil
    var startPosition: Double = 0
    var playbackError: String? = nil
    var seekInterval = 10
    var seekFeedback: PlayerSeekFeedback? = nil
    var vlcSponsorBlockSeekTarget: Double? = nil
    var vlcSeekDelta: Double? = nil
    var onTimeChanged: (Double) -> Void = { _ in }
    var onPlaybackEnded: () -> Void = {}
    var onPlaybackResumed: () -> Void = {}
    var onClearVLCSeekDelta: () -> Void = {}
    var onDoubleTap: ((Bool) -> Void)? = nil
    var onPiPStopped: () -> Void = {}
    var onPlay: () -> Void
    var onRetry: () -> Void
    let overlay: Overlay

    var body: some View {
        Group {
            if let player = player {
                ZStack {
                    AVPlayerView(
                        player: player,
                        isFullScreen: $isFullScreen,
                        isPiPActive: $isPiPActive,
                        onPiPStopped: onPiPStopped
                    )
                    if isBuffering {
                        Color.black
                        ProgressView()
                            .controlSize(.large)
                            .tint(.white)
                    }
                    overlay
                }
                .aspectRatio(16.0 / 9.0, contentMode: .fill)
                .frame(maxWidth: .infinity)
                .clipped()
            } else if let vlcURL = vlcURL {
                #if UI_REVIEW_PREVIEW
                Text(String(localized: "offline_vlc_preview")).aspectRatio(16.0 / 9.0, contentMode: .fit)
                #else
                ZStack {
                    VLCPlayerView(
                        mediaURL: vlcURL,
                        startPosition: startPosition,
                        duration: Double(video.duration),
                        onTimeChanged: { seconds in onTimeChanged(seconds) },
                        isFullScreen: $isFullScreen,
                        sponsorBlockSeekTarget: vlcSponsorBlockSeekTarget,
                        seekDelta: vlcSeekDelta,
                        onSeekDeltaConsumed: { onClearVLCSeekDelta() },
                        onPlaybackEnded: onPlaybackEnded, onPlaybackResumed: onPlaybackResumed, onDoubleTap: onDoubleTap
                    )
                    if isBuffering {
                        Color.black
                        ProgressView()
                            .controlSize(.large)
                            .tint(.white)
                    }
                    PlayerSeekFeedbackOverlay(
                        seekInterval: seekInterval,
                        feedback: seekFeedback
                    )
                    overlay
                }
                .aspectRatio(16.0 / 9.0, contentMode: .fill)
                .frame(maxWidth: .infinity)
                .clipped()
                #endif
            } else {
                ZStack {
                    Color.black
                        .aspectRatio(16.0 / 9.0, contentMode: .fit)
                        .overlay { AuthenticatedAsyncImage(url: video.thumbUrl, localFileURL: localArtworkURL) }
                        .clipped().accessibilityHidden(true)

                    if isBuffering {
                        ProgressView()
                            .controlSize(.large)
                            .tint(.white)
                    } else {
                        Button {
                            onPlay()
                        } label: {
                            Image(systemName: "play.fill").font(.title)
                                .frame(width: 24, height: 24)
                        }
                        .foldAction(prominent: true, shape: .circle)
                        .accessibilityLabel(String(localized: "video_detail_play"))
                    }

                    if let playbackError = playbackError {
                        VStack {
                            HStack(spacing: 8) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.caption)
                                Text(playbackError)
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .lineLimit(3)
                                Spacer()
                                Button {
                                    onRetry()
                                } label: {
                                    Text(String(localized: "retry"))
                                        .font(.caption)
                                        .fontWeight(.bold)
                                }
                                .accessibilityLabel(String(localized: "retry"))
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .foldControlSurface()
                            .padding(.horizontal, 8)
                            .padding(.top, 8)

                            Spacer()
                        }
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .animation(.easeInOut(duration: 0.3), value: self.playbackError)
                    }
                }
                .aspectRatio(16.0 / 9.0, contentMode: .fit)
            }
        }
        .accessibilityIdentifier("video.player.surface")
    }
}

/// Shared pin/scroll behavior keeps the local detail screen in the normal navigation flow.
struct VideoDetailLayout<Player: View, Details: View>: View {
    let isPinned: Bool
    @Environment(\.horizontalSizeClass) private var sizeClass
    @ViewBuilder var player: () -> Player
    @ViewBuilder var details: () -> Details
    var body: some View {
        if isPinned {
            VStack(spacing: 0) { fittedPlayer; ScrollView { fittedDetails } }
        } else {
            ScrollView { VStack(spacing: 0) { fittedPlayer; fittedDetails } }
        }
    }
    private var fittedPlayer: some View {
        player().frame(maxWidth: sizeClass == .regular ? 960 : .infinity)
            .frame(maxWidth: .infinity).background(.black)
    }
    private var fittedDetails: some View {
        details().frame(maxWidth: sizeClass == .regular ? 960 : .infinity)
            .frame(maxWidth: .infinity)
    }
}
