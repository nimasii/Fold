import SwiftUI

struct SimilarVideosSection: View {
    let videos: [Video]
    let isLoading: Bool
    var onVideoTap: ((String) -> Void)? = nil
    var onChannelTap: ((String) -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding()
            } else if videos.isEmpty {
                Text(String(localized: "video_detail_no_similar"))
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
                    .padding()
            } else {
                LazyVStack(spacing: 12) {
                    ForEach(videos) { video in
                        VStack(alignment: .leading, spacing: 4) {
                            Button { onVideoTap?(video.youtubeId) } label: { CinemaVideoRow(video: video) }
                                .buttonStyle(MediaPressStyle())
                                .accessibilityLabel("\(video.title), \(video.durationStr)")
                            if !video.channelId.isEmpty {
                                Button(video.channelName) { onChannelTap?(video.channelId) }
                                    .font(.caption).frame(minHeight: 44)
                                    .accessibilityLabel(video.channelName)
                            }
                        }
                    }
                }
                .padding(.horizontal)
            }
        }
    }
}
