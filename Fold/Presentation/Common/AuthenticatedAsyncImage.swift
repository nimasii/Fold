import SwiftUI

struct AuthenticatedAsyncImage: View {
    let url: String?
    var placeholderColor: Color = Color(.secondarySystemBackground)
    var localFileURL: URL? = nil
    var localRevision = 0
    var serverVideoID: String? = nil
    @Environment(AuthState.self) private var authState
    @State private var image: UIImage?
    @State private var loadTask: Task<Void, Never>?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                placeholderColor
                    .overlay { Image(systemName: "photo").font(.caption).foregroundStyle(.tertiary).accessibilityHidden(true) }
            }
        }
        // Cropping does not clip SwiftUI hit testing. A scaled portrait bitmap
        // can extend beyond its poster and intercept neighboring controls.
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear {
            loadIfNeeded()
        }
        .onChange(of: url) {
            image = nil
            loadIfNeeded()
        }
        .onChange(of: authState.authorization?.id) { image = nil; loadIfNeeded() }
        .onChange(of: localFileURL) { image = nil; loadIfNeeded() }
        .onChange(of: localRevision) { image = nil; loadIfNeeded() }
        .onDisappear {
            loadTask?.cancel()
        }
    }

    private func loadIfNeeded() {
        if let localFileURL {
            loadTask?.cancel()
            guard localFileURL.isFileURL else { return }
            loadTask = Task {
                let loaded = await Task.detached(priority: .utility) { ArtworkDecoder.image(at: localFileURL) }.value
                guard !Task.isCancelled else { return }
                image = loaded
            }
            return
        }
        #if UI_REVIEW_PREVIEW
        if let url, url.hasPrefix("preview://") {
            let resource = url.contains("/channel/") ? "offline-channel" : "offline-thumbnail"
            if let file = Bundle.main.url(forResource: resource, withExtension: "png")
                ?? Bundle.main.url(forResource: resource, withExtension: "png", subdirectory: "Fixtures") {
                image = UIImage(contentsOfFile: file.path)
            }
        }
        #else
        guard image == nil else { return }
        var candidates = [url].compactMap { $0 }.filter { !$0.isEmpty }
        if let serverVideoID, let base = authState.serverURL {
            candidates += ServerArtwork.videoFallbacks(serverVideoID, baseURL: base)
        }
        guard !candidates.isEmpty else { return }
        loadTask?.cancel()
        let authorization = authState.authorization
        let token = authState.token
        loadTask = Task {
            var attempted = Set<String>()
            for candidate in candidates where attempted.insert(candidate).inserted {
                guard !Task.isCancelled, let imageURL = URL(string: candidate) else { return }
                let loaded = await ImageCache.shared.image(for: imageURL, token: token, authorization: authorization)
                guard !Task.isCancelled, authState.authorization?.id == authorization?.id else { return }
                if let loaded { image = loaded; return }
            }
        }
        #endif
    }
}
