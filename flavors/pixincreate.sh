#!/usr/bin/env bash
# Magisk fork with Zygisk support for GrapheneOS; enable with SKIP_PIXINCREATE=false.

MAGISK_PREINIT_DEVICE=${MAGISK_PREINIT_DEVICE:-}
# renovate: datasource=github-releases packageName=pixincreate/Magisk versioning=loose
DEFAULT_PIXINCREATE_VERSION=v30.7
PIXINCREATE_VERSION=${PIXINCREATE_VERSION:-${DEFAULT_PIXINCREATE_VERSION}}
PIXINCREATE_APK_URL=''
PIXINCREATE_APK_SHA256=''

SKIP_PIXINCREATE=${SKIP_PIXINCREATE:-'true'}

function flavor_pixincreate_enabled() {
  [[ -n "$MAGISK_PREINIT_DEVICE" && "$SKIP_PIXINCREATE" != 'true' ]]
}

function flavor_pixincreate_asset_infix() {
  echo "pixincreate-${PIXINCREATE_VERSION}"
}

function flavor_pixincreate_prepare() {
  local endpoint="tags/${PIXINCREATE_VERSION}" release asset
  if [[ "$PIXINCREATE_VERSION" == 'latest' ]]; then
    endpoint=latest
  fi
  release=$(curl --fail -sSL "https://api.github.com/repos/pixincreate/Magisk/releases/${endpoint}") || return
  asset=$(jq -er '
    .tag_name as $version |
    [.assets[] | select(.state == "uploaded" and
      (.name == ("Magisk-" + $version + ".apk") or .name == "app-release.apk"))] |
    if length != 1 then error("Expected one pixincreate release APK for " + $version)
    elif (.[0].digest // "" | test("^sha256:[0-9a-f]{64}$")) | not then
      error("Missing SHA-256 for pixincreate release APK " + $version)
    else [$version, .[0].browser_download_url, (.[0].digest | ltrimstr("sha256:"))] | @tsv end
  ' <<< "$release") || return
  IFS=$'\t' read -r PIXINCREATE_VERSION PIXINCREATE_APK_URL PIXINCREATE_APK_SHA256 <<< "$asset" || return
  print "pixincreate version: $PIXINCREATE_VERSION"
}

function flavor_pixincreate_build() {
  local target=".tmp/pixincreate-${PIXINCREATE_VERSION}.apk"
  if [[ -s "$target" ]] &&
      printf '%s  %s\n' "$PIXINCREATE_APK_SHA256" "$target" | sha256sum --check --status; then
    return 0
  fi
  mkdir -p .tmp || return
  curl --fail -sLo "$target.tmp" "$PIXINCREATE_APK_URL" || return
  if ! printf '%s  %s\n' "$PIXINCREATE_APK_SHA256" "$target.tmp" | sha256sum --check --status; then
    printRed "pixincreate ${PIXINCREATE_VERSION} APK does not match its published SHA-256"
    rm -f -- "$target.tmp"
    return 1
  fi
  mv -- "$target.tmp" "$target" || return
}

function flavor_pixincreate_patch_args() {
  local -n patchArgs="$1"
  patchArgs+=("--patch-arg=--magisk" "--patch-arg" ".tmp/pixincreate-${PIXINCREATE_VERSION}.apk")
  patchArgs+=("--patch-arg=--magisk-preinit-device" "--patch-arg" "$MAGISK_PREINIT_DEVICE")
}
