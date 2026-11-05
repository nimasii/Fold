# Mac VLC sources and rebuilding

Fold's source is available under Apache-2.0 in this repository. The Mac build
links SwiftVLC 1.0.0 and its libVLC static archive. SwiftVLC is MIT licensed;
libVLC is LGPL-2.1-or-later. The application includes both license texts in
About → Licenses. Modification and debugging of the LGPL components is allowed.

Exact dependency inputs for this version:

- SwiftVLC commit `192393a45cdcd7ebb6befac26586360b8b1676b3` (`v1.0.0`):
  <https://github.com/harflabs/SwiftVLC/tree/192393a45cdcd7ebb6befac26586360b8b1676b3>
- The binary archive URL/checksum is pinned in that commit's `Package.swift`:
  `https://github.com/harflabs/SwiftVLC/releases/download/v1.0.0/libvlc.xcframework.zip`
  SHA-256 `23509b945aafb97634d2e66af24a377d7bd50b672aba8f5dec1d6f9ef8614045`.
- libVLC comes from VideoLAN's VLC repository at `c833c4be0`, with the source
  adjustments and patches in the pinned SwiftVLC `scripts` directory:
  <https://code.videolan.org/videolan/vlc/-/tree/c833c4be0>
  <https://github.com/harflabs/SwiftVLC/tree/192393a45cdcd7ebb6befac26586360b8b1676b3/scripts>
- The source build script fetches the pinned VLC and contrib sources. Its
  prerequisite list and configure steps are in `scripts/build-libvlc.sh`.

To rebuild Fold with a modified library:

1. Clone Fold and the pinned SwiftVLC source above. Install the prerequisites
   listed by SwiftVLC (including Xcode/Swift 6.3+, autoconf, automake and libtool).
2. In the SwiftVLC checkout, run `./scripts/build-libvlc.sh --catalyst-only`.
   Apply your library changes in that source build as desired; use the script's
   documented `--hash` / patch options for different VLC sources. Preserve the
   Catalyst arm64/x86_64 slice in `Vendor/libvlc.xcframework`.
3. In that checkout's `Package.swift`, replace only the `libvlc` binary target's
   URL/checksum declaration with:
   ```swift
   .binaryTarget(name: "libvlc", path: "Vendor/libvlc.xcframework")
   ```
4. In Fold's Xcode project, replace the remote SwiftVLC package reference with a
   local package reference to your SwiftVLC checkout. Keep product `SwiftVLC`
   linked only for Mac Catalyst. The iOS MobileVLCKit dependency is independent.
5. Build the Fold scheme for My Mac (Mac Catalyst), using your own development
   signing team/bundle identifier. `scripts/build-mac.sh` runs the Release build.

All Fold source needed to recompile/relink the Mac app is supplied in this
repository. No private Fold framework or proprietary object file is required.
The unmodified prebuilt dependency was used for the released app; the full VLC
source rebuild procedure above is provided for modification and has not been
independently rerun as part of Fold's application-level validation.
