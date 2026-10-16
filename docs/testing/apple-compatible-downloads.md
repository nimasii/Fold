# Apple-compatible phone downloads: feasibility and implementation scope

Investigation branch: `codex/apple-compatible-downloads`, based on the tested session-restoration commit `0d94d3dafab5578d7bd79c8f56cdb2f5e9961bde`. No production download behavior, original media, server configuration or dependency has been changed by this investigation.

## Two distinct download stages

1. **YouTube → Tube Archivist:** the server's global Format/Format Sort settings select what yt-dlp archives. Its code already merges into an MP4 container, which does not imply H.264/AAC. Current public add-to-queue serializers expose no per-item codec/format override. Changing global ingestion would affect future archive quality/format and would not convert existing archived videos. Do not change this setting for a phone-copy feature.
2. **Tube Archivist → TAClient:** OfflineLibrary currently downloads the existing media URL into private staging and commits those bytes unchanged. Its MP4/WebM header checks validate the container only. Naming a file `.mp4` does not change its codecs. There is no existing transcoding/derivative route in the public server video API inspected here.

Private deployment capabilities are not inferred from public source. No live Umbrel access was performed on the Mac. If a server option is considered, ask the parent task to inspect installed version/custom services, available FFmpeg encoders, hardware acceleration, capacity and authentication through Umbrel Remote/Agent.

## Phone-side proof

The bundled **MobileVLCKit 3.7.3** already contains a VideoToolbox H.264 encoder and MP4 muxer, and exposes per-media stream-output options. Its narrow `VLCTranscoder` wrapper is intended for subtitle merging; it is not a general MP4 conversion API. However, a file-only VLCMediaPlayer stream-output pipeline can use the same underlying modules.

`OfflineConversionFeasibilityTests` exercises generated one-second local fixtures:

| Input | AVFoundation native export on this Simulator | Bundled VLC → H.264/AAC MP4 |
| --- | --- | --- |
| H.264/AAC MP4 | Yes | Yes |
| VP9/Opus WebM | No | Yes |
| VP9/Opus MP4 | No | Yes |
| AV1/Opus MP4 | No | Yes |

The AV1 Simulator result is **not** a claim that AV1 is unsupported on Jake's iPhone: his screenshot demonstrates native AV1/Opus playback there. Native export cannot be the sole conversion strategy for media the current device's AVFoundation cannot decode.

The VLC test uses `vcodec=h264,venc=vtenc_h264,vb=5000,fps=30,maxwidth=1920,maxheight=1080,acodec=mp4a,ab=128,channels=2,samplerate=48000`, a file-only MP4 destination, and no display/network output. It verifies actual output track formats (`avc1` and AAC), duration, decoded video frame, fully decoded audio buffers, AVPlayer advancement and precise seek. It byte-compares each source after conversion. All four outputs passed; inputs remained unchanged. The full Simulator unit suite passed **755 tests, zero failures** after adding the two probes. No credential or remote URL enters VLC.

This establishes **feasibility**, not a production guarantee for all files, hardware or long videos. The probe is not wired into the Downloads flow.

## Concrete app-side integration

Recommended target for a broadly compatible phone copy: **MP4, H.264, AAC stereo 48 kHz, up to 1080p/30**, with a roughly 5 Mb/s video / 128 kb/s audio target for converted copies. Keep the archived server original unchanged.

1. Continue the existing exact-origin, no-redirect authenticated transfer into protected private staging.
2. Inspect the downloaded file's actual streams. Reuse verified, already-compatible MP4/H.264/AAC files without reencoding. Missing/stale server metadata must not establish compatibility.
3. For other supported inputs, convert the private staged source to a separate UUID-named, protected MP4 via the bundled VLC modules. Serialize conversion jobs and expose a separate Preparing phase.
4. Validate output codecs, video/audio presence, duration/completeness and native playability before atomically committing it as ready. Store actual output streams separately from archived-source metadata so the local player selects AVKit and displays accurate information. A failed output must never be called Apple-compatible or silently substituted with the original.
5. Keep cancellation/background handling generation-scoped, stop the converter, release its player/delegate, and remove partial output. Reserve space for both source and derivative plus encoding overhead. Keep both excluded from backups and app-private throughout.
6. Preserve all existing ready downloads. No automatic bulk migration, replacement or deletion. Continue their existing supported playback until an explicitly requested per-copy conversion/redownload is available.

Before enabling the pipeline, add lifecycle/cancel/logout/server-switch tests, concurrent playback/resource tests, storage exhaustion/corruption checks, and long-media validation on an actual iPhone. Also test HDR/10-bit tone mapping, rotation/vertical video, variable frame rates, silent video and multiple audio streams. The one-second SDR fixtures do not establish these behaviors.

## Costs and permissions

- On-phone conversion avoids an Umbrel service, new server permissions and new decoder dependencies. It consumes phone battery/CPU/GPU, adds a preparation wait, and requires extra temporary storage. Conversion may reduce quality; a H.264 derivative may be substantially larger than AV1/VP9. At 5 Mb/s video + 128 kb/s audio, a one-hour copy is roughly **2.3 GB**, before variable-rate differences. No real-device throughput claim has been made.
- A server-generated derivative remains an optional alternative when phone cost is unacceptable. It would need a separate authenticated service/integration, read-only source access, a separate bounded derivative cache, one job at a time, cancellation/expiry, and an authenticated range-capable download endpoint. It must not replace archived originals or weaken gateway/app authentication.
- Installing that service, granting source/cache access, creating credentials, changing global yt-dlp format settings, or converting existing library content requires approval of a concrete scope. None has been performed or requested in this pass. The app-only route does not require those server changes.

## Primary sources checked

- [Tube Archivist format settings](https://docs.tubearchivist.com/settings/application/#download-format)
- [Tube Archivist ingestion options](https://github.com/tubearchivist/tubearchivist/blob/master/backend/download/src/yt_dlp_handler.py)
- [Queue input serializers](https://github.com/tubearchivist/tubearchivist/blob/master/backend/download/serializers.py)
- [Video API routes](https://github.com/tubearchivist/tubearchivist/blob/master/backend/video/urls.py)
- [VideoLAN transcoder implementation](https://github.com/videolan/vlckit/blob/master/Sources/sout/VLCTranscoder.m)
- [VLC 3 stream-output conversion bounds](https://github.com/videolan/vlc/blob/3.0.x/modules/stream_out/transcode/transcode.c)
- [Apple AVAssetExportSession](https://developer.apple.com/documentation/avfoundation/avassetexportsession)

The actual bundled 3.7.3 headers/binary and Simulator output, rather than current upstream VLC implementation alone, establish the tested modules' behavior.
