#if DEBUG && targetEnvironment(simulator) && !UI_REVIEW_PREVIEW
import SwiftUI

/// Actual shipping screens and media services with isolated, clearly labeled test data.
struct StreamingFixtureRoot: View {
    @Environment(DependencyContainer.self) private var container
    @Environment(\.dynamicTypeSize) private var systemTypeSize
    @State private var routed = false
    private let arguments = ProcessInfo.processInfo.arguments
    private var privateArtworkCount: Int {
        container.offlineLibrary.records.reduce(0) { count, record in
            count + (container.offlineLibrary.thumbnailURL(record.id) == nil ? 0 : 1)
                + (container.offlineLibrary.channelArtworkURL(record.id) == nil ? 0 : 1)
        }
    }
    var body: some View {
        VStack(spacing: 0) {
            Text(String(localized: "stream_fixture")).font(.caption2.weight(.semibold))
                .dynamicTypeSize(...DynamicTypeSize.large)
                .foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(.vertical, 4)
                .accessibilityIdentifier("streaming.fixture-label")
                .accessibilityValue("Private artwork: \(privateArtworkCount)")
            if arguments.contains("--cinema-audit-standalone") {
                NavigationStack { SettingsScreen { container.makeSettingsViewModel() } }
            } else { RootView() }
        }
            .preferredColorScheme(arguments.contains("--streaming-fixture-dark") ? .dark : arguments.contains("--streaming-fixture-light") ? .light : nil)
            .dynamicTypeSize(arguments.contains("--streaming-fixture-accessibility") ? .accessibility3 : systemTypeSize)
            .task {
                guard !routed else { return }; routed = true
                switch arguments.first(where: { $0.hasPrefix("--cinema-screen=") })?.components(separatedBy: "=").last {
                case "channel": container.router.navigate(to: .channelDetail(channelId: "channel-orbital-journal"))
                case "playlists": container.router.navigate(to: .playlistList)
                case "regular": container.router.navigate(to: .playlistDetail(playlistId: "orbital"))
                case "custom": container.router.navigate(to: .playlistDetail(playlistId: "lunar"))
                case "video": container.router.navigate(to: .videoDetail(videoId: "earthrise"))
                case "settings": container.router.navigate(to: .settings)
                case "about": container.router.navigate(to: .about)
                case "queue": container.router.selectedTab = .queue
                case "downloads": container.router.selectedTab = .downloads
                default: break
                }
            }
            .task {
                guard !arguments.contains("--streaming-fixture-login"), !arguments.contains("--cinema-state=empty"), container.offlineLibrary.records.isEmpty,
                      let fixture = container.videoRepository as? StreamingFixtureRepository,
                      fixture.videos.count > 1 else { return }
                container.offlineLibrary.enqueue(fixture.videos[1])
            }
    }
}
#endif
