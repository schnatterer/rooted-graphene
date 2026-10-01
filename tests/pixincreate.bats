#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
  cd "$BATS_TEST_TMPDIR"
  mkdir -p flavors .tmp
  cp "$REPO_ROOT/flavors/pixincreate.sh" "$REPO_ROOT/flavors/magisk.sh" flavors/
  FLAVOR_DIR="$BATS_TEST_TMPDIR/flavors"
  DEBUG=''
  NO_COLOR=1
  MAGISK_VERSION=v29.1
  PIXINCREATE_VERSION=v30.7
  MAGISK_PREINIT_DEVICE=persist
  SKIP_MAGISK=true
  SKIP_PIXINCREATE=true
  SKIP_ROOTLESS=true
  SKIP_MODULES=false
  UPLOAD_TEST_OTA=false
  GITHUB_REPO=''
  GITHUB_TOKEN=''
  DEVICE_ID=oriole
  OTA_VERSION=2026010100
  # shellcheck disable=SC1090
  source "$REPO_ROOT/rooted-ota.sh"
  declare -gA POTENTIAL_ASSETS=()
  declare -ga FLAVOR_PLUGINS=() FLAVOR_PLUGINS_ENABLED=()
  printf 'legacy fork APK payload\n' > legacy.apk
  printf 'current fork APK payload\n' > fork.apk
  printf 'upstream APK payload\n' > upstream.apk
  digest() { printf 'sha256:%s' "$(sha256sum "$1" | cut -d ' ' -f 1)"; }
  cat > legacy-release.json <<EOF
{"tag_name":"v30.7","assets":[
  {"name":"app-debug.apk","state":"uploaded","browser_download_url":"https://example.invalid/debug.apk"},
  {"name":"app-release.apk","state":"uploaded","digest":"$(digest legacy.apk)","browser_download_url":"https://github.com/pixincreate/Magisk/releases/download/v30.7/app-release.apk"}
]}
EOF
  cat > current-release.json <<EOF
{"tag_name":"v31.0-3","assets":[
  {"name":"app-debug.apk","state":"uploaded","browser_download_url":"https://example.invalid/debug.apk"},
  {"name":"Magisk-v31.0-3.apk","state":"uploaded","digest":"$(digest fork.apk)","browser_download_url":"https://github.com/pixincreate/Magisk/releases/download/v31.0-3/Magisk-v31.0-3.apk"},
  {"name":"SHA256SUMS","state":"uploaded","browser_download_url":"https://example.invalid/SHA256SUMS"}
]}
EOF
  LATEST_RELEASE=current-release.json
  RELEASE_STATUS=0
  DOWNLOAD_STATUS=0
  curl() {
    local destination='' url='' payload=''
    while [[ "$#" -gt 0 ]]; do
      case "$1" in
        -sLo|-sSLo|-o) destination="$2"; shift ;;
        https://*) url="$1" ;;
      esac
      shift
    done
    case "$url" in
      https://api.github.com/repos/pixincreate/Magisk/releases/*)
        [[ "$RELEASE_STATUS" -eq 0 ]] || return "$RELEASE_STATUS"
        case "$url" in
          */latest) cat "$LATEST_RELEASE" ;;
          */tags/v30.7) cat legacy-release.json ;;
          */tags/v31.0-3) cat current-release.json ;;
          *) return 98 ;;
        esac
        return ;;
      https://github.com/topjohnwu/Magisk/releases/latest)
        printf '%s' 'https://github.com/topjohnwu/Magisk/releases/tag/v30.7'
        return ;;
      https://github.com/pixincreate/Magisk/releases/download/v30.7/app-release.apk)
        payload=legacy.apk ;;
      https://github.com/pixincreate/Magisk/releases/download/v31.0-3/Magisk-v31.0-3.apk)
        payload=fork.apk ;;
      https://github.com/topjohnwu/Magisk/releases/download/v30.7/Magisk-v30.7.apk)
        payload=upstream.apk ;;
      *) return 98 ;;
    esac
    [[ -n "$destination" ]] || return 97
    if [[ "$DOWNLOAD_STATUS" -ne 0 ]]; then
      printf 'partial' > "$destination"
      return "$DOWNLOAD_STATUS"
    fi
    cp "$payload" "$destination"
  }
  git() {
    case "$1" in
      rev-parse) printf 'abc1234\n' ;;
      status) return 0 ;;
      *) return 99 ;;
    esac
  }
}

