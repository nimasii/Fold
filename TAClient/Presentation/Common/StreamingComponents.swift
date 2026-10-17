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

struct LibraryDestination: View {
    let title: String
    let detail: String
    let symbol: String
    let route: Route
    var body: some View {
        NavigationLink(value: route) {
            HStack(spacing: 16) {
                Image(systemName: symbol).font(.title3).foregroundStyle(.tint)
                    .frame(width: 44, height: 44)
                    .background(.tint.opacity(0.1), in: .rect(cornerRadius: 14))
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.headline)
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading).padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain).accessibilityLabel(title + ", " + detail)
        .accessibilityIdentifier("library.destination." + symbol)
    }
}

/// Uses existing destinations and device records; no recommendations or history are synthesized.
struct StreamingLibraryView: View {
    @Environment(OfflineLibrary.self) private var library
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                VStack(alignment: .leading, spacing: 12) {
                    Image(systemName: "rectangle.stack.fill").font(.largeTitle).foregroundStyle(.tint).accessibilityHidden(true)
                    Text(String(localized: "stream_library_intro")).font(.title2.bold())
                    Text(String(localized: "stream_library_description")).font(.body).foregroundStyle(.secondary)
                }.padding(.top, 16)
                if let record = library.records.first(where: { $0.status == .ready }) {
                    NavigationLink(value: Route.offlineDownloads) {
                        Color(.secondarySystemBackground).aspectRatio(16 / 9, contentMode: .fit)
                            .overlay {
                                AuthenticatedAsyncImage(url: nil, localFileURL: library.thumbnailURL(record.id), localRevision: library.artworkRevision)
                            }
                            .overlay { LinearGradient(colors: [.clear, .black.opacity(0.85)], startPoint: .top, endPoint: .bottom) }
                            .overlay(alignment: .bottomLeading) {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(String(localized: "stream_on_device")).font(.title2.bold())
                                    Text(String(localized: "stream_ready") + " · " + library.totalSize).font(.subheadline)
                                }.foregroundStyle(.white).padding(20)
                            }.clipped().clipShape(.rect(cornerRadius: 20))
                    }.buttonStyle(MediaPressStyle()).accessibilityLabel(String(localized: "offline_title"))
                }
                VStack(spacing: 0) {
                    LibraryDestination(title: String(localized: "playlist_list_title"), detail: String(localized: "stream_collections_help"), symbol: "rectangle.stack", route: .playlistList)
                    Divider()
                    LibraryDestination(title: String(localized: "offline_title"), detail: library.totalSize + " · " + String(localized: "offline_on_device"), symbol: "arrow.down.circle", route: .offlineDownloads)
                    Divider()
                    LibraryDestination(title: String(localized: "stream_server_queue"), detail: String(localized: "stream_server_queue_help"), symbol: "server.rack", route: .downloadQueue)
                    Divider()
                    LibraryDestination(title: String(localized: "settings_title"), detail: String(localized: "stream_settings_help"), symbol: "slider.horizontal.3", route: .settings)
                }
            }
            .padding(.horizontal, StreamingStyle.gutter).padding(.bottom, 28)
        }
        .background(StreamingStyle.background)
        .navigationTitle(String(localized: "stream_library"))
        .navigationBarTitleDisplayMode(.large)
    }
}

#if !UI_REVIEW_PREVIEW
struct StreamingTabs<Destination: View>: View {
    @Environment(DependencyContainer.self) private var container
    @Environment(AppRouter.self) private var router
    @ViewBuilder let destination: (Route) -> Destination

    var body: some View {
        @Bindable var router = router
        TabView(selection: $router.selectedTab) {
            tab(.watch) { VideoListScreen { container.makeVideoListViewModel() } }
                .tabItem { Label(String(localized: "stream_watch"), systemImage: "play.rectangle.fill") }.tag(AppTab.watch)
            tab(.search) { SearchScreen { container.makeSearchViewModel() } }
                .tabItem { Label(String(localized: "video_list_search"), systemImage: "magnifyingglass") }.tag(AppTab.search)
            tab(.library) { StreamingLibraryView() }
                .tabItem { Label(String(localized: "stream_library"), systemImage: "rectangle.stack.fill") }.tag(AppTab.library)
            tab(.downloads) {
                OfflineDownloadsView(videoRepository: container.videoRepository, playbackSettings: container.sponsorBlockSettings)
            }
            .tabItem { Label(String(localized: "offline_title"), systemImage: "arrow.down.circle.fill") }.tag(AppTab.downloads)
        }
    }

    private func tab<Content: View>(_ tab: AppTab, @ViewBuilder content: () -> Content) -> some View {
        NavigationStack(path: Binding(get: { router.path(for: tab) }, set: { router.setPath($0, for: tab) })) {
            content().navigationDestination(for: Route.self) { route in
                destination(route).toolbar(.hidden, for: .tabBar)
            }
        }
    }
}
#endif
