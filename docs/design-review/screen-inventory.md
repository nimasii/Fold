# Fold exhaustive UI inventory

Source commit: `00d7455cf9825a136db07af443cbfdc9322f028c` (read-only static code audit). All production Swift UI files and the share extension reviewed. No simulator run; this is code-derived coverage, not live runtime verification.

## Coverage matrix / proposed design-image IDs

### 01. Launch / restoring session
- Source: Fold/FoldApp.swift#L64; Fold/Presentation/Common/SplashView.swift
- Symbol: SplashView, RootView
- Required coverage: Logo, progress indicator, offline-downloads escape route during session restore.

### 02. Connect to server
- Source: Fold/Presentation/Login/LoginView.swift#L13
- Symbol: LoginView
- Required coverage: Server address, Sign in, optional API token, saved downloads access; disabled until valid input, keyboard states.

### 03. API token connection
- Source: Fold/Presentation/Login/LoginView.swift#L123
- Symbol: LoginView.tokenOption
- Required coverage: Expanded fallback with secure token field, connect CTA, explanation/privacy; input/loading/error states.

### 04. Server sign-in sheet
- Source: Fold/Presentation/Login/ServerSignInView.swift#L52
- Symbol: ServerSignInView
- Required coverage: Trusted-host header, actual server web content, Cancel/Finish, blocked redirect and authentication errors. Server content is external-owned; redesign shell only.

### 05. Library / discovery
- Source: Fold/Presentation/VideoList/VideoListView.swift#L8
- Symbol: VideoListView
- Required coverage: Featured video, Continue watching when relevant, Recently added, Browse grid, Playlists entry, watched/progress badges, channel links, infinite scrolling.

### 06. Library filters and sorting
- Source: Fold/Presentation/Common/SectionMenu.swift#L24; Fold/Presentation/VideoList/SortFilterBar.swift
- Symbol: LibraryFilterActions
- Required coverage: All/Videos/Shorts/Streams; All/Unwatched/Watched/Continue; downloaded/published/views/likes/duration/file size; ascending/descending. Show filtered library state as inset.

### 07. Library multi-selection
- Source: Fold/Presentation/VideoList/VideoListView.swift#L142
- Symbol: selectionActions
- Required coverage: Selected count, checkmarks, mark watched/unwatched, privileged delete, select all, Cancel. Discovery/Playlists hidden.

### 08. Search introduction / editing
- Source: Fold/Presentation/Search/SearchView.swift#L42; Fold/Presentation/Search/BottomLibrarySearch.swift
- Symbol: SearchView, LibrarySearchEditor
- Required coverage: Search Library field, keyboard, Cancel. iOS26 native trailing Search role; older OS bottom editor. Preserve origin tab and history.

### 09. Search results
- Source: Fold/Presentation/Search/SearchView.swift#L18
- Symbol: SearchView
- Required coverage: Results count, grid, video/channel navigation, updating spinner; query retained after return.

### 10. Channel detail
- Source: Fold/Presentation/ChannelDetail/ChannelDetailView.swift#L133
- Symbol: ChannelDetailView.channelHeader
- Required coverage: Banner, avatar, title, subscriber count, privileged Subscribe/Subscribed, About disclosure, video grid.

### 11. Channel About expanded
- Source: Fold/Presentation/ChannelDetail/ChannelDetailView.swift#L164
- Symbol: channelHeader DisclosureGroup
- Required coverage: Long description expanded with same channel hierarchy; preserve scroll.

### 12. Channel multi-selection
- Source: Fold/Presentation/ChannelDetail/ChannelDetailView.swift#L59
- Symbol: ChannelDetailView toolbar
- Required coverage: Selected count, watched/unwatched, privileged delete, select-all, cancel with grid selection.

### 13. Playlists / collections
- Source: Fold/Presentation/Playlist/PlaylistListView.swift#L9
- Symbol: PlaylistListView
- Required coverage: Artwork grid, title/channel/video count, filter, Create, context delete, pagination.

### 14. Playlist filter
- Source: Fold/Presentation/Playlist/PlaylistListView.swift#L62
- Symbol: PlaylistListView toolbar Menu
- Required coverage: All, regular, custom; filtered list context visible.

### 15. Create playlist dialog
- Source: Fold/Presentation/Playlist/PlaylistListView.swift#L90; Fold/Presentation/VideoDetail/AddToPlaylistSheet.swift#L45
- Symbol: showCreateDialog / showCreateAlert
- Required coverage: Playlist name, Cancel/Create, keyboard. Shared component used from collection list or Add to playlist.

