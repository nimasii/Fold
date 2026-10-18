import SwiftUI

/// Shared editorial hierarchy. Content stays opaque; system navigation supplies glass.
enum StreamingStyle {
    static let gutter: CGFloat = 20
    static let corner: CGFloat = 16
    static let background = Color(.systemBackground)
}

struct MediaSectionHeading: View {
    let title: String
    var subtitle: String? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.title2.bold()).accessibilityAddTraits(.isHeader)
            if let subtitle { Text(subtitle).font(.subheadline).foregroundStyle(.secondary) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, StreamingStyle.gutter)
    }
}

struct MediaPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.8 : 1)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: configuration.isPressed)
    }
}

struct FeaturedVideo: View {
    let video: Video
    let onOpen: () -> Void
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        Group {
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 16) {
                    artwork.aspectRatio(16 / 9, contentMode: .fit).clipShape(.rect(cornerRadius: StreamingStyle.corner))
                    information
                }
            } else {
                Color(.secondarySystemBackground)
                    .aspectRatio(0.95, contentMode: .fit)
                    .overlay { artwork }
                    .overlay {
                        LinearGradient(colors: [.clear, .black.opacity(0.08), .black.opacity(0.96)], startPoint: .top, endPoint: .bottom)
                    }
                    .overlay(alignment: .bottomLeading) { information.padding(24).foregroundStyle(.white) }
                    .clipShape(.rect(cornerRadius: 24))
            }
        }
        .padding(.horizontal, StreamingStyle.gutter)
        .accessibilityIdentifier("watch.featured")
    }
    private var artwork: some View {
        Color(.secondarySystemBackground)
            .overlay { AuthenticatedAsyncImage(url: video.thumbUrl) }
            .clipped().allowsHitTesting(false).accessibilityHidden(true)
    }
    private var information: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(String(localized: "stream_featured"))
                .font(.caption.weight(.bold)).tracking(2)
            Text(video.title).font(.largeTitle.bold()).lineLimit(typeSize.isAccessibilitySize ? nil : 3)
                .fixedSize(horizontal: false, vertical: true)
            Text("\(video.channelName) · \(video.durationStr)").font(.subheadline.weight(.medium))
            Button(action: onOpen) {
                Label(String(localized: "stream_open_video"), systemImage: "arrow.up.right")
                    .font(.headline).frame(maxWidth: .infinity, minHeight: 32)
            }
            .buttonStyle(.borderedProminent).controlSize(.large).buttonBorderShape(.capsule)
            .tint(typeSize.isAccessibilitySize ? .accentColor : .white)
            .foregroundStyle(typeSize.isAccessibilitySize ? Color.white : Color.black)
            .accessibilityLabel(String(localized: "stream_open_video") + ", " + video.title)
        }
    }
}

struct VideoShelf: View {
    let title: String
    let videos: [Video]
    let onOpen: (String) -> Void
    var onChannel: ((String) -> Void)? = nil
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            MediaSectionHeading(title: title)
            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: 16) {
                    ForEach(videos) { video in
                        VideoCardView(video: video, onChannelTap: onChannel, onOpen: { onOpen(video.id) })
                            .frame(width: typeSize.isAccessibilitySize ? 300 : 260)
                    }
                }
                .padding(.horizontal, StreamingStyle.gutter)
            }
            .scrollIndicators(.hidden)
        }
    }
}

#if !UI_REVIEW_PREVIEW
struct StreamingTabs<Destination: View>: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(DependencyContainer.self) private var container
    @Environment(AppRouter.self) private var router
    @ViewBuilder let destination: (Route) -> Destination

    @ViewBuilder var body: some View {
        // Large discovery content can intercept native accessory taps on compact
        // screens. Accessibility sizes use the keyboard-safe inset placement.
        if #available(iOS 26.1, *), !usesLegacySearch, !dynamicTypeSize.isAccessibilitySize {
            tabs.tabViewBottomAccessory(isEnabled: showsSearch) { BottomLibrarySearch() }
        } else {
            tabs.safeAreaInset(edge: .bottom, spacing: 0) {
                if showsSearch { BottomLibrarySearch().padding(.horizontal).background(.bar) }
            }
        }
    }
    private var tabs: some View {
        @Bindable var router = router
        return TabView(selection: $router.selectedTab) {
            tab(.library) {
                LibraryRootScreen(makeVideos: { container.makeVideoListViewModel() }, makeSearch: { container.makeSearchViewModel() })
            }
            .tabItem { Label(String(localized: "stream_library"), systemImage: "play.rectangle.fill") }.tag(AppTab.library)
            tab(.downloads) {
                OfflineDownloadsView(videoRepository: container.videoRepository, playbackSettings: container.sponsorBlockSettings)
            }
            .tabItem { Label(String(localized: "offline_title"), systemImage: "arrow.down.circle.fill") }.tag(AppTab.downloads)
            tab(.queue) { DownloadQueueScreen { container.makeDownloadQueueViewModel() } }
                .tabItem { Label(String(localized: "nav_queue"), systemImage: "server.rack") }.tag(AppTab.queue)
        }
    }

    private var showsSearch: Bool { router.path.isEmpty && !router.isPrivatePlayerVisible && !(router.selectedTab == .library && router.isLibrarySearchActive) }
    private var usesLegacySearch: Bool {
        #if DEBUG && targetEnvironment(simulator)
        ProcessInfo.processInfo.arguments.contains("--navigation-legacy-search")
        #else
        false
        #endif
    }
    private func isPlayer(_ route: Route) -> Bool {
        if case .videoDetail = route { return true }
        return false
    }
    private func tab<Content: View>(_ tab: AppTab, @ViewBuilder content: () -> Content) -> some View {
        NavigationStack(path: Binding(get: { router.path(for: tab) }, set: { router.setPath($0, for: tab) })) {
            content().navigationDestination(for: Route.self) { route in
                destination(route).toolbar(isPlayer(route) ? .hidden : .visible, for: .tabBar)
            }
        }
    }
}
#endif
