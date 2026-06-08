#!/usr/bin/env bash
#
# release_from_commit.sh — single-shot orchestrator for a papertok-reader release.
#
# Given one commit SHA, this script:
#   1. starts iOS TestFlight upload in background (via scripts/tf_from_commit.sh);
#   2. waits for fastlane to allocate the next monotonic build number;
#   3. fans out Android APK + macOS .app builds in parallel using the same
#      build number;
#   4. archives all artifacts + logs under ARTIFACT_ROOT/<shortsha>-<ts>/;
#   5. creates a GitHub Release with the APK ONLY when iOS + Android + macOS
#      all succeed (so a published Release implies a usable build everywhere);
#   6. on --external, polls ASC for processingState=VALID and runs
#      `fastlane pilot distribute` to push to the EX External group and
#      submit Beta App Review.
#
# Failure policy:
#   • iOS failure  → Android + macOS still run (you can still sideload),
#                    GH Release is skipped, --external is skipped.
#   • Android fail → GH Release skipped.
#   • macOS fail   → GH Release skipped (a release implies all 3 platforms work).
#
# A POSIX file lock (mkdir-based) prevents concurrent runs from corrupting the
# fastlane build-number state file.

set -euo pipefail

# ────────── defaults ──────────

EXTERNAL=false
SKIP_IOS=false
SKIP_ANDROID=false
SKIP_MACOS=false
NO_PUB=true
COMMIT=""

REPO_OWNER="ViffyGwaanl"
REPO_NAME="papertok-reader"
APP_BUNDLE="ai.papertok.paperreader"
ASC_APPLE_ID="6759330889"
EXTERNAL_GROUP="EX External"

state_file="/Users/gwaanl/.openclaw/workspace/state/papertok-reader/last_testflight_build_number.txt"
asc_state_script="/Users/gwaanl/.openclaw/workspace/skills/papertok-ios-testflight/scripts/asc_build_state.js"
asc_api_key_path="/tmp/asc_api_key_papertok.json"
ARTIFACT_ROOT="${ARTIFACT_ROOT:-/Users/gwaanl/.openclaw/workspace/artifacts/papertok-reader}"
LOCK_DIR="${LOCK_DIR:-/tmp/papertok-reader-release.lock}"

# ────────── arg parsing ──────────