### 16. Regular playlist detail
- Source: Fold/Presentation/Playlist/PlaylistDetailView.swift#L82
- Symbol: playlistHeader
- Required coverage: Hero art/title/count/type/channel/description, Subscribe or Unsubscribe, video grid, delete menu.

### 17. Custom playlist detail
- Source: Fold/Presentation/Playlist/PlaylistDetailView.swift#L82
- Symbol: playlistHeader
- Required coverage: Same collection language; custom type, no subscription action; videos grid and delete.

### 18. Video detail / Description
- Source: Fold/Presentation/VideoDetail/VideoDetailView.swift#L114; Fold/Presentation/VideoDetail/VideoInfoSection.swift
- Symbol: videoContent, videoDetails
- Required coverage: Poster/play, title/duration/published/watched, channel, detail disclosure, save offline, Description/Comments/Similar. Privileged server delete, add-to-playlist, watched toggle, pin while playing.

### 19. Video technical details expanded
- Source: Fold/Presentation/VideoDetail/VideoInfoSection.swift#L30
- Symbol: DisclosureGroup
- Required coverage: Views/likes, published/downloaded dates, each stream codec/resolution/bitrate, file size.

### 20. Video comments and replies
- Source: Fold/Presentation/VideoDetail/VideoDetailView.swift#L191; Fold/Presentation/VideoDetail/CommentRow.swift
- Symbol: CommentsSection, CommentRow
- Required coverage: Comment count, avatar, uploader treatment, timestamp, text, likes, expand/hide nested replies. Read-only comments, not compose.

### 21. Similar videos
- Source: Fold/Presentation/VideoDetail/SimilarVideosSection.swift
- Symbol: SimilarVideosSection
- Required coverage: Video thumbnail/title/channel/duration/views/watched, open video or channel.

### 22. Add to playlist sheet
- Source: Fold/Presentation/VideoDetail/AddToPlaylistSheet.swift#L25
- Symbol: AddToPlaylistSheet
- Required coverage: Custom playlist toggles; regular playlists are read-only membership; create and Done; medium/large detents.

### 23. Add to playlist empty
- Source: Fold/Presentation/VideoDetail/AddToPlaylistSheet.swift#L66
- Symbol: playlistContent
- Required coverage: No custom/eligible member playlists, Create plus action remains.

### 24. Native fullscreen playback
- Source: Fold/Presentation/VideoDetail/VideoDetailView.swift#L233; Fold/Presentation/Common/VideoPlayerSurface.swift
- Symbol: AVPlayerView
- Required coverage: Landscape AVKit playback, pause/play/timeline, fullscreen, PiP/AirPlay native system controls; source design must distinguish system-owned controls.

### 25. VLC fullscreen playback
- Source: Fold/Presentation/VideoDetail/VLCPlayerView.swift#L328; Fold/Presentation/VideoDetail/VLCPlayerControls.swift
- Symbol: VLCFullScreenVC, VLCPlayerControls
- Required coverage: Landscape alternate codec player, custom timeline/time/play-pause/fullscreen and tap-to-hide, seek feedback. No unsupported native-only AirPlay/PiP promises.

### 26. Picture in Picture / pinned playback
- Source: Fold/Presentation/VideoDetail/VideoDetailView.swift#L29; Fold/Presentation/Common/VideoPlayerSurface.swift#L148
- Symbol: AVPlayerView, VideoDetailLayout
- Required coverage: Pinned inline player over scrollable details; PiP system window leaving detail screen. Two distinct layout states on one board.

### 27. Downloads / ready on device
- Source: Fold/Presentation/Offline/OfflineDownloadsView.swift#L17
- Symbol: OfflineDownloadsView
- Required coverage: Local artwork grid, file sizes, device total storage, private/local copy explanation, info, all/ready/transfers filters, no-network use.

### 28. Downloads / active transfers
- Source: Fold/Presentation/Offline/OfflineDownloadsView.swift#L132
- Symbol: transferRow
- Required coverage: Downloading/preparing progress, cancel, saved items coexist; artwork should be shown in new design, not claimed implemented.

### 29. Downloads information sheet
- Source: Fold/Presentation/Offline/OfflineDownloadsView.swift#L92
- Symbol: showInfo Form
- Required coverage: Storage used, local privacy, transfer/preparation/sign-in/legacy-artwork explanations, Done.

### 30. Offline video detail / playback
- Source: Fold/Presentation/Offline/OfflineDownloadsView.swift#L164; Fold/Presentation/VideoDetail/VideoDetailView.swift#L167
- Symbol: OfflinePlayerScreen
- Required coverage: Same production player/detail language; local copy badge, local metadata/description, pin; NO server watch/delete/playlists/channel navigation/comments/similar; local progress only.

