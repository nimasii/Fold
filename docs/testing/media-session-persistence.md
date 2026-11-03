# Persistent sign-in during media failures

Base: main `eca26f55845388e1e1abda862715ebd73f7d6cfa`. Work is isolated on `codex/preserve-fold-session`; no publication is authorized.

## Problem and behavior

The previous Queue fix verified ambiguous API and normal artwork responses, but the video resource loader, preloader, streaming proxy and private-download completion still posted global logout for resource 401/403, redirects or successful HTML responses. A valid server session could therefore be removed when an individual media URL failed. Controlled tests reproduced the old resource loader and preloader behavior while authenticated ping succeeded; the user's exact failing server response was not captured.

Every scoped resource rejection now verifies the same connection using authenticated ping before reporting expiry. This includes resource 401, because a single protected resource can reject a request without invalidating the whole session. A rejected ping still requires sign-in. An unavailable, malformed, rate-limited or failing ping does not prove expiry. The shared per-connection probe remains bounded and coalesces concurrent checks.

An unexpected successful launch-ping body also preserves the saved connection; it is treated as an unavailable server response rather than a confirmed authentication rejection.

The failed operation stays failed: redirects are stopped, HTML is not accepted as media, and denied actions are not replayed. Canceled or revoked probes cannot post a late logout. Global auth notifications must identify the currently active connection; unscoped or superseded events are ignored. Invalid local download URLs or missing local transfer credentials only affect that transfer. Download verification is canceled with its attempt and cannot invalidate a replacement connection.

## Persistence limits and supported options

Fold keeps the existing device-only Keychain connection until explicit disconnect, replacement or confirmed server rejection. This change does not retain passwords, create tokens, change server settings, extend cookie expiry, or automatically select Remember me.

The sign-in browser displays Tube Archivist's ordinary login page. Its Remember me checkbox is available, defaults off on a fresh page, and is chosen before Login and Finish. Tube Archivist v0.6.0 grants two-day sessions by default and 365-day sessions when selected. Fold now makes the option clearer in its browser guidance. The temporary browser store is discarded after Finish; the captured cookies and their original expiration are saved in Keychain. There is no supported session-renewal endpoint or client promise of an eternal session.

For a direct server connection, the existing **Use an existing API token** option avoids browser-cookie expiry. Fold imposes no timer on that saved token, but the server can revoke it or remove access. Gateway authentication may still require browser sign-in. No owner token was accessed or configured: the server's GET token endpoint uses get_or_create and must not be called merely to inspect whether a token exists.

Sources: [server login lifetime](https://github.com/tubearchivist/tubearchivist/blob/v0.6.0/backend/user/views.py), [Remember me UI](https://github.com/tubearchivist/tubearchivist/blob/v0.6.0/frontend/src/pages/Login.tsx), [token authentication](https://github.com/tubearchivist/tubearchivist/blob/v0.6.0/backend/common/views_base.py), [token endpoint](https://github.com/tubearchivist/tubearchivist/blob/v0.6.0/backend/appsettings/views.py).

## Validation

- `session-full-unit-verified.xcresult`: **854 unit tests in 81 suites passed, zero failures**, including the new media/session matrix, startup and account-confirmation cases, Queue, offline download, proxy, cache and existing playback checks. Evidence is in `/Users/jake/Documents/Codex/2026-11-03/task-2/evidence`.
- `session-relaunch-verified.xcresult`: **1 real HTTP UI test passed, zero failures/skips**. A dedicated synthetic Keychain service survived process termination/relaunch, HTML 503 maintenance and network disconnection, then recovered without another login. Explicit server expiry required sign-in, and a subsequent launch did not restore the rejected connection. Six screenshots are retained; connected, maintenance/Downloads and expiry states were visually checked.
- `session-release.xcresult`: **unsigned generic iOS Release / TAClient build passed**, including the share extension and existing iOS 17 deployment target.
- `git diff --check` passed. No server setting, owner credential, workflow, signing configuration, player engine or archived media was changed.

The original broad run identified an outdated expiry fixture that returned a valid authenticated ping while expecting a resource 401 to wipe credentials. The fixture now rejects ping for its genuine-expiry branch and continues asserting that denied access is never replaced by cached success. A preloader cancellation fixture now requires cached bytes before comparing orphan-reseed offsets, preventing legitimate empty-cache cleanup from racing its assertion. Both corrected checks pass in the final full suite. The first UI attempt was intercepted by the floating keyboard toolbar; the relaunch test now submits the address through its normal Go action. The successful run emitted the existing sign-in frame-dimension diagnostic, with its assertions and captured states intact. Initial compile/discovery attempts and superseded failures are excluded from the passing count.

Tests use synthetic credentials, isolated storage, mocked upstream responses and the proxy's loopback listener. Owner credentials and server data are outside these tests. The media notification helper is app-only; the shared authorization snapshot remains usable by the share extension without depending on app logout notifications.
