#!/usr/bin/env bash
# Patch OTAs with upstream Magisk when a preinit device is configured.

MAGISK_PREINIT_DEVICE=${MAGISK_PREINIT_DEVICE:-}
# renovate: datasource=github-releases packageName=topjohnwu/Magisk versioning=semver-coerced
DEFAULT_MAGISK_VERSION=v30.7
MAGISK_VERSION=${MAGISK_VERSION:-${DEFAULT_MAGISK_VERSION}}

SKIP_MAGISK=${SKIP_MAGISK:-'false'}

function flavor_magisk_enabled() {
  [[ -n "$MAGISK_PREINIT_DEVICE" && "$SKIP_MAGISK" != 'true' ]]
}

function flavor_magisk_asset_infix() {
  echo "magisk-${MAGISK_VERSION}"
}

function flavor_magisk_prepare() {
  if [[ "$MAGISK_VERSION" == 'latest' ]]; then
    local releaseUrl
    releaseUrl=$(curl --fail -sL -I -o /dev/null -w '%{url_effective}' \
      https://github.com/topjohnwu/Magisk/releases/latest) || return
    MAGISK_VERSION=${releaseUrl##*/}
  fi
  print "Magisk version: $MAGISK_VERSION"
}

function flavor_magisk_build() {
  local apk=".tmp/magisk-${MAGISK_VERSION}.apk"
  [[ -s "$apk" ]] && return 0
  mkdir -p .tmp || return
  curl --fail -sLo "${apk}.tmp" \
    "https://github.com/topjohnwu/Magisk/releases/download/${MAGISK_VERSION}/Magisk-${MAGISK_VERSION}.apk" || return
  mv -- "${apk}.tmp" "$apk" || return
}

function flavor_magisk_patch_args() {
  local -n magisk_args="$1"
  magisk_args+=("--patch-arg=--magisk" "--patch-arg" ".tmp/magisk-${MAGISK_VERSION}.apk")
  magisk_args+=("--patch-arg=--magisk-preinit-device" "--patch-arg" "$MAGISK_PREINIT_DEVICE")
}
