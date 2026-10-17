#if DEBUG && targetEnvironment(simulator) && !UI_REVIEW_PREVIEW
import SwiftUI

/// Actual shipping screens and media services with isolated, clearly labeled test data.
struct StreamingFixtureRoot: View {
    @Environment(DependencyContainer.self) private var container
    @Environment(\.dynamicTypeSize) private var systemTypeSize
    private let arguments = ProcessInfo.processInfo.arguments
    var body: some View {
        VStack(spacing: 0) {
            Text(String(localized: "stream_fixture")).font(.caption2.weight(.semibold))
                .dynamicTypeSize(...DynamicTypeSize.large)
                .foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(.vertical, 4)
                .accessibilityIdentifier("streaming.fixture-label")
            RootView()
        }
            .preferredColorScheme(arguments.contains("--streaming-fixture-dark") ? .dark : arguments.contains("--streaming-fixture-light") ? .light : nil)
            .dynamicTypeSize(arguments.contains("--streaming-fixture-accessibility") ? .accessibility3 : systemTypeSize)
            .task {
                guard !arguments.contains("--streaming-fixture-login"), container.offlineLibrary.records.isEmpty,
                      let fixture = container.videoRepository as? StreamingFixtureRepository,
                      fixture.videos.count > 1 else { return }
                container.offlineLibrary.enqueue(fixture.videos[1])
            }
    }
}
#endif
