# Full-screen playback orientation

Entering full screen requests landscape in both the native AVKit player and VLC.
The request uses the player's own UIWindowScene and the public
`requestGeometryUpdate` API. Each presentation saves the current interface
orientation and restores it after dismissal; subsequent presentations capture it
afresh. Normal inline rotation remains controlled by UIKit. AVKit cancellation
keeps the full-screen ownership and playback-exit guards consistent with the
actual completed transition. iPad windowed scenes can decline geometry requests.

`FullscreenOrientationUITests` uses the existing Debug Simulator playback fixture
and the shipping player implementations. It leaves the simulated device portrait,
then asserts a landscape application frame on entry and portrait on exit twice
for each engine. Screenshots are retained in the result bundle.

Reproduce from the repository root:

```sh
python3 Tests/Fixtures/playback_parity_server.py
xcodebuild test -project Fold.xcodeproj -scheme ConnectionFlow \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:FoldUITests/FullscreenOrientationUITests
xcodebuild test -project Fold.xcodeproj -scheme Fold \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

The fixture serves synthetic clips on loopback port 18083; it uses no owner
credentials or archive. Physical-device orientation lock, PiP, external displays,
and iPad multitasking require separate device checks.

Verified with Xcode 27.0 on iPhone 17 Pro Simulator, iOS 26.5: both orientation
UI tests passed (two entry/exit cycles per engine), and all 38 focused playback,
end-state, local-parity and preload-retry tests passed. The broader unit run
reported 853 passed and one preload-cancellation timeout during severe host load;
that exact test passed on an isolated retry in 1.67 seconds. The AVKit delegate
is retained through the full-screen lifetime because rotation can rebuild its
inline SwiftUI host before the dismissal callback arrives.
