#!/bin/sh
# Tiny synthetic clips for OfflineConversionFeasibilityTests; no owner media.
set -eu
cd "$(dirname "$0")/../.."
output=TAClientTests/Fixtures
ffmpeg -n -v error -f lavfi -i 'testsrc2=size=320x180:rate=24:duration=1' -f lavfi -i 'sine=frequency=440:sample_rate=48000:duration=1' -c:v libx264 -pix_fmt yuv420p -profile:v main -level 3.0 -c:a aac -ac 2 -movflags +faststart "$output/conversion-h264-aac.mp4"
ffmpeg -n -v error -f lavfi -i 'testsrc2=size=320x180:rate=24:duration=1' -f lavfi -i 'sine=frequency=440:sample_rate=48000:duration=1' -c:v libvpx-vp9 -deadline realtime -cpu-used 8 -c:a libopus -ac 2 "$output/conversion-vp9-opus.webm"
ffmpeg -n -v error -i "$output/conversion-vp9-opus.webm" -c copy -movflags +faststart "$output/conversion-vp9-opus.mp4"
ffmpeg -n -v error -f lavfi -i 'testsrc2=size=320x180:rate=24:duration=1' -f lavfi -i 'sine=frequency=440:sample_rate=48000:duration=1' -c:v libsvtav1 -preset 12 -svtav1-params lp=1 -crf 40 -c:a libopus -ac 2 -movflags +faststart "$output/conversion-av1-opus.mp4"
