#!/usr/bin/env bash

set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
work_dir=$(mktemp -d)
trap 'rm -rf "$work_dir"' EXIT

printf 'exact-version-apatch-boot\n' > "$work_dir/boot.img"
boot_sha256=$(sha256sum "$work_dir/boot.img" | cut -d ' ' -f 1)
bad_sha256=$(printf '%064d' 0)

(
  cd "$work_dir"
  export DEVICE_ID=shiba
  export OTA_VERSION=2026081300
  export APATCH_BOOT_IMAGE="$work_dir/boot.img"
  export APATCH_BOOT_SHA256="$boot_sha256"
  export APATCH_BOOT_DEVICE=shiba
  export APATCH_BOOT_VERSION=2026081300
  . "$repo_root/rooted-ota.sh"

  prepareApatchBootImage

  [[ "$APATCH_BOOT_DIGEST" == "$boot_sha256" ]]
  [[ "$APATCH_BOOT_FILE" == ".tmp/apatch-shiba-2026081300-boot.img" ]]
  cmp "$work_dir/boot.img" "$APATCH_BOOT_FILE"
)

if (
  cd "$work_dir"
  export DEVICE_ID=shiba
  export OTA_VERSION=2026081300
  export APATCH_BOOT_IMAGE="$work_dir/boot.img"
  export APATCH_BOOT_SHA256="$boot_sha256"
  export APATCH_BOOT_DEVICE=shiba
  export APATCH_BOOT_VERSION=2026081400
  . "$repo_root/rooted-ota.sh"
  prepareApatchBootImage
) >/dev/null 2>&1; then
  echo "Expected mismatched GrapheneOS versions to be rejected" >&2
  exit 1
fi

if (
  cd "$work_dir"
  export DEVICE_ID=shiba
  export OTA_VERSION=2026081300
  export APATCH_BOOT_IMAGE="$work_dir/boot.img"
  export APATCH_BOOT_SHA256="$bad_sha256"
  export APATCH_BOOT_DEVICE=shiba
  export APATCH_BOOT_VERSION=2026081300
  . "$repo_root/rooted-ota.sh"
  prepareApatchBootImage
) >/dev/null 2>&1; then
  echo "Expected a mismatched APatch boot checksum to be rejected" >&2
  exit 1
fi

(
  cd "$work_dir"
  export DEVICE_ID=shiba
  export OTA_VERSION=2026081300
  export SKIP_APATCH=true
  export APATCH_BOOT_IMAGE="$work_dir/boot.img"
  . "$repo_root/rooted-ota.sh"

  prepareApatchBootImage
  [[ -z "$APATCH_BOOT_FILE" ]]
  [[ -z "$APATCH_BOOT_DIGEST" ]]
)

(
  cd "$work_dir"
  export DEVICE_ID=shiba
  export OTA_VERSION=2026081300
  . "$repo_root/rooted-ota.sh"
  OTA_TARGET=shiba-ota_update-2026081300

  mkdir -p .tmp/my-avbroot-setup
  touch .tmp/custota.zip .tmp/oemunlockonboot.zip
  APATCH_BOOT_FILE=.tmp/exact-apatch-boot.img
  cp "$work_dir/boot.img" "$APATCH_BOOT_FILE"
  POTENTIAL_ASSETS=([apatch]='shiba-2026081300-apatch-test.zip')

  downloadAvBroot() { :; }
  downloadAndVerifyFromChenxiaolong() { :; }
  base642key() { :; }
  docker() {
    printf '%s\n' "$*" > docker.args
  }

  verifyApatchOta() {
    printf '%s\n' "$1" > verified-ota
  }

  patchOTAs
  docker_call=$(<docker.args)
  [[ "$docker_call" == *"--patch-arg=--rootless --patch-arg=--replace --patch-arg=boot --patch-arg $APATCH_BOOT_FILE"* ]]
  [[ "$(<verified-ota)" == '.tmp/shiba-2026081300-apatch-test.zip' ]]
)

(
  cd "$work_dir"
  . "$repo_root/rooted-ota.sh"

  mkdir -p .tmp
  cat > .tmp/avbroot <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

directory=''
while (($#)); do
  case "$1" in
    --directory)
      directory=$2
      shift 2
      ;;
    *)
      shift
      ;;
  esac
done

mkdir -p "$directory"
cp "$FAKE_EXTRACTED_BOOT" "$directory/boot.img"
EOF
  chmod +x .tmp/avbroot

  APATCH_BOOT_FILE="$work_dir/boot.img"
  touch apatch-ota.zip
  export FAKE_EXTRACTED_BOOT="$work_dir/boot.img"
  verifyApatchOta apatch-ota.zip

  printf 'different-boot\n' > "$work_dir/different-boot.img"
  export FAKE_EXTRACTED_BOOT="$work_dir/different-boot.img"
  if verifyApatchOta apatch-ota.zip >/dev/null 2>&1; then
    echo "Expected APatch OTA with a different boot image to be rejected" >&2
    exit 1
  fi
  unset FAKE_EXTRACTED_BOOT
)

echo "APatch flavor validation passed"
