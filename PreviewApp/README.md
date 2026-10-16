# UI review preview

`UIReviewPreview` is a simulator-only companion target for reviewing the redesigned screens with synthetic data. It reuses the production SwiftUI screens and navigation while injecting in-memory repositories and a fresh, isolated preferences suite. It does not load saved credentials, contact a server, or write to the production archive.

The preview replaces remote artwork with local placeholders and replaces the player area with an explicit preview card. Playback and the MobileVLCKit package are not part of this target; the production target and player code remain unchanged.

Open `UIReviewPreview.xcodeproj`, select the `UIReviewPreview` scheme, and run it in an iOS Simulator. The scheme supports iOS Simulator only and disables code signing. Use the `Preview appearance` control in the navigation bar to review System, Light, and Dark appearance.

The simulator captures in `review-artifacts/runtime-screenshots/` document the library, detail, settings, playlists, download queue, and empty download states.

## Connection and search review

Pass `--review-screen=login` or `--review-screen=search` to open the production connection or search view directly. Add `--review-dark` for dark appearance. The preview footer is capped at the standard large text size so it does not cover the product when testing accessibility text sizes; production controls retain the full Dynamic Type range.

`TAClientUITests/ModernInterfaceUITests` launches this companion app to verify enabled/disabled connection actions, the existing-token disclosure, search results/clearing/empty states, both appearances, and the largest accessibility text size. Build and install `UIReviewPreview` on the same simulator before running these tests through the `ConnectionFlow` scheme. All archive data is synthetic and remote artwork is replaced by placeholders.

Reviewed sign-in and search captures are in `docs/screenshots/connection-search/`. The screenshots show real production SwiftUI views in this isolated preview target.
