# Private offline downloads

The video detail screen offers **Download to iPhone**. **Downloads**, available from the More menu and the connection screen, contains only copies saved on this device. The previous Pending/Ignored screen is labeled **Server queue** and keeps its existing server behavior.

Downloads use the same AdaptiveVideoGrid and VideoCardView as the normal video list: adaptive columns, thumbnail, quality/date/duration badges, title and channel. File size is a small secondary label; local removal and refreshing details/artwork live in the context menu. Transfer progress/cancel/retry remains visible below the saved videos, while storage/privacy/foreground-download details are in the Info button.

Completed copies survive relaunch, loss of network access, session expiry and logout. Removing a copy requires confirmation and deletes only TAClient's local media, artwork and metadata; it never deletes the archived server video. Tapping a copy pushes the shared inline VideoPlayerSurface and VideoDetailLayout, with the same AVKit/VLC controls, fullscreen/PiP behavior, pinning and VideoInfoSection used by server videos. AVPlayer's existing NowPlayingController also handles local playback/remote controls using local artwork. Offline position is saved locally without writing watched/progress state to the server.

## Storage and authentication

- Media, private Artwork and an atomic versioned manifest live under Application Support/OfflineDownloads-v1. Media, artwork, staging, directories and manifest are excluded from backups and request complete-until-first-authentication file protection. Simulator does not consistently expose the device-only protection attribute; backup exclusion is verified there. Filenames use generated UUIDs and closed extension/artwork-kind enums.
- No Photos, Files, share/export action or file-sharing entitlement is added. Uninstalling TAClient removes its sandbox. Logout deliberately retains downloaded copies so they remain available offline; remove them from Downloads when desired.
- The manifest stores title/channel, source origin and an unsigned media path, size, codec and transfer/playback state. It never stores credentials, cookies, token-bearing query strings or URLSession resume data. Current connection credentials remain in the existing Keychain implementation.
- A transfer uses the current scoped RequestAuthorization, including the existing exact-origin and cookie path/Secure/expiry rules. URLSession uses ephemeral configuration, no shared cookie jar, no credential storage and no URL cache. Every redirect is rejected before forwarding credentials. Signed/query-bearing URLs and foreign origins are rejected.
- 401/403, HTML login responses and redirects require sign-in through the existing normal connection flow. Logout or connection replacement cancels active transfers and rejects late callbacks from revoked snapshots. Retrying requires the same source origin; switching connections never silently authenticates a different source.
- Completion checks status, origin, content length, absence of partial Content-Range, and MP4/WebM signature before publishing a ready entry. Missing/truncated files, capacity checks, failed writes and corrupt manifests surface errors. A corrupt manifest is preserved rather than overwritten. Startup removes only orphaned files inside this store's private media/staging directories.
- Existing connection records and streaming cache formats are unchanged. The new library starts empty on upgrade. Network-unavailable startup preserves saved connection credentials and allows access to Downloads without completing server auto-login.

New downloads save an optional display-metadata snapshot and unsigned same-origin thumbnail/channel-artwork paths. Artwork is fetched through scoped foreground requests that reject redirects, capped at 4 MiB, downsampled to 1024px (thumbnail) / 160px (channel), re-encoded without source metadata, and saved privately. Artwork failure never invalidates a completed video. Playback and grid rendering use only explicit local artwork URLs, without a remote fallback; lock-screen artwork also stays local.

Build 4 records decode without the optional snapshot and keep playing. Their existing title/channel/duration/size remain visible in the shared cards. When connected to the same server, touch and hold a copy and choose **Refresh details & artwork** to fetch its metadata and images without downloading the video again. Refresh cannot change the saved media path or perform server progress/deletion writes. A missing image shows the normal placeholder until refreshed.

## Foreground transfer limitation

Keep TAClient open until a download finishes. Backgrounding or interruption cancels the partial transfer and persists an interrupted state; Retry starts from the beginning. Duplicate taps reuse the existing record and active transfer.

Apple documents that background URLSession tasks always follow redirects, and the redirect delegate is only called for default/ephemeral sessions. A background download therefore cannot enforce this client's authenticated-origin boundary. This implementation uses an ephemeral foreground download session, deliberately discards partial/resume data, and tells the user the limitation in the UI. It does not weaken authentication or change server configuration to enable background downloads.

Sources: [Apple background downloads](https://developer.apple.com/documentation/foundation/downloading-files-in-the-background), [URLSession redirect delegate](https://developer.apple.com/documentation/foundation/urlsessiontaskdelegate/urlsession(_:task:willperformhttpredirection:newrequest:completionhandler:)).

## Safe verification

Unit fixtures use a private temporary directory, in-memory credentials and a URLProtocol that performs no network traffic. The offline suite shares DataLayerSuite's serialized transport boundary because auth-expiry tests exercise shared cache cleanup. Tests cover credential-free manifests, backup exclusion, restart, deduplication, cancellation and late callbacks, expiry/revocation, origin boundaries, invalid/truncated files, failed writes, corrupt manifests, local removal and actual AVPlayer advancement/seek without authentication.

For real URLSession simulator tests:

```sh
python3 Tests/Fixtures/offline_server.py
# Build/install UIReviewPreview from UIReviewPreview.xcodeproj, then:
xcodebuild test -scheme ConnectionFlow \
  -only-testing:TAClientUITests/OfflineDownloadsUITests \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' CODE_SIGNING_ALLOWED=NO
```

The server binds only loopback ports 18081 and 18082, serves a generated two-second H.264 clip, and accepts only dummy fixture cookies. Tests exercise real transfer/cancel/retry, interrupted relaunch, signed-out playback after setting the fixture server unavailable, local deletion with zero DELETE requests, 401 and redirect rejection with zero requests reaching the second-origin listener. Light/dark and playback/progress/error screenshots are attached to the result bundle and saved separately in Library.

Owner-server media, physical-device file protection and the VLC decoder path still need normal owner/device validation. No owner credentials or media are read, no server settings change, and no device install or distribution is part of these tests.

## Apple-compatible preparation

New transfers now enter a cancelable Preparing phase before becoming ready. TAClient verifies the actual private file, keeps natively compatible MP4 files unchanged, and prepares other supported inputs locally as H.264/AAC MP4. Bitrate follows the source with a capped allowance rather than a fixed 5 Mbps. Native verification, decoded audio, sample coverage and head/tail video checks must succeed before publishing the copy. Known unverified HDR/rotation conversions fail clearly.

Preparing can add battery use, waiting and temporary storage. Keep the app foreground. Interrupted work is retryable after relaunch. Existing ready copies are retained with their original supported player selection; there is no automatic bulk conversion. See [preparation design and verification](testing/apple-compatible-downloads.md).
