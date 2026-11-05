import SwiftUI

/// Shared editorial hierarchy. Content stays opaque; system navigation supplies glass.
enum StreamingStyle {
    static let gutter: CGFloat = 20
    static let corner: CGFloat = 14
    static let background = Color("CinemaCanvas")
    static let surface = Color("CinemaSurface")
    static let elevated = Color("CinemaElevated")
    static let accent = Color("CinemaAccent")
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

/// Compact hero preserves the full landscape thumbnail and exposes the first shelf.
struct FeaturedVideo: View {
    let video: Video
    @Environment(\.playbackCoordinator) private var history
    let onOpen: () -> Void
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        let video = history?.project(video) ?? video
        VStack(alignment: .leading, spacing: typeSize.isAccessibilitySize ? 16 : -64) {
            Color.black.aspectRatio(16 / 9, contentMode: .fit)
                .frame(maxHeight: sizeClass == .regular ? 320 : nil)
                .overlay { AuthenticatedAsyncImage(url: video.thumbUrl, localFileURL: history?.artwork(for: video)?.thumbnail) }
                .overlay(alignment: .bottom) {
                    LinearGradient(colors: [.clear, .black.opacity(0.9)], startPoint: .top, endPoint: .bottom)
                        .frame(height: 80)
                }
                .clipped().accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 12) {
                Text(String(localized: "cinema_your_library"))
                    .font(.caption.weight(.semibold)).tracking(2).foregroundStyle(.secondary)
                Text(video.title).font(.title.weight(.bold))
                    .lineLimit(typeSize.isAccessibilitySize ? nil : 2)
                    .fixedSize(horizontal: false, vertical: true)
                Text("\(video.channelName) · \(video.durationStr)")
                    .font(.subheadline).foregroundStyle(.secondary)
                Button(action: onOpen) {
                    Label(String(localized: PlaybackCompletion.resumePosition(position: video.position, duration: Double(video.duration), watched: video.watched) > 0 ? "cinema_resume" : "video_detail_play"), systemImage: "play.fill")
                        .font(.headline).frame(maxWidth: .infinity, minHeight: 34)
                }
                .foldAction(prominent: true)
                .frame(maxWidth: sizeClass == .regular ? 360 : .infinity)
                .accessibilityIdentifier("library.featured.play")
                .accessibilityLabel(String(localized: PlaybackCompletion.resumePosition(position: video.position, duration: Double(video.duration), watched: video.watched) > 0 ? "cinema_resume" : "video_detail_play") + ", " + video.title)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, StreamingStyle.gutter).padding(.bottom, 12)
        }
        .background(.black)
        .accessibilityIdentifier("watch.featured")
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
                LazyHStack(alignment: .top, spacing: 12) {
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
    @State private var searchPresented = false
    @State private var legacyPlayerVisible = false
    @ViewBuilder let destination: (Route) -> Destination

    @ViewBuilder var body: some View {
        if #available(iOS 26, *), !usesLegacySearch { nativeTabs }
        else { legacyShell }
    }

    /// Search is the native trailing affordance, not another primary section.
    @available(iOS 26, *)
    private var nativeTabs: some View {
        @Bindable var router = router
        return TabView(selection: Binding(
            get: { router.isLibrarySearchActive ? ShellSelection.search : .section(router.selectedTab) },
            set: { selection in
                switch selection {
                case .search:
                    router.beginLibrarySearch()
                    searchPresented = true
                case .section(let section):
                    router.cancelLibrarySearch(returnToOrigin: false)
                    router.selectedTab = section
                    searchPresented = false
                }
            }
        )) {
            Tab(String(localized: "stream_library"), systemImage: "play.rectangle.fill", value: ShellSelection.section(.library)) {
                section(.library) { VideoListScreen { container.makeVideoListViewModel() } }
            }
            Tab(String(localized: "offline_title"), systemImage: "arrow.down.circle.fill", value: ShellSelection.section(.downloads)) {
                section(.downloads) { downloads }
            }
            Tab(String(localized: "nav_queue"), systemImage: "server.rack", value: ShellSelection.section(.queue)) {
                section(.queue) { DownloadQueueScreen { container.makeDownloadQueueViewModel() } }
            }
            Tab(value: ShellSelection.search, role: .search) {
                searchNavigation.searchable(text: $router.librarySearchQuery, isPresented: $searchPresented, placement: .toolbar,
                    prompt: Text(String(localized: "nav_search_library")))
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
            }
        }
        .tint(.primary)
        .tabViewSearchActivation(.searchTabSelection)
        .onChange(of: searchPresented) { _, presented in
            if !presented && router.isLibrarySearchActive && router.librarySearchPath.isEmpty {
                router.cancelLibrarySearch()
            }
        }
        .onChange(of: router.isLibrarySearchActive) { _, active in
            if !active { searchPresented = false }
        }
        .onChange(of: router.librarySearchPath.count) { oldCount, count in
            if count > 0 { searchPresented = false }
            else if oldCount > 0 && router.isLibrarySearchActive { searchPresented = true }
        }
    }

    /// iOS 17–25 has no native inline search tab. Use one system-material row
    /// of accessible section buttons and search, replaced by the editor on focus.
    private var legacyShell: some View {
        @Bindable var router = router
        return ZStack {
            TabView(selection: $router.selectedTab) {
                section(.library, hidesTabs: true) { VideoListScreen { container.makeVideoListViewModel() } }.tag(AppTab.library)
                section(.downloads, hidesTabs: true) { downloads }.tag(AppTab.downloads)
                section(.queue, hidesTabs: true) { DownloadQueueScreen { container.makeDownloadQueueViewModel() } }.tag(AppTab.queue)
            }
            .toolbar(.hidden, for: .tabBar)
            .opacity(router.isLibrarySearchActive ? 0 : 1)
            .accessibilityHidden(router.isLibrarySearchActive)
            .allowsHitTesting(!router.isLibrarySearchActive)
            if router.isLibrarySearchActive { searchNavigation }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !isPlayerVisible {
                if router.isLibrarySearchActive { LibrarySearchEditor() }
                else {
                    HStack(spacing: 0) {
                        ForEach(AppTab.allCases, id: \.self) { tab in
                            Button { router.selectedTab = tab } label: {
                                VStack(spacing: 4) {
                                    Image(systemName: symbol(tab)).font(.body)
                                    if !dynamicTypeSize.isAccessibilitySize { Text(title(tab)).font(.caption2) }
                                }.frame(maxWidth: .infinity, minHeight: 48).contentShape(Rectangle())
                            }
                            .foregroundStyle(router.selectedTab == tab ? Color.accentColor : .secondary)
                            .accessibilityLabel(title(tab))
                            .accessibilityAddTraits(router.selectedTab == tab ? [.isSelected] : [])
                            .accessibilityIdentifier("section.tab." + String(tab.rawValue))
                        }
                        BottomLibrarySearch().frame(width: 52)
                    }.buttonStyle(.plain).padding(.horizontal, 12).background(.bar)
                }
            }
        }
        .onChange(of: router.librarySearchPath.count) { _, count in
            if count > 0 { router.librarySearchWantsFocus = false }
        }
    }
    private var downloads: some View {
        OfflineDownloadsView(videoRepository: container.videoRepository, playbackSettings: container.sponsorBlockSettings)
    }
    private var searchNavigation: some View {
        @Bindable var router = router
        return NavigationStack(path: $router.librarySearchPath) {
            LibrarySearchScreen { container.makeSearchViewModel() }
                .navigationDestination(for: Route.self) { route in
                    destination(route).toolbar(isPlayer(route) || usesLegacySearch ? .hidden : .visible, for: .tabBar)
                        .onAppear { legacyPlayerVisible = isPlayer(route) }
                        .onDisappear { if isPlayer(route) { legacyPlayerVisible = false } }
                }
        }
    }
    private var isPlayerVisible: Bool {
        router.isPrivatePlayerVisible || legacyPlayerVisible || (router.isLibrarySearchActive && !router.librarySearchPath.isEmpty)
    }
    private var usesLegacySearch: Bool {
        #if DEBUG && targetEnvironment(simulator)
        ProcessInfo.processInfo.arguments.contains("--navigation-legacy-search")
        #else
        false
        #endif
    }
    private func title(_ tab: AppTab) -> String {
        switch tab {
        case .library: String(localized: "stream_library")
        case .downloads: String(localized: "offline_title")
        case .queue: String(localized: "nav_queue")
        }
    }
    private func symbol(_ tab: AppTab) -> String {
        switch tab {
        case .library: "play.rectangle.fill"
        case .downloads: "arrow.down.circle.fill"
        case .queue: "server.rack"
        }
    }
    private func isPlayer(_ route: Route) -> Bool {
        if case .videoDetail = route { return true }
        return false
    }
    private func section<Content: View>(_ tab: AppTab, hidesTabs: Bool = false, @ViewBuilder content: () -> Content) -> some View {
        NavigationStack(path: Binding(get: { router.path(for: tab) }, set: { router.setPath($0, for: tab) })) {
            Group {
                if hidesTabs { content().toolbar(.hidden, for: .tabBar) }
                else { content() }
            }
                .navigationDestination(for: Route.self) { route in
                    destination(route).toolbar(isPlayer(route) || hidesTabs ? .hidden : .visible, for: .tabBar)
                        .onAppear { legacyPlayerVisible = isPlayer(route) }
                        .onDisappear { if isPlayer(route) { legacyPlayerVisible = false } }
                }
        }.tint(StreamingStyle.accent)
    }
    private enum ShellSelection: Hashable { case section(AppTab), search }
}
#endif
