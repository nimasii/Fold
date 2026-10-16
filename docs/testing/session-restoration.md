# Session restoration and upstream player investigation

The session fix was developed on `codex/native-player-session-restore`, based on main merge `18285ebfd094cfbf5c5b0efff486e7855be20f38`, and is included in `codex/apple-compatible-downloads`.

## Session behavior

- Saved cookie sessions and existing tokens continue using the same device-only Keychain service and access group. No lifetime is extended and no token is created.
- Startup network failures, maintenance, rate limits and server errors preserve the connection and enter the main screen, where retry and private downloads are available. Previously network failure returned to connection setup, and HTML 5xx responses were treated as authentication failures and wiped credentials.
- HTML login pages returned with a successful status, redirects and 401/403 still require normal sign-in. Explicit logout still revokes snapshots and removes saved credentials.
- Session mutations now serialize HTTP `Origin` like a browser: default ports are omitted. The internal exact-origin comparison still normalizes ports. Previously a normal HTTPS server could receive `Origin: https://host:443` while Django compared against `https://host`, causing a CSRF 403 and sign-out when progress was saved. This is a confirmed source defect; whether it explains Jake's exact deployment still needs normal owner-flow validation.
- A launch ping/account request from an earlier connection cannot invalidate a replacement connection. Navigating into private downloads also prevents the launch check from replacing navigation.

Server-owned session expiry remains authoritative. Tube Archivist's public login implementation currently issues two-day sessions, or one year when the owner chooses its Remember me option. The client does not select that option for the owner, keep passwords, change server settings, or silently exchange sessions for tokens.

## Verification

`SessionRestorationTests` covers restoration, network error variants, expiry/relogin, navigation, server replacement, account-auth failures, maintenance response classification and HTTP Origin variants. Existing auth/transport/offline tests remain relevant.

`SessionPersistenceUITests.testSessionRelaunch` runs against the local `connection_server.py` fixture using real Simulator Keychain persistence under a distinct synthetic service. It connects through the visible server-owned login, terminates and launches the app, repeats during HTML 503 maintenance and network disconnect, recovers without a new login, and then receives a genuine 403 and verifies saved authentication is removed. Six screenshots are retained in the test result. The fixture-only Keychain initializer is absent from device/release builds. Simulator signing is required for this test (`CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=-`). Owner secrets are never read.

## Player investigation and chosen integration

Inspected the fork parent `MikhailZhukov/TAClient` main at `4c69cdaab4f1bd5890960619b2c56ee2ad7135dd` before editing playback. Its `AVPlayerView` wrapper is byte-for-byte identical to this fork's wrapper (SHA-256 `4cb856c7edc0df649e3d47684cf74fd17ece7fc670e4784a2921d322823a79d6`). It uses native `AVPlayerViewController` controls, PiP and fullscreen.

Upstream also selects `VLCPlayerView` with custom controls for VP8/VP9. The prior merged offline implementation now shares both of those actual production controllers. The only codec selection addition since upstream is conservative VLC fallback for a legacy WebM file with missing stream metadata.

The owner subsequently chose native Apple playback for new private downloads, with local preparation when needed. The implemented path validates compatible MP4 inputs unchanged and converts supported incompatible inputs into a separately stored H.264/AAC copy. See [Apple-compatible private downloads](apple-compatible-downloads.md) for implementation and evidence. Streaming and existing downloads retain their supported codec-aware behavior; native controls are the original production controller. No server download-format setting or archived original is changed.

Sources: [original public source](https://github.com/MikhailZhukov/TAClient/tree/4c69cdaab4f1bd5890960619b2c56ee2ad7135dd), [Tube Archivist login lifetime](https://github.com/tubearchivist/tubearchivist/blob/master/backend/user/views.py), [Django CSRF Origin validation](https://docs.djangoproject.com/en/5.2/ref/csrf/).