@test "pixincreate requires opt-in and a preinit device" {
  unset SKIP_PIXINCREATE
  loadFlavorPlugins
  prepareFlavorPlugins
  [ "${#FLAVOR_PLUGINS_ENABLED[@]}" -eq 0 ]

  SKIP_PIXINCREATE=''
  loadFlavorPlugins
  prepareFlavorPlugins
  [ "${#FLAVOR_PLUGINS_ENABLED[@]}" -eq 0 ]

  SKIP_PIXINCREATE=false
  MAGISK_PREINIT_DEVICE=''
  prepareFlavorPlugins
  [ "${#FLAVOR_PLUGINS_ENABLED[@]}" -eq 0 ]

  MAGISK_PREINIT_DEVICE=persist
  prepareFlavorPlugins
  [ "${FLAVOR_PLUGINS_ENABLED[*]}" = pixincreate ]

  SKIP_PIXINCREATE=true
  prepareFlavorPlugins
  [ "${#FLAVOR_PLUGINS_ENABLED[@]}" -eq 0 ]

  SKIP_PIXINCREATE=1
  prepareFlavorPlugins
  [ "${FLAVOR_PLUGINS_ENABLED[*]}" = pixincreate ]
}

@test "pinned fork version selects its legacy release APK independently of Magisk" {
  SKIP_PIXINCREATE=false
  MAGISK_PREINIT_DEVICE='device with spaces'
  loadFlavorPlugins
  prepareFlavorPlugins
  checkBuildNecessary
  [ "$MAGISK_VERSION" = v29.1 ]
  [ "${#POTENTIAL_ASSETS[@]}" -eq 1 ]
  [ "${POTENTIAL_ASSETS[pixincreate]}" = oriole-2026010100-abc1234-pixincreate-v30.7.zip ]
  buildFlavorPlugins
  local args=(existing)
  flavor_pixincreate_patch_args args
  [ "${#args[@]}" -eq 7 ]
  [ "${args[0]}" = existing ]
  [ "${args[1]}" = --patch-arg=--magisk ]
  [ "${args[2]}" = --patch-arg ]
  cmp "${args[3]}" legacy.apk
  [ "${args[4]}" = --patch-arg=--magisk-preinit-device ]
  [ "${args[5]}" = --patch-arg ]
  [ "${args[6]}" = 'device with spaces' ]
}

@test "latest fork resolves its own release and downloads the versioned APK" {
  SKIP_PIXINCREATE=false
  PIXINCREATE_VERSION=latest
  loadFlavorPlugins
  prepareFlavorPlugins
  checkBuildNecessary
  [ "$MAGISK_VERSION" = v29.1 ]
  [ "$PIXINCREATE_VERSION" = v31.0-3 ]
  [ "${POTENTIAL_ASSETS[pixincreate]}" = oriole-2026010100-abc1234-pixincreate-v31.0-3.zip ]
  buildFlavorPlugins
  cmp .tmp/pixincreate-v31.0-3.apk fork.apk
}

@test "failed fork release lookup propagates and leaves latest retryable" {
  SKIP_PIXINCREATE=false
  PIXINCREATE_VERSION=latest
  RELEASE_STATUS=22
  loadFlavorPlugins
  local result=0
  prepareFlavorPlugins || result=$?
  [ "$result" -eq 22 ]
  [ "$PIXINCREATE_VERSION" = latest ]
  [ ! -e .tmp/pixincreate-latest.apk ]

  RELEASE_STATUS=0
  prepareFlavorPlugins
  [ "$PIXINCREATE_VERSION" = v31.0-3 ]
}

@test "both latest flavors keep different release identities and APKs" {
  SKIP_MAGISK=false
  SKIP_PIXINCREATE=false
  MAGISK_VERSION=latest
  PIXINCREATE_VERSION=latest
  loadFlavorPlugins
  prepareFlavorPlugins
  checkBuildNecessary
  [ "$MAGISK_VERSION" = v30.7 ]
  [ "$PIXINCREATE_VERSION" = v31.0-3 ]
  [ "${POTENTIAL_ASSETS[magisk]}" = oriole-2026010100-abc1234-magisk-v30.7.zip ]
  [ "${POTENTIAL_ASSETS[pixincreate]}" = oriole-2026010100-abc1234-pixincreate-v31.0-3.zip ]
  buildFlavorPlugins
  cmp .tmp/magisk-v30.7.apk upstream.apk
  cmp .tmp/pixincreate-v31.0-3.apk fork.apk
}

