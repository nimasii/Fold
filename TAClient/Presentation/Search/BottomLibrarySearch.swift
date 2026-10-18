import SwiftUI
import UIKit

/// A bottom search launcher keeps Library search inside the three-section shell.
struct BottomLibrarySearch: View {
    @Environment(AppRouter.self) private var router
    var body: some View {
        Button { router.beginLibrarySearch() } label: {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                Text(String(localized: "nav_search_library"))
                Spacer(minLength: 0)
            }
            .font(.body).foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, minHeight: 44).contentShape(Rectangle())
        }
        .buttonStyle(.plain).padding(.horizontal, 16).padding(.vertical, 2)
        .accessibilityLabel(String(localized: "nav_search_library"))
        .accessibilityIdentifier("library.search.open")
    }
}

/// Editing is anchored to the Library's keyboard-aware safe area. Tab accessories
/// are hidden with the tab bar by iOS when the keyboard appears.
struct LibrarySearchEditor: View {
    @Environment(AppRouter.self) private var router
    var body: some View {
        @Bindable var router = router
        LibrarySearchBar(query: $router.librarySearchQuery, wantsFocus: $router.librarySearchWantsFocus,
            onBegin: router.beginLibrarySearch, onCancel: router.cancelLibrarySearch)
            .background(.bar)
    }
}

private struct LibrarySearchBar: UIViewRepresentable {
    @Binding var query: String
    @Binding var wantsFocus: Bool
    let onBegin: () -> Void
    let onCancel: () -> Void
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIView(context: Context) -> SearchContainer {
        let container = SearchContainer()
        let bar = container.bar
        bar.delegate = context.coordinator
        bar.searchBarStyle = .minimal
        bar.backgroundImage = UIImage()
        bar.searchTextField.backgroundColor = .clear
        bar.placeholder = String(localized: "nav_search_library")
        bar.searchTextField.accessibilityLabel = String(localized: "nav_search_library")
        bar.searchTextField.accessibilityIdentifier = "library.search"
        bar.searchTextField.font = .preferredFont(forTextStyle: .body)
        bar.searchTextField.adjustsFontForContentSizeCategory = true
        bar.autocapitalizationType = .none; bar.autocorrectionType = .no
        bar.returnKeyType = .search; bar.showsCancelButton = false
        container.cancel.setTitle(String(localized: "cancel"), for: .normal)
        container.cancel.accessibilityLabel = String(localized: "cancel")
        container.cancel.accessibilityIdentifier = "library.search.cancel"
        container.cancel.addAction(UIAction { [weak coordinator = context.coordinator, weak bar] _ in
            coordinator?.parent.wantsFocus = false
            bar?.resignFirstResponder()
            coordinator?.parent.onCancel()
        }, for: .primaryActionTriggered)
        return container
    }
    func updateUIView(_ container: SearchContainer, context: Context) {
        let bar = container.bar
        context.coordinator.parent = self
        if bar.text != query { bar.text = query }
        bar.wantsFocus = wantsFocus
        bar.requestFocusIfAttached()
    }
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: SearchContainer, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? 320, height: max(48, UIFont.preferredFont(forTextStyle: .body).lineHeight + 16))
    }
    final class Coordinator: NSObject, UISearchBarDelegate {
        var parent: LibrarySearchBar
        init(_ parent: LibrarySearchBar) { self.parent = parent }
        func searchBarTextDidBeginEditing(_ searchBar: UISearchBar) { parent.onBegin() }
        func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) { parent.query = searchText }
        func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
            parent.wantsFocus = false; searchBar.resignFirstResponder()
        }
        func searchBarCancelButtonClicked(_ searchBar: UISearchBar) {
            parent.wantsFocus = false; searchBar.resignFirstResponder(); parent.onCancel()
        }
    }
    /// UISearchBar disables its built-in Cancel when editing ends. This public
    /// sibling button remains available after Return or returning from a video.
    final class SearchContainer: UIView {
        let bar = AttachedSearchBar()
        let cancel = UIButton(type: .system)
        override init(frame: CGRect) {
            super.init(frame: frame)
            cancel.titleLabel?.font = .preferredFont(forTextStyle: .body)
            cancel.titleLabel?.adjustsFontForContentSizeCategory = true
            cancel.setContentHuggingPriority(.required, for: .horizontal)
            cancel.setContentCompressionResistancePriority(.required, for: .horizontal)
            let stack = UIStackView(arrangedSubviews: [bar, cancel])
            stack.axis = .horizontal; stack.spacing = 4; stack.alignment = .center
            stack.translatesAutoresizingMaskIntoConstraints = false
            addSubview(stack)
            NSLayoutConstraint.activate([
                stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
                stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
                stack.topAnchor.constraint(equalTo: topAnchor), stack.bottomAnchor.constraint(equalTo: bottomAnchor),
                cancel.heightAnchor.constraint(greaterThanOrEqualToConstant: 44),
                cancel.widthAnchor.constraint(greaterThanOrEqualToConstant: 44)
            ])
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    }
    final class AttachedSearchBar: UISearchBar {
        var wantsFocus = false
        override func didMoveToWindow() { super.didMoveToWindow(); requestFocusIfAttached() }
        func requestFocusIfAttached() {
            guard window != nil, wantsFocus, !searchTextField.isFirstResponder else { return }
            DispatchQueue.main.async { [weak self] in
                guard let self, self.window != nil, self.wantsFocus, !self.searchTextField.isFirstResponder else { return }
                self.becomeFirstResponder()
            }
        }
    }
}
