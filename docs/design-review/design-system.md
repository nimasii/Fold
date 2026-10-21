# Fold — Cinema for your archive

Design concept only. This is a proposed system, not an implemented app. Functional inventory controls which surfaces exist. Do not invent subscription plans, recommendation engines, movies/episodes, watch parties or capabilities not present in Fold.

## Direction
A calm, cinematic personal streaming library, not a server-administration dashboard. Full-bleed artwork, a strong editorial title hierarchy, deliberate negative space and quiet controls. Preserve Fold's approved centered charcoal/red logo unchanged. Keep the same app-icon artwork across appearance modes.

Reference synthesis: Apple TV contributes artwork-led browsing and restrained translucent control layers; Netflix contributes visible navigation and decision-making context; Prime Video contributes obvious availability and direct playback actions. These are inspirations, not a pixel copy of their TV interfaces. Native phone ergonomics win over TV proportions.

## Tokens (proposed)
- Canonical review frame: 393 × 852 CSS px, render 3× to 1179 × 2556 PNG. Status/safe area 59 px top, 34 px bottom; honor rather than draw into them.
- Grid: 20 px horizontal insets; 12 px gaps; 4 px base rhythm. Spacing 4/8/12/16/20/24/32/40. Screen sections 32 px apart; title/body 12 px.
- Colors: canvas #0B0D10; surface #161A20; elevated #222831; separators #FFFFFF14; title #F6F7F9; body #C0C6CF; secondary #9CA6B4; Fold red #F14B55. Warning #F5BA60, success #67CAA4. Status color always paired with a label/icon.
- Typography: system UI/SF Pro where licensed/installed; otherwise Inter or Arial fallback with consistent metrics. Display 34/38 semibold, screen title 30/35 bold, section 22/27 semibold, card title 16/21 semibold, body/control 16/22 regular/medium, secondary 13/18, smallest labels 12/16. Avoid tiny upper-case metadata everywhere; one small kicker on hero is enough.
- Shape: art 14 px radius, panels 18 px, sheets 28 px top corners, controls capsule/12 px. Consistent radius by component, not different arbitrary values on each screen.
- Controls: main Play/Resume 50 px high, white background/dark text. Secondary controls subdued surface. Destructive controls red only when destructive. Touch target at least 44 × 44. Minimal hairline, no decorative neon glows or heavy borders.
- Icon system: one 1.75–2 px rounded-line SVG family at24 px, filled selected tab. Never mix emoji with line icons. Tab labels always visible.

## Shared composition
- Top chrome: predictable back at left, screen title or compact identity, one trailing overflow/action. Search should be one gesture away. Settings/account/server access in a consistent top trailing control, not on every card.
- Bottom navigation: preserve existing top-level destinations unless proposing an explicitly labeled information-architecture change. Same height, labels, selected color and geometry across every root screen. Do not casually hide Downloads inside another destination.
- Browse canvas: one hero no taller than approximately360 px including title/CTA, then immediately Continue Watching or useful library content. A phone should reveal real browse content without scrolling past a giant promo.
- Section shelves:16:9 cards with title/creator below. A2-column grid can use170.5 ×95.9 px art. A horizontal rail uses264 ×148.5 px art with a partial next card to indicate scrolling. Avoid portrait-cropping YouTube landscape thumbnails into movie posters.
- Hero: edge-to-edge16:9 artwork or taller composition only when safe source crop exists. Bottom black gradient, readable two-line title, creator and duration, one primary Play/Resume and compact secondary actions. No false title logos or fake award badges.
- Long titles:2–3 lines permitted, never ellipsis that removes the meaningful distinction; detail screen holds full title. Creator, duration and download state must remain legible.