@test "a release containing only the debug APK fails without resolving latest" {
  SKIP_PIXINCREATE=false
  PIXINCREATE_VERSION=latest
  jq '.assets |= map(select(.name == "app-debug.apk"))' current-release.json > debug-only.json
  LATEST_RELEASE=debug-only.json
  loadFlavorPlugins
  local result=0
  prepareFlavorPlugins || result=$?
  [ "$result" -ne 0 ]
  [ "$PIXINCREATE_VERSION" = latest ]
  [ -z "$PIXINCREATE_APK_URL" ]
}

@test "ambiguous release APKs fail instead of selecting an arbitrary download" {
  SKIP_PIXINCREATE=false
  PIXINCREATE_VERSION=latest
  jq '.assets += [{"name":"app-release.apk","state":"uploaded","browser_download_url":"https://example.invalid/other.apk"}]' \
    current-release.json > ambiguous.json
  LATEST_RELEASE=ambiguous.json
  loadFlavorPlugins
  local result=0
  prepareFlavorPlugins || result=$?
  [ "$result" -ne 0 ]
  [ "$PIXINCREATE_VERSION" = latest ]
  [ -z "$PIXINCREATE_APK_URL" ]
}

@test "fork caches are distinct from upstream and reused only for their version" {
  loadFlavorPlugins
  flavor_pixincreate_prepare
  cp upstream.apk .tmp/magisk-v30.7.apk
  flavor_pixincreate_build
  cmp .tmp/pixincreate-v30.7.apk legacy.apk
  cmp .tmp/magisk-v30.7.apk upstream.apk

  DOWNLOAD_STATUS=22
  flavor_pixincreate_build
  PIXINCREATE_VERSION=v31.0-3
  flavor_pixincreate_prepare
  run flavor_pixincreate_build
  [ "$status" -eq 22 ]
  [ ! -e .tmp/pixincreate-v31.0-3.apk ]
  cmp .tmp/pixincreate-v30.7.apk legacy.apk

  DOWNLOAD_STATUS=0
  flavor_pixincreate_build
  cmp .tmp/pixincreate-v31.0-3.apk fork.apk
  cmp .tmp/pixincreate-v30.7.apk legacy.apk
}

@test "empty cache is replaced only after a successful download" {
  loadFlavorPlugins
  flavor_pixincreate_prepare
  : > .tmp/pixincreate-v30.7.apk
  DOWNLOAD_STATUS=22
  run flavor_pixincreate_build
  [ "$status" -eq 22 ]
  [ ! -s .tmp/pixincreate-v30.7.apk ]

  DOWNLOAD_STATUS=0
  flavor_pixincreate_build
  cmp .tmp/pixincreate-v30.7.apk legacy.apk
  [ ! -e .tmp/pixincreate-v30.7.apk.tmp ]
}

@test "a download that does not match the published SHA-256 is rejected and not cached" {
  loadFlavorPlugins
  flavor_pixincreate_prepare
  printf 'tampered APK payload\n' > legacy.apk
  run flavor_pixincreate_build
  [ "$status" -eq 1 ]
  [ ! -e .tmp/pixincreate-v30.7.apk ]
  [ ! -e .tmp/pixincreate-v30.7.apk.tmp ]
}

@test "a cached APK with different content is replaced by the verified download" {
  loadFlavorPlugins
  flavor_pixincreate_prepare
  printf 'stale APK payload\n' > .tmp/pixincreate-v30.7.apk
  flavor_pixincreate_build
  cmp .tmp/pixincreate-v30.7.apk legacy.apk
}

@test "a release APK without a published SHA-256 cannot be selected" {
  SKIP_PIXINCREATE=false
  jq '(.assets[] | select(.name == "app-release.apk")) |= del(.digest)' legacy-release.json > release.next
  mv release.next legacy-release.json
  loadFlavorPlugins
  local result=0
  prepareFlavorPlugins || result=$?
  [ "$result" -ne 0 ]
  [ -z "$PIXINCREATE_APK_URL" ]
  [ -z "$PIXINCREATE_APK_SHA256" ]
}

@test "failed publication propagates without creating the final APK" {
  loadFlavorPlugins
  flavor_pixincreate_prepare
  mv() { return 23; }
  run flavor_pixincreate_build
  [ "$status" -eq 23 ]
  [ ! -e .tmp/pixincreate-v30.7.apk ]
}
