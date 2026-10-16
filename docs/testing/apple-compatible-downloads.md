# Apple-compatible private downloads

TAClient now prepares new phone copies for the native Apple player without changing Tube Archivist's archived originals or ingestion settings. Compatible MP4 inputs are kept byte-for-byte when runtime video/audio validation succeeds; other supported inputs are converted locally with the already bundled MobileVLCKit 3.7.3.

## Transfer and preparation

Authenticated transfers retain the existing exact-origin, no-redirect policy. Complete HTTP 200 responses must pass Content-Length and container checks before entering `preparing`. A serial preparer inspects actual local media, rather than trusting server codec metadata or filename extensions. All input/output paths are protected, UUID-named files inside excluded-from-backup private staging. VLC receives file URLs and encoder options only; no credentials or network media URL enter its conversion path.

Preparation verifies native playability, drains complete sample streams (including decoded PCM audio and final timestamps), and decodes head/tail video frames. A compatible MP4 passes through unchanged. Otherwise, the derivative uses H.264 and AAC where audio conversion is needed, up to 1920×1080 while preserving source frame rate. Known HDR/rotation that needs unverified conversion is rejected; a natively validated HDR original can remain unchanged.

The video bitrate target is 1.6 times the measured source video bitrate, or a file-size/duration estimate when that bitrate is unavailable. It has a 256 kb/s floor and a 5 Mb/s ceiling. Thus an 800 kb/s video targets about 1.28 Mb/s, rather than 5 Mb/s. AAC conversion targets 128 kb/s stereo. These are quality/size targets, not promises of identical file size or quality. H.264 can need more space than AV1/VP9, and reencoding is lossy. Already-compatible files have no reencoding cost.

The preparer reserves output capacity with mux overhead and checks capacity as encoding proceeds. Unexpected output growth fails preparation. The converter uses a private VLC instance with explicit decoding/mux settings and bounded AVCodec/Dav1d threads. This matters: media-only settings did not prevent tail-frame loss in a silent VP9 fixture, and unbounded AV1 frame threading could produce an audio-only short derivative. MP4 faststart relocation is disabled for local derivatives to avoid an unnecessary full-file copy at close. Teardown and file quiescence precede final codec/duration/completeness validation; full validation can retry for up to 15 seconds while the asynchronous muxer finishes its index. A failed, short or unvalidated output is never marked ready.

## Lifecycle, playback and migration

`preparing` is a persisted, cancelable state with separate progress. Download/preparation cancellation, backgrounding, logout and server replacement revoke the attempt and prevent late completion from committing. Relaunch turns unfinished transfers/preparation into retryable interrupted records and removes orphan staging files. Cancelled work retains no resume-data credentials. Output is atomically moved and marked ready only after successful validation and current-attempt/auth checks.

Ready records save actual private-copy streams independently from archived-source metadata. A later server metadata refresh cannot overwrite them. A positive native-verification marker selects the existing AVPlayer/AVPlayerViewController path for these new copies, including otherwise conservatively blacklisted codecs that this device has actually verified. Native controls, fullscreen, PiP, local viewing progress and private artwork retain the production controller path. Streaming engine selection remains unchanged.

Existing downloaded files and manifests remain readable and are not automatically converted, replaced or deleted. Legacy copies without the optional fields retain the existing codec-aware AVKit/VLC fallback. Logout keeps ready private copies.

## Verification and limits

The fixtures contain generated test patterns and sine audio only. Coverage includes MP4 H.264/AAC byte preservation, VP9/Opus in MP4 and WebM, AV1/Opus MP4, a two-minute 720p VP9 clip, H.264/Opus conversion and vertical silent VP9. Tests exercise duration mismatch, capacity failure, known HDR handling, cancellation, server switching, interrupted manifest recovery, original-copy preservation, and metadata refresh after native verification.

Simulator UI coverage exercises Preparing → cancel → retry → ready, relaunch with the fixture server unavailable, and native playback/seeking/fullscreen. Separate session UI tests verify real synthetic Keychain persistence and normal expiry/logout. Test result paths and exact final counts are recorded in the task evidence.

Physical-iPhone throughput, thermal/battery behavior, hour-long media and general HDR tone mapping are not certified by Simulator tests. Known unverified HDR/rotation conversions fail explicitly instead of pretending to preserve them. This work does not implement a background conversion service; keep TAClient foreground during transfer/preparation. Existing private copies continue to work regardless of the new preparation path.

Final local regression on 2026-10-16: **763 unit tests passed, zero failures**, iPhone 17 Pro / iOS 26.5, signed Simulator build. Result bundle: `test_sim_2026-10-16T18-39-00-008Z_pid17905_824bece1.xcresult`. The three-format short-media matrix also passed five repetitions (15 fixture executions), result `test_sim_2026-10-16T18-37-57-166Z_pid17905_571e6c6c.xcresult`. The earlier standalone VLC feasibility converter is superseded by tests of the shipping preparer and its stricter validation.

`CompatibleDownloadsUITests.testPreparationCancelRetryAndNativeOfflinePlayback` passed, result `test_sim_2026-10-16T18-40-51-340Z_pid17905_5f15aa03.xcresult`, retaining five screenshots. Both `PlaybackParityUITests` cases passed in `test_sim_2026-10-16T18-17-06-250Z_pid17905_779def6a.xcresult`, covering native inline/fullscreen controls and zero offline media requests. The separate new preparation UI test was still failing in that earlier bundle due to an over-specific native accessibility seek assertion; its corrected assertion and precise AVPlayer unit seeks pass in the final results above.

In that Simulator run, the 30-second 720p VP9 fixture grew from 2,942,109 to 5,166,288 bytes and prepared/validated/played/seeked in 6.58 seconds; the two-minute fixture grew from 11,930,155 to 20,743,742 bytes in 17.57 seconds. These generated-fixture measurements are evidence of bounded behavior, not physical-device performance estimates.

## Server scope and alternatives

Tube Archivist's Format/Format Sort settings control YouTube → server ingestion. Its public ingestion code already merges into MP4, which does not establish H.264/AAC. Those settings do not convert existing archived media copied to a phone. The inspected public video API has no per-copy derivative conversion endpoint.

No server setting, original archived file, credential, access grant or service was changed. There is no new app dependency. A future server derivative alternative would require separately approved read-only source access, a separate bounded cache and authenticated range-serving integration. It could move conversion load off the phone but is not needed for the app-side path implemented here.

## Primary sources checked

- [Tube Archivist format settings](https://docs.tubearchivist.com/settings/application/#download-format)
- [Tube Archivist ingestion options](https://github.com/tubearchivist/tubearchivist/blob/master/backend/download/src/yt_dlp_handler.py)
- [Queue input serializers](https://github.com/tubearchivist/tubearchivist/blob/master/backend/download/serializers.py)
- [Video API routes](https://github.com/tubearchivist/tubearchivist/blob/master/backend/video/urls.py)
- [VideoLAN transcoder implementation](https://github.com/videolan/vlckit/blob/master/Sources/sout/VLCTranscoder.m)
- [VLC 3 stream-output conversion bounds](https://github.com/videolan/vlc/blob/3.0.x/modules/stream_out/transcode/transcode.c)
- [Apple AVAssetExportSession](https://developer.apple.com/documentation/avfoundation/avassetexportsession)

The actual bundled 3.7.3 headers/binary and Simulator output, rather than current upstream VLC implementation alone, establish the tested modules' behavior.