## Functional treatments
- Video detail: large artwork/player surface; title, creator, duration/date, Resume/Play; save/download/overflow as a consistent secondary action row; description and related content below. Keep actions out of artwork faces and lower subtitles.
- Channel/playlist: same detail template with distinct creator/avatar or collection identity, followed by actionable video rows. Avoid creating TV seasons when actual data is playlists/videos.
- Queue: visual16:9 thumbnail rows, title and creator, ordered index/drag handle, clear Play next/Remove actions. Queue should never feel like an opaque database table.
- Downloads: use exactly the same thumbnail identity/title treatment as Queue and detail. Clear sections for Ready offline and Downloading. Per-row progress, size, pause/retry/status. Offline banner should reassure usable media rather than make entire page look broken. Preserve visible thumbnail in completed-local state.
- Player: content edge to edge; quiet translucent controls only while shown; standard timeline, elapsed/remaining, back, play/pause, skip, captions/audio/settings/AirPlay only if existing. Landscape needs its own designed board. Loading/error states remain within same player frame with one clear recovery action.
- Search: prominent search field, recent query/browse state if supported, results with filters and same cards. No-results message should offer a useful action without inventing remote search capabilities.
- Forms/server settings: cinematic shell still present, but opaque grouped surfaces and clear field labels. Never place credentials over a busy photo. Use visible validation inline. Connection success and credential error are distinct states.
- Sheets/dialogs: shared sheet header, close, typography and action geometry. Destructive confirmation names the item and consequence; primary action is not misleadingly white Play style.
- Empty/loading/error: same layout scaffold, stable image dimensions and skeleton blocks; one descriptive headline and one useful CTA. Show reconnect vs retry vs available-offline based on actual capability. A blank screen with spinner alone is not a finished design.

## Accessibility and appearance
- All images need meaningful accessible labels in eventual implementation; decorative art excluded. Logical focus order and VoiceOver names separate from icon glyph.
- Aim4.5:1 regular text contrast and3:1 large text/control boundaries; actual contrast testing required at implementation. Text over art always gets a dependable scrim; blur alone is insufficient.
- Large text variants wrap and reflow; no fixed tiny captions or clipped button labels. Include one enlarged-text board to establish the pattern.
- Reduced motion: no auto-moving hero, parallax or bouncing controls. Increased contrast/reduced transparency: replace glass with opaque surface.
- Canonical design is dark cinema. If app supports system appearance, provide a consistent light token set (#F4F5F7 canvas, #FFFFFF surface, #14171C title, #525D6B secondary; dark-red accent #B8293A). Keep artwork, spacing, component geometry and app icon identical. A black player is still black. Do not promise a new appearance setting not present in inventory.

## Mockup production
Use deterministic HTML/CSS and shared SVG components, rendered by Chromium. Keep source outside app repository. Build one shared shell, button/card/list/sheet/field components and a screen manifest keyed to every inventory item. Render3× PNG, provide individual image for every distinct screen, plus numbered contact sheets and a PDF index. Major states can be additional labeled boards; overlays need dedicated boards, not footnotes.

The same sample video must retain thumbnail/title/creator/duration across Library, Queue, Downloads, detail and player. Use sample names explicitly, e.g. “Above the tree line” / “Field Notes” /18:42. Concept assets live in assets/ and sources.json; no actual user-library contents are asserted. Name road.jpg “Sunrise ridge” rather than road.

Do not generate whole UI screens independently with imagegen: typography/control drift makes dozens of consistent screens harder to review. Imagegen may supply artwork only if needed. User explicitly permits separate tools.

QA each output for text overflow, touch targets, inconsistent tab state, missing controls and impossible data. A coverage manifest should map every source inventory screen/state to a PNG filename. Label proposal-only new surfaces and preserved system-owned UI separately.

## Verified official references
- Apple TV redesign, June9,2025: https://www.apple.com/newsroom/2025/06/apple-tv-brings-a-beautiful-redesign-and-enhanced-home-entertainment-experience/ — artwork focus and content-visible control layers; newsroom hero image visually inspected. Some embedded app-video poster image links return404.
- Apple iPhone Home personalization: https://support.apple.com/en-mk/guide/iphone/iphbf1137ac0/ios — Continue Watching and Watchlist behavior.
- Netflix TV redesign, May7,2025: https://www.netflix.com/tudum/articles/netflix-new-tv-layout — visible navigation, personal hub and useful title context. TV-specific; do not directly copy phone geometry.
- Prime Video experience update: https://www.aboutamazon.com/news/entertainment/prime-video-updated-steaming-experience — content-led navigation, hero direct actions and availability clarity.
- Apple accessibility reference: https://developer.apple.com/design/human-interface-guidelines/accessibility — page available but detailed text requires JavaScript; numeric targets above are our proposed design acceptance criteria, not a verbatim quotation.
