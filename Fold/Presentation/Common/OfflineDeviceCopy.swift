import SwiftUI

/// Keep the existing iPhone/iPad wording while naming the Mac's private library.
enum OfflineDeviceCopy {
    static var downloadAction: String {
        #if targetEnvironment(macCatalyst)
        String(localized: "offline_download_action_mac")
        #else
        String(localized: "offline_download_action")
        #endif
    }
    static var onDevice: String {
        #if targetEnvironment(macCatalyst)
        String(localized: "offline_on_mac")
        #else
        String(localized: UIDevice.current.userInterfaceIdiom == .pad ? "cinema_on_this_ipad" : "offline_on_device")
        #endif
    }
    static var symbol: String {
        #if targetEnvironment(macCatalyst)
        "desktopcomputer"
        #else
        UIDevice.current.userInterfaceIdiom == .pad ? "ipad" : "iphone"
        #endif
    }
    static var emptyHelp: String {
        #if targetEnvironment(macCatalyst)
        String(localized: "offline_empty_help_mac")
        #else
        String(localized: "offline_empty_help")
        #endif
    }
}
