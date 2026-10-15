# Server-owned connection setup

TAClient opens the configured Tube Archivist URL in an ephemeral WKWebView. Sign in on the server's page, then choose **Finish**. The browser supports the same-host Umbrel port-2000 handoff used by MurmurNative. HTTP(S) navigation stays on the exact hostname and the configured/standard Umbrel ports; HTTPS connections cannot downgrade to HTTP. External navigation, popups and external response redirects are rejected.

Umbrel login and Tube Archivist authentication are separate layers. Tube Archivist documents session and token authentication; its API base class uses Django `SessionAuthentication` before `TokenAuthentication`. The standard Umbrel package currently sets `PROXY_AUTH_ADD: "false"` and configures Tube Archivist's own username/password. Consequently, a successful Umbrel gateway login alone is not proof of API access. Tube Archivist can still present its own server-owned login page. No server configuration is changed by this client.

**Finish** performs only authenticated `GET /api/ping/`, requiring a decoded `pong` response with a user. Only a validated session replaces the saved connection. The new flow never calls the token endpoint: upstream `GET /api/appsettings/token/` uses `get_or_create`, which can create a persistent credential. The older native username/password repository API remains source compatible, but is no longer offered by connection setup.

If a server cannot supply a usable application session, **Use an existing API token** accepts an owner-provided existing token and validates it with the same ping. It never creates, resets or revokes that token. A gateway-protected server should use server sign-in, completing Tube Archivist login there if required. Sessions use the standard `sessionid`/`csrftoken` cookies; custom Django CSRF cookie names are not inferred.

## Transport and storage

- API calls, thumbnails, lock-screen artwork, cache HEAD/range requests, VLC/AirPlay's local proxy and the share extension use the same scoped authorization implementation. Native URLSession cookie jars are disabled. Cookies are filtered by exact host, path, Secure flag and expiry, then attached only to the configured origin, including its port. Tokens have the same origin boundary. Range headers are preserved.
- Session mutations carry `X-CSRFToken`, Origin and Referer. Native redirects are stopped before forwarding any credential. 401, 403, redirects or HTML sign-in responses require a new sign-in. As in the previous client, a 403 permission rejection also requires sign-in.
- New connection records contain the origin and either cookies or an explicitly supplied existing token together in a single Keychain entry. Keychain updates preserve the prior entry if an update fails. Cookies are device-only and available after first unlock. Failed candidate validation does not replace a working connection. Session cookies are never widened to sibling hosts or other ports in native requests.
- Existing token/server keys remain readable and do not automatically become session connections. The keychain service/account names remain unchanged. The app and share extension now derive their access group from the fork's existing entitlements instead of the original author's hardcoded team. Credentials belonging to another signing team/access group remain inaccessible and require normal sign-in; the app does not request broader entitlements.
- Logout/unauthorized responses revoke retained authorization snapshots, clear saved credentials, and discard media/image caches through the router. An expired session retains its non-secret server address in memory for relogin. Browser state is ephemeral and removed when the sheet closes. Logout is local to TAClient; it does not reset API tokens or sign other Umbrel clients out.

## Verification

Run the unit suite in a deterministic timezone:

```sh
xcodebuild test -scheme TAClient -destination 'platform=iOS Simulator,id=918C7545-A4A2-4A2C-9FE9-0499B4E0F1E1' CODE_SIGNING_ALLOWED=NO TEST_RUNNER_TZ=UTC
```

`ServerConnectionTests` covers origin/host/path/Secure/expiry boundaries, CSRF, browser handoffs, session validation without token retrieval, rejected gateway-only authentication, persisted session and legacy token modes, revocation, expiry/relogin, and authenticated HEAD/range preload requests. A generated two-second H.264 fixture additionally verifies that AVPlayer becomes playable, advances playback, and seeks through the authenticated caching resource loader. Existing transport/cache/player suites also run.

For the browser UI fixture, run `python3 Tests/Fixtures/connection_server.py`, then:

```sh
xcodebuild test -scheme ConnectionFlow -only-testing:TAClientUITests/ServerConnectionUITests -destination 'platform=iOS Simulator,id=918C7545-A4A2-4A2C-9FE9-0499B4E0F1E1' CODE_SIGNING_ALLOWED=NO
```

The fixture binds only loopback ports 18079 and 2000. It uses dummy cookies, exercises Umbrel's handoff followed by application login, rejects gateway-only access, blocks an external-host navigation, connects and confirms logout. Screenshots are attached to the result bundle. `--connection-fixture` is Debug-only isolation: it prevents reading saved credentials and keeps fixture credentials in memory. The HTTP UI fixture does not implement media playback; the separate unit fixture verifies AVPlayer locally. Owner-server playback, a signed device's Keychain/extension behavior, and live sign-in still require normal user validation. No owner credential is read by these tests.

Sources checked October 15, 2026:

- [Tube Archivist API authentication](https://docs.tubearchivist.com/api/introduction/)
- [API authentication order](https://github.com/tubearchivist/tubearchivist/blob/master/backend/common/views_base.py)
- [Login session API](https://github.com/tubearchivist/tubearchivist/blob/master/backend/user/views.py)
- [Token endpoint behavior](https://github.com/tubearchivist/tubearchivist/blob/master/backend/appsettings/views.py)
- [Standard Umbrel package](https://github.com/getumbrel/umbrel-apps/blob/master/tubearchivist/docker-compose.yml)

These upstream sources establish supported behavior; the owner's private deployment settings were not read or changed.
