#!/bin/bash
set -euo pipefail
repo_dir="$(cd "$(dirname "$0")/.." && pwd)"
derived_dir="${1:-$repo_dir/.build/mac}"
xcodebuild build \
  -project "$repo_dir/Fold.xcodeproj" \
  -scheme Fold -configuration Release \
  -destination 'platform=macOS,variant=Mac Catalyst' \
  -derivedDataPath "$derived_dir"
printf '\nBuilt Mac app: %s/Build/Products/Release-maccatalyst/Fold.app\n' "$derived_dir"