usage() {
  cat <<USAGE
Usage: $(basename "$0") [options] <commit-ish>

Options:
  --external              Also submit to "$EXTERNAL_GROUP" + Beta App Review.
                          (Default: off; just upload to TestFlight.)
  --skip-ios              Skip iOS phase entirely.
  --skip-android          Skip Android phase entirely.
  --skip-macos            Skip macOS phase entirely.
  --with-pub              Run \`flutter pub get\` (default: skip, FLUTTER_NO_PUB=true).
  -h, --help              Show this help.

Environment overrides:
  ARTIFACT_ROOT           Where to drop the per-release artifact directory.
                          Default: $ARTIFACT_ROOT
  LOCK_DIR                Cross-process file lock path.
                          Default: $LOCK_DIR

Example:
  $(basename "$0") 5cf55233              # iOS TF + Android + macOS, no external
  $(basename "$0") --external HEAD       # full pipeline incl. external review
  $(basename "$0") --skip-macos abc1234  # iOS + Android only
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --external)     EXTERNAL=true;     shift ;;
    --skip-ios)     SKIP_IOS=true;     shift ;;
    --skip-android) SKIP_ANDROID=true; shift ;;
    --skip-macos)   SKIP_MACOS=true;   shift ;;
    --with-pub)     NO_PUB=false;      shift ;;
    -h|--help)      usage; exit 0 ;;
    -*)             echo "Unknown flag: $1" >&2; usage >&2; exit 2 ;;
    *)              COMMIT="$1";       shift ;;
  esac
done

if [[ -z "$COMMIT" ]]; then
  echo "Missing required <commit-ish>." >&2
  usage >&2
  exit 2
fi

# ────────── resolve repo + commit + version ──────────

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

export GIT_TERMINAL_PROMPT=0
if ! git cat-file -e "${COMMIT}^{commit}" 2>/dev/null; then
  echo "==> Fetching commit '$COMMIT' from origin…"
  git -c http.version=HTTP/1.1 fetch --all --prune --quiet
fi

full_sha="$(git rev-parse "${COMMIT}^{commit}")"
short_sha="$(git rev-parse --short "$full_sha")"
version_name="$(git show "$full_sha:pubspec.yaml" | awk -F'[: +]' '/^version:/ {print $3; exit}')"

# Will be filled in by Phase 1 (iOS) or fallback from pubspec.
build_number=""

# ────────── lock ──────────

if ! mkdir "$LOCK_DIR" 2>/dev/null; then
  cat >&2 <<MSG
❌ Another release run already holds the lock at $LOCK_DIR.

If you are sure no other run is in progress, remove it manually:
  rm -rf "$LOCK_DIR"
MSG
  exit 1
fi

# ────────── artifact dir ──────────

ts="$(date +%Y%m%d%H%M%S)"
artifact_dir="$ARTIFACT_ROOT/$short_sha-$ts"
log_dir="$artifact_dir/logs"
mkdir -p "$log_dir"

# Mirror everything we print to a session log so it's in the artifact dir too.
session_log="$log_dir/release_from_commit.log"
exec > >(tee -a "$session_log") 2>&1

cleanup_paths=()
on_exit() {
  set +e
  if [[ ${#cleanup_paths[@]} -gt 0 ]]; then
    for p in "${cleanup_paths[@]}"; do
      if [[ -d "$p" ]]; then
        git worktree remove --force "$p" >/dev/null 2>&1
        git worktree prune >/dev/null 2>&1
      fi
    done
  fi
  rmdir "$LOCK_DIR" 2>/dev/null || true
}
trap on_exit EXIT

# ────────── plan summary ──────────

cat <<SUMMARY
==> Release: $short_sha (v$version_name)
==> Artifacts: $artifact_dir
==> Platforms: ios=$([[ $SKIP_IOS == true ]] && echo SKIP || echo go) android=$([[ $SKIP_ANDROID == true ]] && echo SKIP || echo go) macos=$([[ $SKIP_MACOS == true ]] && echo SKIP || echo go)
==> External: $EXTERNAL
==> Pub get: $([[ $NO_PUB == true ]] && echo skip || echo run)
SUMMARY

# ────────── Phase 1: iOS (background) ──────────

ios_pid=""
ios_rc=0
ios_log="$log_dir/ios.log"
prev_build_number="$(cat "$state_file" 2>/dev/null || echo 0)"

if [[ "$SKIP_IOS" != "true" ]]; then
  echo ""
  echo "==> Phase 1: launching iOS TestFlight pipeline (background)"
  FLUTTER_NO_PUB="$NO_PUB" "$repo_root/scripts/tf_from_commit.sh" "$full_sha" \
    >"$ios_log" 2>&1 &
  ios_pid=$!
  echo "    PID=$ios_pid  log=$ios_log"

  # Wait up to 12 minutes for fastlane to write a new build number into the
  # state file. (Archive + match + IPA build dominates this delay.)
  echo "==> Phase 1: waiting for fastlane to assign next build number…"
  for _ in $(seq 1 240); do
    cur="$(cat "$state_file" 2>/dev/null || echo 0)"
    if [[ "$cur" != "$prev_build_number" ]]; then
      build_number="$cur"
      break
    fi
    if ! kill -0 "$ios_pid" 2>/dev/null; then
      # iOS died before writing — record the rc and fall through.
      set +e
      wait "$ios_pid"
      ios_rc=$?
      set -e
      echo "❌ iOS process exited (rc=$ios_rc) before assigning a build number."
      break
    fi
    sleep 3
  done

  if [[ -z "$build_number" && "$ios_rc" == "0" ]]; then
    echo "❌ Timed out waiting for fastlane to write build number."
    kill "$ios_pid" 2>/dev/null || true
    set +e
    wait "$ios_pid"
    ios_rc=$?
    set -e
  fi
fi

if [[ -z "$build_number" ]]; then
  # Fall back to whatever pubspec.yaml said at the target commit.
  build_number="$(git show "$full_sha:pubspec.yaml" | awk -F'+' '/^version:/ {print $2; exit}')"
  echo "==> build_number fallback from pubspec: $build_number"
else
  echo "==> build_number=$build_number"
fi

# ────────── Phase 2: Android + macOS (parallel) ──────────

# Build root: if HEAD already points at the target commit, reuse the current
# tree to avoid the cost of a second worktree + flutter pub get. Otherwise
# create a detached worktree at /tmp.
if [[ "$full_sha" == "$(git rev-parse HEAD)" ]]; then
  build_root="$repo_root"
  echo ""
  echo "==> Phase 2: HEAD matches target — building Android/macOS in current tree"
else
  build_root="/tmp/papertok-rel-${short_sha}-${ts}"
  echo ""
  echo "==> Phase 2: creating worktree for Android/macOS at $build_root"
  git worktree add --detach "$build_root" "$full_sha" >/dev/null
  cleanup_paths+=("$build_root")

  if [[ "$NO_PUB" != "true" ]]; then
    (cd "$build_root" && flutter pub get) >>"$log_dir/pub_get.log" 2>&1 \
      || echo "⚠️ pub get failed (continuing) — see $log_dir/pub_get.log"
  fi
fi

android_pid=""; android_rc=0; android_log="$log_dir/android.log"
macos_pid="";   macos_rc=0;   macos_log="$log_dir/macos.log"

if [[ "$SKIP_ANDROID" != "true" ]]; then
  (cd "$build_root" && flutter build apk --release --build-number="$build_number") \
    >"$android_log" 2>&1 &
  android_pid=$!
  echo "    Android PID=$android_pid  log=$android_log"
fi

if [[ "$SKIP_MACOS" != "true" ]]; then
  (cd "$build_root" && flutter build macos --release --build-number="$build_number") \
    >"$macos_log" 2>&1 &
  macos_pid=$!
  echo "    macOS   PID=$macos_pid  log=$macos_log"
fi

# Wait for everything. We deliberately don't propagate failures here; the
# summary + exit code at the end reports per-platform status.
set +e
if [[ -n "$ios_pid" && "$ios_rc" == "0" ]]; then
  echo "==> Waiting for iOS (this is usually the longest)…"
  wait "$ios_pid"
  ios_rc=$?
fi
if [[ -n "$android_pid" ]]; then
  echo "==> Waiting for Android…"
  wait "$android_pid"
  android_rc=$?
fi
if [[ -n "$macos_pid" ]]; then
  echo "==> Waiting for macOS…"
  wait "$macos_pid"
  macos_rc=$?
fi
set -e

echo "==> iOS rc=$ios_rc  Android rc=$android_rc  macOS rc=$macos_rc"

# ────────── Phase 3: archive ──────────

echo ""
echo "==> Phase 3: archiving artifacts → $artifact_dir"

apk_src="$build_root/build/app/outputs/flutter-apk/app-release.apk"
apk_dst="$artifact_dir/papertok-reader-${version_name}-${build_number}.apk"
if [[ "$android_rc" == "0" && -f "$apk_src" ]]; then
  cp "$apk_src" "$apk_dst"
  (cd "$artifact_dir" && shasum -a 256 "$(basename "$apk_dst")" > CHECKSUMS.txt)
  echo "    + $(basename "$apk_dst") ($(du -h "$apk_dst" | awk '{print $1}'))"
fi

macos_app_src="$build_root/build/macos/Build/Products/Release/PaperTok Reader.app"
if [[ "$macos_rc" == "0" && -d "$macos_app_src" ]]; then
  cp -R "$macos_app_src" "$artifact_dir/"
  echo "    + PaperTok Reader.app"
fi

ipa_src="$build_root/build/ios/ipa"
if [[ "$ios_rc" == "0" && -d "$ipa_src" ]]; then
  # Best-effort: copy the IPA if it still exists (worktree from tf may have
  # been cleaned). Not fatal if missing.
  cp "$ipa_src"/*.ipa "$artifact_dir/" 2>/dev/null \
    && echo "    + $(ls "$ipa_src"/*.ipa | xargs -n1 basename)"
fi

# ────────── Phase 4: GitHub Release ──────────

gh_release_url=""
should_release=true
if [[ "$SKIP_IOS" != "true" && "$ios_rc" != "0" ]]; then should_release=false; fi
if [[ "$SKIP_ANDROID" != "true" && "$android_rc" != "0" ]]; then should_release=false; fi
if [[ "$SKIP_MACOS" != "true" && "$macos_rc" != "0" ]]; then should_release=false; fi
if [[ "$SKIP_ANDROID" == "true" ]]; then should_release=false; fi
if [[ ! -f "$apk_dst" ]]; then should_release=false; fi

if [[ "$should_release" == "true" ]]; then
  tag="android-v${version_name}-${build_number}"
  echo ""
  echo "==> Phase 4: creating GitHub Release $tag"

  notes_file="$artifact_dir/release_notes.md"
  commit_subject="$(git log -1 --format=%s "$full_sha")"
  cat > "$notes_file" <<EOF
## Build

- **Version:** ${version_name}+${build_number}
- **Commit:** \`${short_sha}\` — ${commit_subject}
- **Signing:** debug keystore (\`androiddebugkey\`). **Not suitable for Play Store.** Sideload only; updates require the same debug-signing identity.

## Assets

- \`papertok-reader-${version_name}-${build_number}.apk\` — universal Android APK
- \`CHECKSUMS.txt\` — sha256
EOF

  if gh release create "$tag" \
    --repo "$REPO_OWNER/$REPO_NAME" \
    --target "$full_sha" \
    --title "PaperTok Reader v${version_name} (build ${build_number}) — Android" \
    --prerelease \
    --notes-file "$notes_file" \
    "$apk_dst" "$artifact_dir/CHECKSUMS.txt" \
    >>"$log_dir/github_release.log" 2>&1; then
    gh_release_url="https://github.com/$REPO_OWNER/$REPO_NAME/releases/tag/$tag"
    echo "    ✅ $gh_release_url"
  else
    echo "    ⚠️ gh release create failed — see $log_dir/github_release.log"
  fi
else
  reasons=()
  [[ "$SKIP_ANDROID" == "true" ]] && reasons+=("Android skipped")
  [[ "$ios_rc" != "0" && "$SKIP_IOS" != "true" ]] && reasons+=("iOS rc=$ios_rc")
  [[ "$android_rc" != "0" && "$SKIP_ANDROID" != "true" ]] && reasons+=("Android rc=$android_rc")
  [[ "$macos_rc" != "0" && "$SKIP_MACOS" != "true" ]] && reasons+=("macOS rc=$macos_rc")
  [[ ! -f "$apk_dst" ]] && reasons+=("no APK at $apk_dst")
  echo ""
  echo "==> Phase 4: GH Release skipped (${reasons[*]})"
fi

# ────────── Phase 5: external review (opt-in) ──────────

asc_state="not-checked"
external_status="not-requested"

if [[ "$EXTERNAL" == "true" ]]; then
  if [[ "$ios_rc" != "0" ]]; then
    external_status="skipped (iOS rc=$ios_rc)"
  elif [[ ! -x "$asc_state_script" && ! -f "$asc_state_script" ]]; then
    external_status="skipped (no asc_build_state.js at $asc_state_script)"
  else
    echo ""
    echo "==> Phase 5: polling ASC for processingState=VALID (max 60min)"
    asc_log="$log_dir/asc_state.log"
    for i in $(seq 1 60); do
      out="$(node "$asc_state_script" \
        --bundle "$APP_BUNDLE" \
        --build "$build_number" \
        --env "$build_root/ios/fastlane/.env" 2>&1 || true)"
      echo "[$(date +%H:%M:%S) attempt $i]" >> "$asc_log"
      echo "$out" >> "$asc_log"
      if echo "$out" | grep -q "VALID"; then
        asc_state="VALID"
        break
      fi
      sleep 60
    done

    if [[ "$asc_state" == "VALID" ]]; then
      echo "==> Phase 5: pilot distribute → $EXTERNAL_GROUP"
      ext_log="$log_dir/external.log"
      ext_ok=false
      for attempt in 1 2 3 4 5; do
        echo "    attempt $attempt/5" | tee -a "$ext_log"
        if (cd "$build_root/ios" && bundle exec fastlane pilot distribute \
              --api_key_path "$asc_api_key_path" \
              --apple_id "$ASC_APPLE_ID" \
              --app_identifier "$APP_BUNDLE" \
              --app_platform ios \
              --groups "$EXTERNAL_GROUP" \
              --build_number "$build_number" \
              --app_version "$version_name" \
              --distribute_external true \
              --submit_beta_review true \
              --reject_build_waiting_for_review true) >>"$ext_log" 2>&1; then
          ext_ok=true
          break
        fi
        sleep 30
      done
      external_status=$([[ "$ext_ok" == "true" ]] && echo "submitted" || echo "FAILED after 5 attempts — see $ext_log")
    else
      external_status="skipped (ASC processing did not reach VALID in 60min)"
    fi
  fi
fi

# ────────── Summary ──────────

echo ""
echo "================ SUMMARY ================"
echo "Commit:        $short_sha (v${version_name}+${build_number})"
echo "Artifacts:     $artifact_dir"
ios_status="skipped"
[[ "$SKIP_IOS" != "true" ]] && ios_status=$([[ "$ios_rc" == "0" ]] && echo "uploaded to ASC" || echo "FAILED rc=$ios_rc")
echo "iOS:           $ios_status"
android_status="skipped"
[[ "$SKIP_ANDROID" != "true" ]] && android_status=$([[ "$android_rc" == "0" ]] && echo "APK built" || echo "FAILED rc=$android_rc")
echo "Android:       $android_status"
macos_status="skipped"
[[ "$SKIP_MACOS" != "true" ]] && macos_status=$([[ "$macos_rc" == "0" ]] && echo ".app built (unsigned)" || echo "FAILED rc=$macos_rc")
echo "macOS:         $macos_status"
echo "GH Release:    ${gh_release_url:-not created}"
[[ "$EXTERNAL" == "true" ]] && echo "External:      $external_status"
echo "Logs:          $log_dir"
echo "========================================="

# Exit non-zero if any requested platform failed.
overall=0
[[ "$SKIP_IOS"     != "true" && "$ios_rc"     != "0" ]] && overall=1
[[ "$SKIP_ANDROID" != "true" && "$android_rc" != "0" ]] && overall=1
[[ "$SKIP_MACOS"   != "true" && "$macos_rc"   != "0" ]] && overall=1
exit $overall