### 31. Queue / pending
- Source: Fold/Presentation/DownloadQueue/DownloadQueueView.swift#L10
- Symbol: DownloadQueueView
- Required coverage: Server queue NOT device downloads; pending rows with artwork/title/channel/duration/published/message, privileged add URL/start/rescan.

### 32. Queue / ignored
- Source: Fold/Presentation/DownloadQueue/DownloadQueueView.swift#L186
- Symbol: filter == ignore
- Required coverage: Ignored items, restore to pending, download item, delete; Start disabled.

### 33. Queue / running task
- Source: Fold/Presentation/DownloadQueue/DownloadQueueView.swift#L87
- Symbol: TaskNotificationBanner, queueControls
- Required coverage: Task title/progress/message, Stop when permitted, stable list scroll, running/rescanning indicators.

### 34. Queue / add link editing
- Source: Fold/Presentation/DownloadQueue/DownloadQueueView.swift#L125
- Symbol: addInput
- Required coverage: URL or ID input keyboard, Add disabled/adding state, inline error; same queue context.

### 35. Queue item swipe actions
- Source: Fold/Presentation/DownloadQueue/DownloadQueueView.swift#L31
- Symbol: swipeActions
- Required coverage: Trailing Delete + Ignore/Return pending; leading Download now; preserve accessible equivalents.

### 36. Settings / playback preferences
- Source: Fold/Presentation/Settings/SettingsView.swift#L10
- Symbol: SettingsView
- Required coverage: Server host, SponsorBlock enabled and eight category toggles, double-tap seek toggle, seek interval, logout, About. Disabled toggles collapse dependent controls.

### 37. Seek interval picker
- Source: Fold/Presentation/Settings/SettingsView.swift#L54
- Symbol: Picker
- Required coverage: 5/10/15/30 seconds; platform picker presentation; settings context.

### 38. About
- Source: Fold/Presentation/Settings/AboutView.swift#L11
- Symbol: AboutView
- Required coverage: App version/build, description, disclaimer, licenses, source/support/Tube Archivist links.

### 39. MobileVLCKit license
- Source: Fold/Presentation/Settings/AboutView.swift#L94
- Symbol: LicenseDetailView
- Required coverage: Scrollable LGPL2.1 legal text, title/back; preserve legal copy.

### 40. Fold license
- Source: Fold/Presentation/Settings/AboutView.swift#L94
- Symbol: LicenseDetailView
- Required coverage: Scrollable Apache2.0 legal text, title/back; shared layout, different content.

### 41. Share extension / sending
- Source: ShareExtension/ShareViewController.swift#L226
- Symbol: ShareOverlayView loading
- Required coverage: Presented over external app; sending shared YouTube URL to server queue; progress overlay.

### 42. Share extension / success
- Source: ShareExtension/ShareViewController.swift#L239
- Symbol: ShareOverlayView success
- Required coverage: Success check and automatic close; no invented additional action.

### 43. Share extension / errors
- Source: ShareExtension/ShareViewController.swift#L195
- Symbol: ShareError
- Required coverage: Invalid URL, not logged in, unauthorized, network, server error; message + error icon, automatic dismiss. One image board with all five messages.

### 44. Delete server video confirmation
- Source: Fold/Presentation/VideoDetail/VideoDetailView.swift#L67
- Symbol: showDeleteDialog
- Required coverage: Delete, Delete and ignore, Cancel; explains destructive server scope.

### 45. Delete selected videos confirmation
- Source: Fold/Presentation/VideoList/VideoListView.swift#L113; Fold/Presentation/ChannelDetail/ChannelDetailView.swift#L106
- Symbol: showDeleteConfirmation
- Required coverage: Selected count, Delete/Cancel; applies Library and Channel contexts.

### 46. Delete queue item confirmation
- Source: Fold/Presentation/DownloadQueue/DownloadQueueView.swift#L169
- Symbol: pendingDeletion
- Required coverage: Item title, Delete/Cancel; distinguish queue item from downloaded media.

### 47. Delete playlist detail confirmation
- Source: Fold/Presentation/Playlist/PlaylistDetailView.swift#L57
- Symbol: showDeleteDialog
- Required coverage: Delete playlist keep videos vs Delete with videos, Cancel; consequential distinction visible.

### 48. Delete playlist from list confirmation
- Source: Fold/Presentation/Playlist/PlaylistListView.swift#L99
- Symbol: deleting
- Required coverage: Delete playlist keep videos only, Cancel; differs from detail dialog.

