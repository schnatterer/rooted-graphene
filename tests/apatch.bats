#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
  cd "$BATS_TEST_TMPDIR"
  DEVICE_ID=shiba
  OTA_VERSION=2026081300
  OTA_TARGET=shiba-ota_update-2026081300
  FLAVOR_DIR="$REPO_ROOT/flavors"
  NO_COLOR=1
  DEBUG=''
  SKIP_APATCH=false
  mkdir -p .tmp/apatch
  # shellcheck disable=SC1090
  source "$REPO_ROOT/rooted-ota.sh"
  loadFlavorPlugins
}

# avbroot stand-in for failure handling and boot-byte verification.
bootTools() {
  cat > .tmp/avbroot <<'EOF'
#!/usr/bin/env bash
set -e
case "$1 $2" in
  "ota verify"|"avb unpack") exit 0 ;;
esac
while (( $# )); do
  if [[ "$1" == --directory ]]; then dir="$2"; break; fi
  shift
done
mkdir -p "$dir"
cp -- "$FAKE_OTA_BOOT" "$dir/boot.img"
EOF
  chmod +x .tmp/avbroot
}

@test "APatch requires explicit opt-in" {
  unset SKIP_APATCH
  loadFlavorPlugins
  run flavor_apatch_enabled
  [ "$status" -eq 1 ]
}

@test "KernelPatch failure stops boot creation" {
  bootTools
  cat > .tmp/apatch/kptools <<'EOF'
#!/usr/bin/env bash
exit 23
EOF
  chmod +x .tmp/apatch/kptools
  run apatchPatchBootImage stock.img
  [ "$status" -eq 23 ]
  [ ! -e .tmp/apatch/boot.img ]
}

@test "verification rejects changed boot bytes and accepts exact bytes" {
  bootTools
  APATCH_BOOT_FILE="$PWD/apatch-boot.img"
  printf 'patched boot' > "$APATCH_BOOT_FILE"
  printf 'repacked boot' > other.img
  export FAKE_OTA_BOOT="$PWD/other.img"
  run flavor_apatch_verify ota.zip
  [ "$status" -eq 1 ]
  FAKE_OTA_BOOT="$APATCH_BOOT_FILE"
  run flavor_apatch_verify ota.zip
  [ "$status" -eq 0 ]
}
