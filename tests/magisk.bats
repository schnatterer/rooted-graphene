#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
  cd "$BATS_TEST_TMPDIR"
  DEBUG=''
  NO_COLOR=1
  MAGISK_VERSION=v31.2
  MAGISK_PREINIT_DEVICE=persist
  SKIP_MAGISK=false
  SKIP_PIXINCREATE=true
  SKIP_ROOTLESS=true
  SKIP_MODULES=false
  UPLOAD_TEST_OTA=false
  GITHUB_REPO=''
  DEVICE_ID=shiba
  OTA_VERSION=2026081300
  # shellcheck disable=SC1090
  source "$REPO_ROOT/rooted-ota.sh"
  # shellcheck disable=SC1090
  source "$REPO_ROOT/flavors/magisk.sh"
  # Sourced declarations otherwise remain local to setup().
  declare -gA POTENTIAL_ASSETS=()
  declare -ga FLAVOR_PLUGINS=(magisk) FLAVOR_PLUGINS_ENABLED=()
  git() {
    if [[ "$1" == rev-parse ]]; then printf 'abc123\n'; fi
  }
  curl() { return 97; }
}

@test "Magisk selection requires preinit and honors only literal true skip" {
  unset SKIP_MAGISK
  # shellcheck disable=SC1090
  source "$REPO_ROOT/flavors/magisk.sh"
  prepareFlavorPlugins
  checkBuildNecessary
  [ "${POTENTIAL_ASSETS[magisk]+present}" = present ]

  MAGISK_PREINIT_DEVICE=''
  prepareFlavorPlugins
  checkBuildNecessary
  [ "${POTENTIAL_ASSETS[magisk]+present}" = '' ]

  MAGISK_PREINIT_DEVICE=persist
  SKIP_MAGISK=true
  prepareFlavorPlugins
  checkBuildNecessary
  [ "${POTENTIAL_ASSETS[magisk]+present}" = '' ]

  SKIP_MAGISK=TRUE
  prepareFlavorPlugins
  checkBuildNecessary
  [ "${POTENTIAL_ASSETS[magisk]+present}" = present ]
}

@test "explicit Magisk version determines release identity without a lookup" {
  prepareFlavorPlugins
  checkBuildNecessary
  [ "${POTENTIAL_ASSETS[magisk]}" = shiba-2026081300-abc123-magisk-v31.2.zip ]
}

@test "latest Magisk resolves before constructing release identity" {
  MAGISK_VERSION=latest
  curl() { printf '%s' 'https://github.com/topjohnwu/Magisk/releases/tag/v32.1'; }
  prepareFlavorPlugins
  checkBuildNecessary
  [ "${POTENTIAL_ASSETS[magisk]}" = shiba-2026081300-abc123-magisk-v32.1.zip ]
}

@test "failed latest resolution stops preparation and leaves version retryable" {
  MAGISK_VERSION=latest
  curl() {
    printf '%s' 'https://github.com/topjohnwu/Magisk/releases/tag/partial'
    return 23
  }
  local result=0
  prepareFlavorPlugins || result=$?
  [ "$result" -eq 23 ]
  [ "$MAGISK_VERSION" = latest ]

  curl() { printf '%s' 'https://github.com/topjohnwu/Magisk/releases/tag/v32.2'; }
  prepareFlavorPlugins
  checkBuildNecessary
  [ "${POTENTIAL_ASSETS[magisk]}" = shiba-2026081300-abc123-magisk-v32.2.zip ]
}

@test "Magisk replaces an empty cache and reuses the completed APK" {
  mkdir -p .tmp
  : > .tmp/magisk-v31.2.apk
  curl() { printf 'complete APK' > "$3"; }
  flavor_magisk_build
  [ "$(cat .tmp/magisk-v31.2.apk)" = 'complete APK' ]

  curl() { return 23; }
  flavor_magisk_build
  [ "$(cat .tmp/magisk-v31.2.apk)" = 'complete APK' ]
}

@test "failed Magisk download does not publish partial bytes and can be retried" {
  curl() {
    printf 'partial APK' > "$3"
    return 23
  }
  run flavor_magisk_build
  [ "$status" -eq 23 ]
  [ ! -e .tmp/magisk-v31.2.apk ]

  curl() { printf 'retried APK' > "$3"; }
  flavor_magisk_build
  [ "$(cat .tmp/magisk-v31.2.apk)" = 'retried APK' ]
  [ ! -e .tmp/magisk-v31.2.apk.tmp ]
}

@test "Magisk patch arguments preserve existing arguments and preinit boundaries" {
  MAGISK_PREINIT_DEVICE='persist device*'
  local -a args=('existing argument')
  flavor_magisk_patch_args args
  [ "${#args[@]}" -eq 7 ]
  [ "${args[0]}" = 'existing argument' ]
  [ "${args[1]}" = '--patch-arg=--magisk' ]
  [ "${args[2]}" = '--patch-arg' ]
  [ "${args[3]}" = '.tmp/magisk-v31.2.apk' ]
  [ "${args[4]}" = '--patch-arg=--magisk-preinit-device' ]
  [ "${args[5]}" = '--patch-arg' ]
  [ "${args[6]}" = 'persist device*' ]
}