### 49. Remove local copy confirmation
- Source: Fold/Presentation/Offline/OfflineDownloadsView.swift#L85
- Symbol: removing
- Required coverage: Remove local download, server original stays, Cancel.

### 50. Sign out confirmation
- Source: Fold/Presentation/Settings/SettingsView.swift#L92
- Symbol: showLogoutConfirmation
- Required coverage: Sign out/Cancel; local downloads remain available via login.

### 51. Connection state board
- Source: Fold/Presentation/Login/LoginView.swift#L81; Fold/Presentation/Login/ServerSignInView.swift#L72
- Symbol: errorMessage/isLoading/browser.blocked
- Required coverage: Disabled empty form, connecting, connection error, web blocked-redirect/auth-failure; preserve original validation meaning.

### 52. Library state board
- Source: Fold/Presentation/VideoList/VideoListView.swift#L11
- Symbol: body
- Required coverage: Initial loading, error+Retry, no videos, filtered grid without discovery, pagination loading; playlists still reachable when empty.

### 53. Search state board
- Source: Fold/Presentation/Search/SearchView.swift#L42
- Symbol: results
- Required coverage: Searching spinner, no results(query), request error+Retry, results refreshing spinner; preserve Cancel.

### 54. Channel state board
- Source: Fold/Presentation/ChannelDetail/ChannelDetailView.swift#L9
- Symbol: body
- Required coverage: Loading, error+Retry, header with no videos, pagination, subscribed/unsubscribed and nonprivileged.

### 55. Playlist states board
- Source: Fold/Presentation/Playlist/PlaylistListView.swift#L12; Fold/Presentation/Playlist/PlaylistDetailView.swift#L7
- Symbol: body
- Required coverage: List loading/error/empty/pagination, detail loading/error, detail empty videos, subscribed/unsubscribed.

### 56. Video content states board
- Source: Fold/Presentation/VideoDetail/VideoDetailView.swift#L12; Fold/Presentation/VideoDetail/CommentsSection.swift; Fold/Presentation/VideoDetail/SimilarVideosSection.swift
- Symbol: body
- Required coverage: Detail loading/error+Retry, absent description, comments loading/empty, similar loading/empty, watched/unwatched.

### 57. Downloads empty / filtering / storage
- Source: Fold/Presentation/Offline/OfflineDownloadsView.swift#L20
- Symbol: body
- Required coverage: No downloads, no matches for current filter, storage error, all/ready/transfers menu, downloaded-item context menu Remove/Refresh details and refreshing label.

### 58. Transfer failure / recovery states
- Source: Fold/Data/Offline/OfflineRecord.swift; Fold/Presentation/Offline/OfflineDownloadsView.swift#L132
- Symbol: OfflineStatus, OfflineFailure
- Required coverage: Canceled/interrupted/failed/needs-sign-in with Retry; failures network/storage/invalid media/missing file/sign-in/server/conversion/unsupported conversion; active downloading/preparing and Ready.

### 59. Queue loading / empty / failures
- Source: Fold/Presentation/DownloadQueue/DownloadQueueView.swift#L12
- Symbol: body, TaskNotificationBanner
- Required coverage: Loading/error Retry/empty; dismissible inline error with existing items; failed task banner; row failure text; pending/ignore menu.

### 60. Player overlays / download CTA states
- Source: Fold/Presentation/Common/VideoPlayerSurface.swift#L31; Fold/Presentation/VideoDetail/VideoDetailView.swift#L143; Fold/Presentation/Offline/OfflineDownloadButton.swift
- Symbol: playerArea, sponsorBlockBanner
- Required coverage: Poster ready, buffering, playback error+Retry, sponsor segment skipped+Undo, seek ± feedback, download CTA not saved/downloading/preparing/ready/error.


## Navigation graph and ownership

- RootView: saved authorization → session-restoration/splash → authenticated shell; failure → Connect. Both Connect and Splash expose local Downloads without authentication.
- Authenticated shell: Library, Downloads (private on-device copies), Queue (server acquisition tasks). Search is a transient Library context with independent navigation and a remembered originating tab; it is not currently a fourth primary content section.
- Library → video detail / channel / Playlists. Video detail → channel / similar-video detail / Add to playlist. Playlists → regular or custom playlist detail → video detail / channel.
- Any primary section overflow → Settings → About → either license. Section overflow also exposes supported section filters.
- Downloads → private OfflinePlayerScreen (same detail component with reduced capabilities), Download Info sheet, local remove confirmation. It is available logged out and has no dependency on live server credentials to play saved media.
- Queue owns Add/Start/Stop/Rescan/Ignore/Restore/Delete acquisition actions and shows task polling progress; it is NOT the local offline-download list.
- Share extension is a separate entry point from other apps. It has loading/success/error states and auto-dismisses, not a main-app navigation destination.
- Retained Route.search / SearchScreen supports a standalone navigation-bar search screen in addition to the normal embedded Library search. VideoListViewModel.navigateToSearch still exists; current VideoListView does not call it. Treat as a retained/legacy route, not pretend it is current primary navigation. Include an alternate standalone search frame in image 08/09 to satisfy source coverage.

