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

# Prefer user-installed Bundler (Gemfile.lock requires a newer Bundler than macOS ships).
if [[ -d "${HOME}/.gem/ruby/2.6.0/bin" ]]; then
  export PATH="${HOME}/.gem/ruby/2.6.0/bin:${PATH}"
fi

cd "$repo_root"

# Avoid long/hanging network fetches when the commit already exists locally.
# Also disable interactive credential prompts (fail fast instead of hanging).
export GIT_TERMINAL_PROMPT=0
if ! git cat-file -e "${commit}^{commit}" 2>/dev/null; then
  git -c http.version=HTTP/1.1 fetch --all --prune --quiet
fi

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
  "Fastfile"
  "ios/fastlane"
  "ios/Gemfile"
  "ios/Gemfile.lock"
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

# When pub.dev is unavailable, allow a fully offline build by reusing the current
# working tree's resolved packages + generated iOS config.
if [[ "${FLUTTER_NO_PUB:-0}" == "true" || "${SKIP_PUB_GET:-0}" == "true" ]]; then
  echo "==> FLUTTER_NO_PUB=true: overlaying .dart_tool + generated Flutter iOS config"

  extra_overlay_paths=(
    ".dart_tool"
    ".flutter-plugins-dependencies"
    "ios/Flutter/Generated.xcconfig"
    "ios/Flutter/flutter_export_environment.sh"
    "ios/Runner/GeneratedPluginRegistrant.h"
    "ios/Runner/GeneratedPluginRegistrant.m"
  )

  for p in "${extra_overlay_paths[@]}"; do
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

  # Also overlay codegen outputs that are usually not tracked by git.
  # Without these, a detached worktree will miss Freezed/JsonSerializable outputs.
  echo "==> FLUTTER_NO_PUB=true: overlaying codegen outputs (.g.dart/.freezed.dart/.gr.dart/.gen.dart/.mocks.dart)"
  mkdir -p "$wt_dir/lib"
  rsync -a --prune-empty-dirs \
    --include='*/' \
    --include='*.g.dart' \
    --include='*.freezed.dart' \
    --include='*.gr.dart' \
    --include='*.gen.dart' \
    --include='*.mocks.dart' \
    --exclude='*' \
    "$repo_root/lib/" "$wt_dir/lib/"
fi

# Patch worktree Xcode project to force manual App Store signing for Release/Profile,
# avoiding Xcode Automatic signing (which can trigger Development cert/account issues).
patch_signing() {
  local pbxproj="$1"

  python3 - "$pbxproj" <<'PY'
import re, sys, pathlib
pbx = pathlib.Path(sys.argv[1])
text = pbx.read_text(encoding='utf-8')

IND = "\n\t\t\t\t"

def set_or_add(body: str, key: str, value: str, quoted: bool = False) -> str:
    if quoted:
        line = f"{IND}{key} = \"{value}\";"
    else:
        line = f"{IND}{key} = {value};"
    pat = re.compile(rf"\n\t\t\t\t{re.escape(key)} = .*?;", re.S)
    if pat.search(body):
        body = pat.sub(line, body)
    else:
        # insert before the end of buildSettings block
        body = body.rstrip("\n") + line + "\n"
    return body


def patch_config(text: str, config_name: str, bundle_id: str, profile_spec: str) -> tuple[str, int]:
    # Match any XCBuildConfiguration block with buildSettings containing the bundle id
    pat = re.compile(
        rf"(isa = XCBuildConfiguration;\n\t\t\t(?:baseConfigurationReference = .*?;\n\t\t\t)?buildSettings = \{{)(.*?)(\n\t\t\t\}};\n\t\t\tname = {re.escape(config_name)};\n\t\t\}};)",
        re.S,
    )
    count = 0
    out = text
    offset = 0
    for m in list(pat.finditer(text)):
        body = m.group(2)
        if f"PRODUCT_BUNDLE_IDENTIFIER = {bundle_id};" not in body:
            continue
        new = body
        new = set_or_add(new, "CODE_SIGN_STYLE", "Manual", quoted=False)
        new = set_or_add(new, "CODE_SIGN_IDENTITY", "Apple Distribution", quoted=True)
        new = set_or_add(new, "\"CODE_SIGN_IDENTITY[sdk=iphoneos*]\"", "Apple Distribution", quoted=True)
        new = set_or_add(new, "PROVISIONING_PROFILE_SPECIFIER", profile_spec, quoted=True)
        new = set_or_add(new, "\"PROVISIONING_PROFILE_SPECIFIER[sdk=iphoneos*]\"", profile_spec, quoted=True)
        # keep DEVELOPMENT_TEAM unchanged (already set)

        if new != body:
            out = out[:m.start(2)+offset] + new + out[m.end(2)+offset:]
            offset += len(new) - len(body)
            count += 1
    return out, count

changed = 0
for cfg in ("Release", "Profile"):
    text, c = patch_config(text, cfg, "ai.papertok.paperreader", "match AppStore ai.papertok.paperreader")
    changed += c
    text, c = patch_config(text, cfg, "ai.papertok.paperreader.shareExtension", "match AppStore ai.papertok.paperreader.shareExtension")
    changed += c

if changed <= 0:
    print("signing_patch: FAILED (no matching Release/Profile blocks found)", file=sys.stderr)
    sys.exit(2)

pbx.write_text(text, encoding='utf-8')
print(f"signing_patch: applied to {changed} build configuration block(s)")
PY

  # Verify we really patched the expected keys (fail fast instead of building wrong)
  if ! grep -q 'PROVISIONING_PROFILE_SPECIFIER = "match AppStore ai.papertok.paperreader";' "$pbxproj"; then
    echo "signing_patch: verification failed for Runner" >&2
    return 2
  fi
  if ! grep -q 'PROVISIONING_PROFILE_SPECIFIER = "match AppStore ai.papertok.paperreader.shareExtension";' "$pbxproj"; then
    echo "signing_patch: verification failed for shareExtension" >&2
    return 2
  fi
}

if [[ "${FORCE_MANUAL_SIGNING:-0}" == "1" ]]; then
  patch_signing "$wt_dir/ios/Runner.xcodeproj/project.pbxproj"
else
  echo "signing_patch: skipped (FORCE_MANUAL_SIGNING!=1)"
fi

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
