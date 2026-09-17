#!/usr/bin/env bash

set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
work_dir=$(mktemp -d)
trap 'rm -rf "$work_dir"' EXIT

printf 'exact-version-apatch-boot\n' > "$work_dir/boot.img"
boot_sha256=$(sha256sum "$work_dir/boot.img" | cut -d ' ' -f 1)
bad_sha256=$(printf '%064d' 0)
python3 -c 'import sys, zipfile; z = zipfile.ZipFile(sys.argv[1], "w"); z.writestr("AndroidManifest.xml", b"manifest"); z.close()' "$work_dir/APatch.apk"
manager_sha256=$(sha256sum "$work_dir/APatch.apk" | cut -d ' ' -f 1)

(
  cd "$work_dir"
  export DEVICE_ID=shiba
  export OTA_VERSION=2026081300
  export APATCH_BOOT_IMAGE="$work_dir/boot.img"
  export APATCH_BOOT_SHA256="$boot_sha256"
  export APATCH_BOOT_DEVICE=shiba
  export APATCH_BOOT_VERSION=2026081300
  export APATCH_MANAGER_APK="$work_dir/APatch.apk"
  export APATCH_MANAGER_SHA256="$manager_sha256"
  . "$repo_root/rooted-ota.sh"

  prepareApatchBootImage
  prepareApatchManagerApk

  [[ "$APATCH_BOOT_DIGEST" == "$boot_sha256" ]]
  [[ "$APATCH_BOOT_FILE" == ".tmp/apatch-shiba-2026081300-boot.img" ]]
  cmp "$work_dir/boot.img" "$APATCH_BOOT_FILE"
  [[ "$APATCH_MANAGER_DIGEST" == "$manager_sha256" ]]
  [[ "$APATCH_MANAGER_FILE" == ".tmp/apatch-shiba-2026081300-manager.apk" ]]
  cmp "$work_dir/APatch.apk" "$APATCH_MANAGER_FILE"
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

if (
  cd "$work_dir"
  export DEVICE_ID=shiba
  export OTA_VERSION=2026081300
  export APATCH_BOOT_IMAGE="$work_dir/boot.img"
  export APATCH_BOOT_SHA256="$boot_sha256"
  export APATCH_BOOT_DEVICE=shiba
  export APATCH_BOOT_VERSION=2026081300
  export APATCH_MANAGER_APK=
  export APATCH_MANAGER_SHA256=
  . "$repo_root/rooted-ota.sh"
  prepareApatchBootImage
  prepareApatchManagerApk
) >/dev/null 2>&1; then
  echo "Expected an APatch flavor without a manager APK to be rejected" >&2
  exit 1
fi

if (
  cd "$work_dir"
  export DEVICE_ID=shiba
  export OTA_VERSION=2026081300
  export APATCH_BOOT_IMAGE="$work_dir/boot.img"
  export APATCH_BOOT_SHA256="$boot_sha256"
  export APATCH_BOOT_DEVICE=shiba
  export APATCH_BOOT_VERSION=2026081300
  export APATCH_MANAGER_APK="$work_dir/APatch.apk"
  export APATCH_MANAGER_SHA256="$bad_sha256"
  . "$repo_root/rooted-ota.sh"
  prepareApatchBootImage
  prepareApatchManagerApk
) >/dev/null 2>&1; then
  echo "Expected a mismatched APatch manager checksum to be rejected" >&2
  exit 1
fi

printf 'not-an-apk\n' > "$work_dir/not-an-apk"
not_apk_sha256=$(sha256sum "$work_dir/not-an-apk" | cut -d ' ' -f 1)
if (
  cd "$work_dir"
  export DEVICE_ID=shiba
  export OTA_VERSION=2026081300
  export APATCH_BOOT_IMAGE="$work_dir/boot.img"
  export APATCH_BOOT_SHA256="$boot_sha256"
  export APATCH_BOOT_DEVICE=shiba
  export APATCH_BOOT_VERSION=2026081300
  export APATCH_MANAGER_APK="$work_dir/not-an-apk"
  export APATCH_MANAGER_SHA256="$not_apk_sha256"
  . "$repo_root/rooted-ota.sh"
  prepareApatchBootImage
  prepareApatchManagerApk
) >/dev/null 2>&1; then
  echo "Expected a non-APK manager artifact to be rejected" >&2
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
  prepareApatchManagerApk
  [[ -z "$APATCH_BOOT_FILE" ]]
  [[ -z "$APATCH_BOOT_DIGEST" ]]
  [[ -z "$APATCH_MANAGER_FILE" ]]
  [[ -z "$APATCH_MANAGER_DIGEST" ]]
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
  APATCH_MANAGER_FILE=.tmp/exact-apatch-manager.apk
  cp "$work_dir/APatch.apk" "$APATCH_MANAGER_FILE"
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
  [[ "$docker_call" == *"apatch-patch.py"* ]]
  [[ "$docker_call" == *"--module-apatch-manager $APATCH_MANAGER_FILE"* ]]
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
partition=''
while (($#)); do
  case "$1" in
    --directory)
      directory=$2
      shift 2
      ;;
    --partition)
      partition=$2
      shift 2
      ;;
    *)
      shift
      ;;
  esac
