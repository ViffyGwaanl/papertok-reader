#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "Usage: $(basename "$0") <commit-ish>"
  exit 2
fi

commit="$1"
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Ensure UTF-8 locale for fastlane
export LANG="${LANG:-en_US.UTF-8}"
export LC_ALL="${LC_ALL:-en_US.UTF-8}"

cd "$repo_root"

git fetch --all --prune

short="$(git rev-parse --short "$commit")"
wt_dir="/tmp/papertok-tf-${short}-$(date +%Y%m%d%H%M%S)"

# Create a detached worktree so we don't disturb your current working tree
mkdir -p "$wt_dir"
git worktree add --detach "$wt_dir" "$commit" >/dev/null

cleanup() {
  set +e
  git -C "$repo_root" worktree remove --force "$wt_dir" >/dev/null 2>&1 || true
  git -C "$repo_root" worktree prune >/dev/null 2>&1 || true
}
trap cleanup EXIT

echo "==> Worktree ready: $wt_dir ($(git -C "$wt_dir" rev-parse --short HEAD))"

# Overlay release infra & iOS fixes from your current working tree
# (fastlane lanes, ExportOptions, ShareExtension version sync fixes, etc.)
overlay_paths=(
  "ios/fastlane"
  "ios/ExportOptions-AppStore.plist"
  "ios/ExportOptions-AppStore-Manual.plist"
  "ios/Flutter/ShareExtension-Debug.xcconfig"
  "ios/Flutter/ShareExtension-Profile.xcconfig"
  "ios/Flutter/ShareExtension-Release.xcconfig"
  "ios/ShareExtension/Info.plist"
  "scripts/tf_from_commit.sh"
)

for p in "${overlay_paths[@]}"; do
  if [[ -e "$repo_root/$p" ]]; then
    mkdir -p "$(dirname "$wt_dir/$p")"
    if [[ -d "$repo_root/$p" ]]; then
      mkdir -p "$wt_dir/$p"
      rsync -a "$repo_root/$p/" "$wt_dir/$p/"
    else
      rsync -a "$repo_root/$p" "$wt_dir/$p"
    fi
  fi
done

# Copy local secrets if present (gitignored)
if [[ -f "$repo_root/ios/fastlane/.env" ]]; then
  rsync -a "$repo_root/ios/fastlane/.env" "$wt_dir/ios/fastlane/.env"
fi

cd "$wt_dir/ios"

# Bundler install can be flaky when using ephemeral worktrees (re-downloading gems each run).
# Use a stable cache path in the OpenClaw workspace + add retries.
# NOTE: repo has ios/.bundle/config pinning path=vendor/bundle; override it per-worktree.
BUNDLE_CACHE_BASE="/Users/gwaanl/.openclaw/workspace/cache/bundler"
BUNDLE_CACHE_PATH="$BUNDLE_CACHE_BASE/papertok-reader/ios/ruby-2.6"
mkdir -p "$BUNDLE_CACHE_PATH"

bundle config set --local path "$BUNDLE_CACHE_PATH" >/dev/null
bundle install --jobs 4 --retry 3
bundle exec fastlane ios release_app_store
