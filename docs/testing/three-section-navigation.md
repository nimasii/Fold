# Three sections and bottom Library search

This records PR9 validation. The current [inline-search and artwork refinement](inline-search-artwork.md) supersedes its stacked-accessory search placement and search-history behavior.

The primary navigation is exactly **Library**, **Downloads** and **Queue**. Library combines the archive discovery/video grid with a contextual Playlists entry. Downloads contains private local copies; Queue contains pending and ignored server work. Root menus contain Settings and supported filters only. Search is a Library context rather than a fourth section.

On iOS26.1 and later the shell uses SwiftUI's native `tabViewBottomAccessory`. A search control opens Library search. During editing the tabs/accessory yield to a keyboard-aware bottom safe-area search bar, so the query and Cancel remain visible above the keyboard. UIKit owns editing and clear; a sibling native Cancel remains enabled after Return. Older supported systems and accessibility text sizes use bottom safe-area placement. This keeps the control tappable when large discovery content overlaps the native tab accessory on compact screens. The compact control has an explicit Library scope, routes there from another primary section, and clears on Cancel. Starting a search intentionally goes to the Library root; ordinary tab changes preserve all three independent back stacks. A Library search does not discard Downloads or Queue history. Searches use the existing debounced repository and stale-result guard; no API behavior or authentication is added.

The shell keeps primary tabs available on non-player destinations, including Settings and collections. Player destinations hide navigation/search chrome. Logout and expiry clear all section paths and transient search state. Local player visibility is presentation state only; storage, authorization and conversion services are unchanged.

Useful actions were relocated, not deleted:

- Playlists has one contextual entry in Library content.
- Library filters include video type, watch state, sort and direction. Selection actions and the selected count appear in a contextual bar with accessible hit areas.
- Logout lives in Settings with confirmation; existing playback preferences and About remain there.
- Local download information lives in Downloads content, alongside local status filters. Retry, cancel, refresh and removal remain available.
- Queue start/stop, rescan and adding a URL remain in the Queue surface; swipe actions retain ignore/requeue/download and confirmed deletion. Pending/Ignored changes through the root Filters menu. The VM's polling/reconciliation and stable-list/safe-area banner contract are preserved.

## Icon

The app icon is an original minimal play/video/archive mark, with dedicated default, dark and monochrome tinted variants. Opaque 1024px masters keep square full-bleed backgrounds so iOS supplies its mask. [Icon preview](../screenshots/navigation-icon-preview.png), [vector sources and regeneration](../branding/README.md). The design takes inspiration from the familiar video/play motif without copying YouTube's logo or claiming affiliation.

## Validation and limits

- Full unit suite: **767 passed**, including search routing and expiry reset.
- Connection/session fixture regression: **2 UI tests passed**, covering gateway-only rejection, application session sign-in, blocked external redirect, confirmed logout, process relaunch, maintenance/offline retention and server expiry.
- All four navigation UI scenarios passed on the compact iPhone 17e across focused runs; the same scenarios were also exercised successfully on iPhone 17 Pro. Coverage includes keyboard search, menu contents, independent histories, contextual actions, local playback and logout.
- Native accessory placement at ordinary text sizes, accessibility-size safe-area placement and the forced older-layout branch were exercised on iOS 26.5.
- The shipping target built and ran on Simulator. The separate UI review preview target also built successfully.
- Default, dark and tinted icons are 1024×1024, sRGB and opaque. The actual installed icon was visually checked, including small-size preview samples.

[Actual simulator review sheet](../screenshots/three-section-navigation.png).

`StreamingRedesignUITests` uses the shipping target's isolated loopback fixture. It checks the three tab identities, menu contents, Settings from each section, global search routing/results/clear/Return/Cancel, independent stacks, Library filters/collections, Queue actions, local download filters and native offline playback without new media requests, plus large text and forced safe-area fallback. Auth/session tests use the existing separate connection fixture. No live owner account or production archive is used.

The older-OS layout branch can be exercised with `--navigation-legacy-search` in Debug Simulator. This checks placement behavior on the installed runtime, not an uninstalled older iOS runtime. Physical-device performance, real VoiceOver, owner sign-in and App Store/TestFlight distribution are separate checks; this review branch does not merge or release a build.
