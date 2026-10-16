#!/bin/sh
# Tiny synthetic clips for OfflineConversionFeasibilityTests; no owner media.
set -eu
cd "$(dirname "$0")/../.."
output=TAClientTests/Fixtures
ffmpeg -n -v error -f lavfi -i 'testsrc2=size=320x180:rate=24:duration=1' -f lavfi -i 'sine=frequency=440:sample_rate=48000:duration=1' -c:v libx264 -pix_fmt yuv420p -profile:v main -level 3.0 -c:a aac -ac 2 -movflags +faststart "$output/conversion-h264-aac.mp4"
ffmpeg -n -v error -f lavfi -i 'testsrc2=size=320x180:rate=24:duration=1' -f lavfi -i 'sine=frequency=440:sample_rate=48000:duration=1' -c:v libvpx-vp9 -deadline realtime -cpu-used 8 -c:a libopus -ac 2 "$output/conversion-vp9-opus.webm"
ffmpeg -n -v error -i "$output/conversion-vp9-opus.webm" -c copy -movflags +faststart "$output/conversion-vp9-opus.mp4"
ffmpeg -n -v error -f lavfi -i 'testsrc2=size=320x180:rate=24:duration=1' -f lavfi -i 'sine=frequency=440:sample_rate=48000:duration=1' -c:v libsvtav1 -preset 12 -svtav1-params lp=1 -crf 40 -c:a libopus -ac 2 -movflags +faststart "$output/conversion-av1-opus.mp4"
ffmpeg -n -v error -f lavfi -i 'testsrc2=size=1280x720:rate=24:duration=30' -f lavfi -i 'sine=frequency=440:sample_rate=48000:duration=30' -c:v libvpx-vp9 -deadline realtime -cpu-used 8 -threads 2 -b:v 650k -c:a libopus -b:a 64k -ac 2 "$output/conversion-long-vp9.webm"
ffmpeg -n -v error -f lavfi -i 'testsrc2=size=1280x720:rate=24:duration=120' -f lavfi -i 'sine=frequency=440:sample_rate=48000:duration=120' -c:v libvpx-vp9 -deadline realtime -cpu-used 8 -threads 2 -b:v 650k -c:a libopus -b:a 64k -ac 2 "$output/conversion-two-minute-vp9.webm"
ffmpeg -n -v error -f lavfi -i 'testsrc2=size=320x180:rate=24:duration=8' -f lavfi -i 'sine=frequency=440:sample_rate=48000:duration=8' -c:v libx264 -b:v 300k -c:a libopus -ac 2 -movflags +faststart "$output/conversion-h264-opus.mp4"
ffmpeg -n -v error -f lavfi -i 'testsrc2=size=180x320:rate=24:duration=8' -an -c:v libvpx-vp9 -deadline realtime -cpu-used 8 -threads 2 -b:v 220k "$output/conversion-vertical-silent.webm"
ffmpeg -n -v error -f lavfi -i 'testsrc2=size=320x180:rate=24:duration=1' -an -c:v libx265 -pix_fmt yuv420p10le -x265-params 'pools=1:frame-threads=1:log-level=error' -color_primaries bt2020 -color_trc smpte2084 -colorspace bt2020nc -movflags +faststart "$output/conversion-high-bit-depth-hevc.mp4"
ffmpeg -n -v error -f lavfi -i 'testsrc2=size=320x180:rate=24:duration=1' -an -c:v libx265 -pix_fmt yuv420p10le -x265-params 'pools=1:frame-threads=1:log-level=error:colorprim=bt2020:transfer=smpte2084:colormatrix=bt2020nc' -tag:v hvc1 -movflags +faststart "$output/conversion-hdr-hevc.mp4"
