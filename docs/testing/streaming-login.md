# Streaming-style login

The login screen now uses the same open system background, 20-point gutter, 16-point surfaces, editorial typography and native capsule actions as the library. The server field sits directly in the page rather than inside a grouped settings card. Browser sign-in stays primary; the existing-token option remains a disclosure, and saved Downloads has a full-width destination row with a short explanation.

The token action shows a spinner and localized Connecting status. Both inputs and sign-in actions disable during verification. Empty or whitespace-only token input cannot submit. With the token option expanded, the URL keyboard's Next action moves focus to the secure token field; Go submits the existing action. Done and interactive scroll dismissal remain available. Text wraps at accessibility sizes, and controls use a rounded rectangle when capsule geometry would crowd large text.

Authentication repositories, browser navigation/cookie rules, credentials, persistence and server configuration are unchanged. New copy is translated in English and Russian. The only server change in this branch is a three-second rejection mode in the loopback test fixture.

## Validation

- Shipping Simulator build/run succeeded on iPhone 17e, iOS 26.5.
- Focused login, server connection and restoration unit run: **31 passed**.
- Existing browser sign-in/logout UI regression passed, including gateway-only rejection and blocked external redirect.
- Existing session-persistence UI regression passed across process termination, maintenance, offline recovery and genuine expiry.
- Login UI checks cover blank/enabled controls, URL → token keyboard focus, whitespace validation, loading/disabled state, error recovery, saved Downloads and returning with the address retained.
- Light and dark login flows plus both accessibility-size runs passed: six successful UI checks across focused runs on iPhone 17e and iPhone 17 Pro.
- Accessibility-size checks reach both sign-in options and saved Downloads.

The tests use isolated Keychain state and synthetic loopback data only. Initial UI harness failures were resolved by matching the native URL keyboard's case-insensitive Next/Go labels and choosing Not Now on iOS's optional Save Password sheet for the synthetic token. No test value is saved to the password store.

The installed iOS 26.5 Simulator emits a nonfatal “Invalid frame dimension” warning when the keyboard opens; the focused input/navigation checks and actual captures verify the visible behavior. Physical-device VoiceOver and older-iOS runtime checks were not performed. This branch is for review and is not merged or distributed.

[Actual Simulator screenshots](../screenshots/streaming-login/).

The implementation retains native [FocusState](https://developer.apple.com/documentation/swiftui/focusstate) and [scrollDismissesKeyboard](https://developer.apple.com/documentation/swiftui/view/scrolldismisseskeyboard(_:)) behavior.
