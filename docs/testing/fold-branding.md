# Fold branding validation

The app/project/primary scheme and GitHub repository are renamed to Fold. The layered `Fold/Fold.icon` is the selected folded white play ribbon with red bookmark accent, recreated as four editable SVG layers and rendered with native Icon Composer material. Actual native exports and the Composer window capture are in `docs/branding/Fold` and `docs/screenshots/fold`.

Validation before publication:

- Canonical `Fold.xcodeproj` / `Fold` Simulator build and launch passed on iPhone 17e, iOS 26.5.
- Existing `TAClient.xcodeproj` compatibility path / `TAClient` scheme build passed, so the current automatic Xcode Cloud entry remains usable during migration.
- 18 focused login/auth/restoration unit tests passed, plus 239 serialized data tests including server-session authorization and offline-library persistence.
- Browser sign-in/logout, session restoration, large-text login and standard login/loading/error/offline navigation UI checks passed across focused runs.
- The standard UI test initially hit iOS 26.5's offscreen accessibility frame for the system Next key. Sending normal Return input verifies the same focus handoff and submission without relying on the system key's invalid hit-test frame; the final focused run passed.
- Native Default and Dark exports were visually inspected. Installed light/dark Home Screen captures verify the new icon and Fold display label.

Bundle IDs, development team, signing identities/profiles, app entitlements, Keychain service names, notification identifiers and offline-view implementation were compared against the previous main and remain unchanged. No owner credentials or downloaded media were read. The original untracked local Cloud manifest was preserved byte-for-byte and excluded from the commit.

The existing `AuthProxy.swift:245` weak-capture warning remains. No physical-device or older-runtime test was performed; the native icon compiler generates compatibility icons for the app's existing iOS 17 minimum.
