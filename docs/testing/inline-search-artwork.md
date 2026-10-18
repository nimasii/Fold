# Inline search, private artwork and Queue controls

The three primary sections remain Library, Downloads and Queue. On iOS 26+, the trailing native `Tab(role: .search)` affordance shares their bottom navigation row. It expands into the native search field rather than adding a second accessory row. Search has its own transient Library history. Cancel clears the query and returns to the originating section; all three primary section histories remain intact. Opening a result ends field presentation while pushed; returning restores native bottom-field placement. Search is scoped to the search content so other sections do not acquire a second field.

The implementation uses the installed SDK's `TabRole.search`, `tabViewSearchActivation(.searchTabSelection)` and toolbar search placement. This follows Apple's [WWDC25 search guidance](https://developer.apple.com/videos/play/wwdc2025/323/?time=670). The native search control is supplementary to the three `AppTab` cases and has no fourth persistent section history. Root menus remain Settings and supported Filters.

For iOS 17–25, one supported SwiftUI system-material row contains three section buttons plus Search; editing replaces that row with the keyboard-aware search editor. There is no extra stacked row or simulated glass. The Debug Simulator flag `--navigation-legacy-search` exercises this fallback on the installed runtime.

Queue now puts Pending/Ignored, a compact primary Start/Stop action and a secondary rescan icon on one cohesive row. Full accessibility names, loading indicators, disabled states, privilege gating, confirmations, polling and depth-preserving reconciliation remain in place.

## Private artwork

New downloads save the thumbnail and available channel artwork as sanitized JPEG pixels in the app-private Artwork directory, excluded from backups alongside the private media. Artwork is independent of URL/image caches. The list, local player poster and channel label load these files locally; a photo placeholder represents missing or corrupt images.

Visible downloads and local details lazily repair missing artwork. Existing copies without a presentation snapshot use the existing read-only video-detail repository to recover unsigned artwork paths. The active connection must match the saved scheme/host/port, and its authorization identity is checked again after each await before committing. Persisted paths are revalidated against traversal, encoded separators, credentials, query strings and foreign origins; local artwork symlinks are rejected. Metadata and pixel repair never enqueue or replace a ready video.

Two artwork downloads can fetch concurrently. Image responses remain bounded to 4 MiB; display-sized pixel preparation occurs off the main actor, followed by an atomic guarded private-file commit. Image validation is cached by size and modification time. A failed optional image leaves the video ready and receives a 30-second retry cooldown. Foreground entry and pull-to-refresh allow another visible-image attempt. Successful metadata reads lacking an image are cooled down for five minutes. Connection changes, removal and background interruption cancel repair work. Local artwork references observe the revision so details can display a late repair.

[Actual Simulator review sheet](../screenshots/inline-search-artwork-review.png).

## Validation

- Full unit suite: **773 passed**, including six new private-artwork tests and expanded search-history/expiry assertions.
- The three feature UI scenarios passed on iPhone 17e: native inline search lifecycle, compact Queue loading/disabled states, and private artwork across offline relaunch/legacy/corrupt repair.
- All four broader navigation UI scenarios passed on iPhone 17 Pro across focused runs, including menus, independent histories, filters, Queue actions, offline playback/logout, accessibility text sizes and fallback layout. A dedicated fallback result/back/Cancel-to-Queue scenario also passed.
- The private-artwork scenario passed again on iPhone 17 Pro after verifying player navigation chrome stays hidden.
- An additional compact-screen run passed native large text, fallback standard text and fallback accessibility text.
- The separate UI review preview target also built successfully.
- Simulator captures show actual shipping views under an isolated fixture account; no owner credentials or production writes are used.

The loopback fixture rejects artwork/media while offline; tests assert no new artwork or media requests when saved files are shown and played, and no new media requests during legacy/corrupt repair. Unit tests also restore artwork while signed out and check byte-for-byte preservation of ready media. This is deterministic offline evidence, not a physical-device radio test. Actual airplane-mode hardware behavior, real VoiceOver and an installed older-iOS runtime remain separate checks. No release or distribution is part of this review branch.
