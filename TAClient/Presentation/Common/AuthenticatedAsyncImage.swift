import SwiftUI

struct AuthenticatedAsyncImage: View {
    let url: String?
    var placeholderColor: Color = Color(.secondarySystemBackground)
    var localFileURL: URL? = nil
    var localRevision = 0
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
                    #if UI_REVIEW_PREVIEW
                    .overlay { Image(systemName: "photo").font(.caption).foregroundStyle(.tertiary).accessibilityHidden(true) }
                    #endif
            }
        }
        .onAppear {
            loadIfNeeded()
        }
        .onChange(of: url) {
            image = nil
            loadIfNeeded()
        }
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
            image = UIImage(contentsOfFile: localFileURL.path)
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
        guard image == nil,
              let urlString = url,
              !urlString.isEmpty,
              let imageURL = URL(string: urlString) else { return }

        loadTask?.cancel()
        loadTask = Task {
            let loaded = await ImageCache.shared.image(for: imageURL, token: authState.token, authorization: authState.authorization)
            if !Task.isCancelled {
                self.image = loaded
            }
        }
        #endif
    }
}