done

mkdir -p "$directory"
case "$partition" in
  boot)
    cp "$FAKE_EXTRACTED_BOOT" "$directory/boot.img"
    ;;
  system)
    touch "$directory/system.img"
    ;;
esac
EOF
  chmod +x .tmp/avbroot

  APATCH_BOOT_FILE="$work_dir/boot.img"
  APATCH_MANAGER_FILE="$work_dir/APatch.apk"
  touch apatch-ota.zip
  export FAKE_EXTRACTED_BOOT="$work_dir/boot.img"
  export FAKE_EXTRACTED_MANAGER="$work_dir/APatch.apk"
  extractApatchManagerFromSystem() {
    cp "$FAKE_EXTRACTED_MANAGER" "$2"
  }
  verifyApatchOta apatch-ota.zip

  printf 'different-boot\n' > "$work_dir/different-boot.img"
  export FAKE_EXTRACTED_BOOT="$work_dir/different-boot.img"
  if verifyApatchOta apatch-ota.zip >/dev/null 2>&1; then
    echo "Expected APatch OTA with a different boot image to be rejected" >&2
    exit 1
  fi

  export FAKE_EXTRACTED_BOOT="$work_dir/boot.img"
  printf 'different-manager\n' > "$work_dir/different-manager.apk"
  export FAKE_EXTRACTED_MANAGER="$work_dir/different-manager.apk"
  if verifyApatchOta apatch-ota.zip >/dev/null 2>&1; then
    echo "Expected APatch OTA with a different manager APK to be rejected" >&2
    exit 1
  fi
  unset FAKE_EXTRACTED_BOOT
)

injector_dir="$work_dir/injector"
mkdir -p "$injector_dir/.tmp/my-avbroot-setup/lib/modules"
cp "$repo_root/apatch-patch.py" "$injector_dir/apatch-patch.py"
cat > "$injector_dir/.tmp/my-avbroot-setup/lib/filesystem.py" <<'EOF'
class CpioFs:
    pass


class ExtFs:
    pass
EOF
cat > "$injector_dir/.tmp/my-avbroot-setup/lib/modules/__init__.py" <<'EOF'
from dataclasses import dataclass


class MissingArgs(Exception):
    pass


class Module:
    pass


@dataclass
class ModuleRequirements:
    boot_images: set[str]
    ext_images: set[str]
    selinux_patching: bool


def all_modules():
    return []
EOF
cat > "$injector_dir/.tmp/my-avbroot-setup/patch.py" <<'EOF'
import argparse
import os
from pathlib import Path

from lib import modules


class FakeExtFs:
    def __init__(self, root):
        self.root = root

    def mkdir(self, path, **kwargs):
        (self.root / path).mkdir(
            mode=kwargs.get('mode', 0o777),
            parents=kwargs.get('parents', False),
            exist_ok=kwargs.get('exist_ok', False),
        )

    def open(self, path, open_mode, **kwargs):
        return (self.root / path).open(open_mode)


def main():
    parser = argparse.ArgumentParser()
    for module_type in modules.all_modules():
        module_type.add_args(parser)
    args = parser.parse_args()

    system_root = Path(os.environ['FAKE_SYSTEM_ROOT'])
    for module_type in modules.all_modules():
        try:
            module = module_type(args)
        except modules.MissingArgs:
            continue
        module.inject({}, {'system': FakeExtFs(system_root)}, [])
EOF
mkdir -p "$injector_dir/system"
(
  cd "$injector_dir"
  FAKE_SYSTEM_ROOT="$injector_dir/system" \
    python3 apatch-patch.py --module-apatch-manager "$work_dir/APatch.apk"
)
cmp "$work_dir/APatch.apk" "$injector_dir/system/system/app/APatch/APatch.apk"

echo "APatch flavor validation passed"