## Production variants that must not be lost

- iOS26 uses native TabView + trailing Search role; iOS17–25 use the custom bottom navigation row/editor fallback. Both keep the same three primary sections and separate tab histories. Include a navigation comparison board.
- Layout is adaptive for iPhone/iPad widths; no separate custom iPad screen tree exists. Grid minimum is160points, or300 in accessibility size. Login is capped520points. Provide iPad landscape mockups for Library, video detail/player, Downloads, Queue, collections, and Settings to prove hierarchy consistency; do not multiply all data states into redundant iPad frames.
- Dark and light color schemes are inherited system styles throughout the actual app; large Dynamic Type changes featured-video layout and suppresses legacy tab captions. Include light-theme and accessibility-size examples for Connect, Library, detail, Queue, and Settings. A unified design system must define both themes, not just dark marketing images.
- Privileged vs standard users: Library/Channel bulk delete, channel subscription, detail server delete, Queue add/start/stop/rescan are gated in UI. Do not invent unprivileged destructive controls. Queue per-item swipe actions and playlist delete are not UI gated in these source files; backend authorization may reject them.
- Online AVKit supports native full screen, PiP, AirPlay/system controls; VLC is a separate fullscreen landscape fallback with its own controls. Local playback uses the same machinery while limiting server actions and keeping progress private.
- Playlists contain regular server subscriptions and editable custom lists. Add to playlist lets you toggle only custom memberships; existing regular memberships are informative/read-only.
- Settings includes all eight SponsorBlock categories: sponsor, self-promotion, interaction, intro, outro, preview, hook, filler. Double-tap intervals are5/10/15/30seconds.
- Destructive scopes differ: remove local copy, delete server video, delete-and-ignore video, delete queue entry, delete playlist only, delete playlist with videos. Never unify these into an ambiguous Delete label without scoped copy.

## State completeness rules for design delivery

The60 image IDs above are a proposed deliverable matrix, not a claim that the app has60 independent full-screen routes. IDs01–50 cover distinct pages, sheets, expanded/presentation variants, and confirmations. IDs51–60 are explicitly labeled multi-frame state boards covering non-happy paths. A designer may combine closely related variants into a board, but each numbered coverage item must be visibly represented and traceable in the delivery index. Include an individual full-size export for every primary screen; contact sheets alone are not sufficient for review.

Every UI family must have loading, content, empty, recoverable error, disabled/in-progress action, long-text/accessibility and light/dark treatments where code supports them. Do not add nonexistent write-comments, profile-management, subscriptions billing, search-history, or new streaming-service content features as if already supported. Proposed navigation changes may be shown, clearly marked as design proposals.

## System-owned / external surfaces

- Server webpage content in ServerSignInView is supplied by the user's Tube Archivist/Umbrel server. Only the enclosing app sheet is controlled by Fold. Show realistic neutral placeholder login content, not a fabricated authentication promise.
- Apple native keyboard, AVKit full-screen controls, PiP window, AirPlay route picker, lock-screen Now Playing controls and local-network permission prompt are system-owned. Include contextual handoff sketches where useful; style the app around them rather than claiming a bespoke redesign of OS UI.
- Source/support/Tube Archivist links from About leave the app. Their destination websites are not Fold screens.
- Debug simulator fixture routes and PreviewApp are excluded from user production inventory. All underlying production components they exercise are included.

## Evidence and limitations

Inspected all production Swift files defining UI in Fold/Presentation, Fold/FoldApp.swift, ShareExtension/ShareViewController.swift; reviewed every route, sheet, alert, confirmationDialog, NavigationLink and UIKit full-screen presentation. Also checked view-model navigation calls, OfflineStatus/OfflineFailure, settings and playlist filter enumerations. Source at the exact rollback commit, no repository mutation, test run, simulator, or device access.

Source base: https://github.com/nimasii/Fold/tree/00d7455cf9825a136db07af443cbfdc9322f028c

Potential delivery issue to avoid: The restored app already has FeaturedVideo/VideoShelf components and some streaming-inspired hierarchy. The requested new designs should be a coherent rework, not merely recoloring those same current layouts.

