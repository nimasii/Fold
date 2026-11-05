import UIKit
import OSLog

/// One full-screen presentation, scoped to the player's window (including on iPad).
/// Request geometry after presentation/dismissal so the visible controller owns
/// orientation negotiation. No device-orientation mutation or global app lock.
@MainActor
final class FullscreenOrientationSession {
    private weak var scene: UIWindowScene?
    private var originalOrientation: UIInterfaceOrientation?

    func capture(in scene: UIWindowScene?) {
        guard originalOrientation == nil, let scene else { return }
        self.scene = scene
        originalOrientation = scene.interfaceOrientation
    }

    func enterLandscape() {
        request(.landscape)
    }

    func restore() {
        if let originalOrientation {
            request(Self.mask(for: originalOrientation))
        }
        originalOrientation = nil
        scene = nil
    }

    static func mask(for orientation: UIInterfaceOrientation) -> UIInterfaceOrientationMask {
        switch orientation {
        case .portrait: .portrait
        case .portraitUpsideDown: .portraitUpsideDown
        case .landscapeLeft: .landscapeLeft
        case .landscapeRight: .landscapeRight
        default: .allButUpsideDown
        }
    }

    private func request(_ orientations: UIInterfaceOrientationMask) {
        #if !targetEnvironment(macCatalyst)
        guard let scene else { return }
        // Transition completions can run before UIKit removes the dismissed
        // controller from the presentation chain. Negotiate on the next main
        // turn, when the visible controller supplies its orientation mask.
        DispatchQueue.main.async {
            scene.windows.forEach { $0.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations() }
            // Windowed iPad scenes may decline rotation; leave geometry to UIKit.
            scene.requestGeometryUpdate(.iOS(interfaceOrientations: orientations)) { error in
                Logger(subsystem: "com.jacobcampbell.ta-client", category: "PlayerOrientation")
                    .error("Player orientation request declined: \(error.localizedDescription, privacy: .public)")
            }
        }
        #endif
    }
}
