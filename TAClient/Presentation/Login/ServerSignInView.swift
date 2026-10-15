import SwiftUI
import WebKit
import Combine

struct ServerSignInDestination: Identifiable { let id = UUID(); let url: URL }

@MainActor final class ServerSignInBrowser: NSObject, ObservableObject, WKNavigationDelegate {
    let url: URL
    let webView: WKWebView
    @Published var blocked = false
    init(url: URL) {
        self.url = url
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        webView = WKWebView(frame: .zero, configuration: config)
        super.init()
        webView.navigationDelegate = self
    }
    nonisolated static func allows(_ target: URL, for server: URL) -> Bool {
        let ports = Set([server.port ?? (server.scheme == "https" ? 443 : 80), 2000, 443, 80])
        return ["http", "https"].contains(target.scheme) && target.host?.lowercased() == server.host?.lowercased() &&
            target.user == nil && target.password == nil && ports.contains(target.port ?? (target.scheme == "https" ? 443 : 80)) &&
            !(server.scheme == "https" && target.scheme == "http")
    }
    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let target = action.request.url, Self.allows(target, for: url), action.targetFrame != nil else {
            blocked = true; decisionHandler(.cancel); return
        }
        decisionHandler(.allow)
    }
    func webView(_ webView: WKWebView, decidePolicyFor response: WKNavigationResponse,
                 decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        guard let target = response.response.url, Self.allows(target, for: url) else {
            blocked = true; decisionHandler(.cancel); return
        }
        decisionHandler(.allow)
    }
    func cookies() async -> [HTTPCookie] { await webView.configuration.websiteDataStore.httpCookieStore.allCookies() }
    func clear() async {
        webView.stopLoading()
        await webView.configuration.websiteDataStore.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast)
    }
}

private struct ServerBrowserSurface: UIViewRepresentable {
    let browser: ServerSignInBrowser
    func makeUIView(context: Context) -> WKWebView { browser.webView }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}

struct ServerSignInView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var browser: ServerSignInBrowser
    @Bindable var viewModel: LoginViewModel
    init(url: URL, viewModel: LoginViewModel) {
        _browser = StateObject(wrappedValue: ServerSignInBrowser(url: url))
        self.viewModel = viewModel
    }
    var body: some View {
        NavigationStack {
            VStack(spacing: 8) {
                Text(String(localized: "login_server_explanation")).font(.footnote).foregroundStyle(.secondary).padding(.horizontal)
                Text(browser.url.host ?? "").font(.caption.monospaced())
                if browser.blocked { Text(String(localized: "login_redirect_blocked")).font(.caption).foregroundStyle(.red) }
                if let error = viewModel.errorMessage { Text(error).font(.caption).foregroundStyle(.red).padding(.horizontal) }
                ServerBrowserSurface(browser: browser)
            }
            .navigationTitle(String(localized: "login_server_title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "login_cancel")) { dismiss() }
                        .accessibilityLabel(String(localized: "login_cancel"))
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "login_finish")) {
                        Task {
                            let cookies = await browser.cookies()
                            if await viewModel.completeServerSignIn(url: browser.url, cookies: cookies) { dismiss() }
                        }
                    }.disabled(viewModel.isLoading)
                        .accessibilityLabel(String(localized: "login_finish"))
                }
            }
            .task { browser.webView.load(URLRequest(url: browser.url)) }
            .onDisappear { Task { await browser.clear() } }
        }
    }
}
