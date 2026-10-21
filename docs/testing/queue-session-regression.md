# Queue session regression

Base release: `18fec2b9bc4345b6168d00cbd5f668812773252b`.

## Reproduced causes

A permission-denied Queue request was classified as an expired login solely because it returned HTTP 403. Queue then called the global unauthorized handler, which revoked the authorization and removed its saved credentials. This was reproduced with both token and cookie sessions through the production API client, repository, view model and router, using an isolated persisted test Keychain. The new repeated-entry regression failed against the base release before the fix.

Real HTTP simulator testing exposed another false-expiry path: an unsupported artwork fallback can return the server's HTML application shell with HTTP 200 while the authenticated ping still succeeds. The former image response classifier treated all successful HTML responses as login expiry. That cleared a working session as soon as Queue artwork appeared.

A separate cancellation regression demonstrated that an image fetch could outlive its last cancelled view consumer and publish a late authentication failure. The regression failed before the image-flight cancellation fix and passed afterward.

These are controlled reproductions. The user's physical server response, installed Tube Archivist version, account role and exact failing artwork URL were not captured. No claim is made that the user lacks permission. Current upstream Tube Archivist illustrates the distinction: the [Queue API](https://github.com/tubearchivist/tubearchivist/blob/develop/backend/download/views.py) and [task API](https://github.com/tubearchivist/tubearchivist/blob/develop/backend/task/views.py) restrict access to administrators, while [authenticated ping](https://github.com/tubearchivist/tubearchivist/blob/develop/backend/common/views.py) requires authentication through the [base view](https://github.com/tubearchivist/tubearchivist/blob/develop/backend/common/views_base.py).

## Behavior after the fix

- HTTP 401 still rejects the current session immediately. Ambiguous 403, redirects and successful HTML responses are confirmed using the read-only authenticated ping with the exact same authorization snapshot and origin. A rejected authenticated ping still requires sign-in; unavailable or malformed verification does not prove expiry.
- A denied action remains denied. It is never replayed after the probe, and a permission error does not remove saved credentials. Redirects are not followed and HTML is not accepted as an image or a successful API mutation.
- Revalidation uses a ten-second request timeout. Concurrent denied API/artwork requests share one ping per authorization snapshot. There is no successful-result cache that could hide later expiry. A rejected ping never recursively probes itself.
- Cancelled or superseded API requests cannot revoke a replacement connection. Optional notification requests still report genuine session expiry. Polling stops for confirmed auth/permission denial and cancellation, while transient failures retain retry behavior.
- Image fetches track their consumers. Cancelling one consumer preserves the shared fetch for other consumers. Cancelling the last consumer cancels its transport and prevents late authentication notifications. Generation checks prevent a cancelled flight from overwriting a new one.
- Missing CSRF authorization still denies mutations without incorrectly erasing a valid read session. No server permission, credential, signing or workflow change is required.

## Validation

Evidence bundles live outside the repository in `/Users/jake/Documents/Codex/2026-10-20/task-6/evidence`.

- `queue-auth-final-focused.xcresult`: **77 passed, zero failed/skipped**, covering API client, server connection, Queue view model and the new response/race matrix.
- `queue-auth-ui-final.xcresult`: **2 passed, zero failed/skipped**. Real loopback HTTP requests through normal server-owned sign-in and production repositories exercised repeated Queue/Library/Downloads navigation, pending/ignored filters, denied artwork and HTML fallback, process termination/relaunch, interruption, maintenance, confirmed expiry and logged-out relaunch.
- `queue-auth-unit-verified.xcresult`: **795 passed, zero failed/skipped**. This includes the shared-image consumer cancellation/cache test and the explicit HTML API-mutation rejection test. The prior final run also passed 794/794 before adding the last API-response guard.
- `queue-auth-release.xcresult`: unsigned generic iOS **Release / TAClient passed**, including the share extension and iOS17 deployment availability compilation. Simulator builds passed with the final unit/UI runs.

Screenshots: [session retained after relaunch](screenshots/queue-session-retained.jpg), [denied artwork remains a placeholder](screenshots/queue-session-artwork.jpg), [confirmed expiry requires sign-in](screenshots/queue-session-expired.jpg).

The fixture server binds only to `127.0.0.1:18085`, uses synthetic cookies and in-memory data, never logs headers or credentials, and denies task mutations. Simulator persistence uses the existing dedicated synthetic Keychain namespace. No owner credentials, video bytes or server data were deleted. The two passing UI tests emitted frame-dimension diagnostics during sign-in; the screenshots and assertions passed, and no layout code changed. Earlier failed fixture/harness runs and the expected failing pre-fix regressions are retained in the evidence folder; they are not counted as final passes.

## Scope and limits

The approved Liquid Glass layout, centered icon, system player/web ownership, account mode, iOS 17 deployment target, TAClient compatibility scheme and Xcode Cloud workflows are unchanged. Runtime checks use iOS 26.5 Simulator on this Mac; physical-server/device confirmation and TestFlight availability are separate from local fixture results. The prior Apple browser session required authentication, so archive success alone must not be described as TestFlight availability.
