#!/usr/bin/env bash
# Patch the target OTA's stock boot image with GitHub-built KernelPatch.
# Enable with SKIP_APATCH=false.

SKIP_APATCH=${SKIP_APATCH:-'true'}

# Switch to bmax121 once upstream publishes binaries with the required fixes.
KERNELPATCH_OWNER=${KERNELPATCH_OWNER:-'xeropresence'}
# renovate: datasource=github-releases packageName=bmax121/KernelPatch versioning=semver
KERNELPATCH_VERSION=0.13.9

APATCH_BOOT_FILE=''
KERNELPATCH_ASSET_DIGEST=''

function flavor_apatch_enabled() {
  [[ "$SKIP_APATCH" == 'false' ]]
}

function flavor_apatch_asset_infix() {
  echo "apatch-kp${KERNELPATCH_VERSION}-${KERNELPATCH_ASSET_DIGEST:0:12}"
}

function flavor_apatch_prepare() {
  mkdir -p .tmp/apatch || return
  apatchDownloadKernelPatch
}

function flavor_apatch_build() {
  local extractDir='.tmp/apatch/extract'

  rm -rf "$extractDir" || return
  mkdir -p "$extractDir" || return
  .tmp/avbroot ota extract \
    --input ".tmp/$OTA_TARGET.zip" \
    --directory "$extractDir" \
    --partition boot || return
  apatchPatchBootImage "$extractDir/boot.img" || return
  printGreen "Built APatch boot image for ${DEVICE_ID} ${OTA_VERSION}"
}

function flavor_apatch_patch_args() {
  # Preserve KernelPatch's appended payload by replacing the boot partition exactly.
  local -n patchArgs="$1"
  patchArgs+=("--patch-arg=--rootless" "--patch-arg=--replace"
    "--patch-arg=boot" "--patch-arg" "$APATCH_BOOT_FILE")
}

function flavor_apatch_verify() {
  local otaFile="$1"
  local verifyDir='.tmp/apatch/verify'

  rm -rf "$verifyDir" || return
  mkdir -p "$verifyDir" || return
  .tmp/avbroot ota extract \
    --input "$otaFile" \
    --directory "$verifyDir" \
    --partition boot || return

  if ! cmp -s -- "$APATCH_BOOT_FILE" "$verifyDir/boot.img"; then
    printRed "APatch boot image was not preserved in $otaFile"
    return 1
  fi

  .tmp/avbroot ota verify --input "$otaFile" --cert-ota "$CERT_OTA" || return
  printGreen "Verified APatch boot image in $otaFile"
}

# Resolve release assets before checking for an existing OTA. A release tag can
# be rebuilt in place, so both cached binaries and OTA names depend on its hashes.
function apatchDownloadKernelPatch() {
  local repo="${KERNELPATCH_OWNER}/KernelPatch" release assets
  release=$(curl --fail -sSL "https://api.github.com/repos/${repo}/releases/tags/${KERNELPATCH_VERSION}") || return
  assets=$(jq -er '
    .assets as $assets |
    ["kpimg-android", "kptools-linux"][] as $name |
    [$assets[] | select(.name == $name and .state == "uploaded")] |
    if length == 1 then .[0] else error("Missing KernelPatch asset: " + $name) end |
    if (.digest // "" | test("^sha256:[0-9a-f]{64}$")) then
      [.name, (.digest | ltrimstr("sha256:")), .browser_download_url] | @tsv
    else error("Missing KernelPatch SHA-256: " + $name) end
  ' <<< "$release") || return

  local name digest url target
  while IFS=$'\t' read -r name digest url; do
    case "$name" in
      kpimg-android) target='.tmp/apatch/kpimg' ;;
      kptools-linux) target='.tmp/apatch/kptools' ;;
    esac
    if [[ -s "$target" ]] &&
        printf '%s  %s\n' "$digest" "$target" | sha256sum --check --status; then
      continue
    fi
    curl --fail -sSLo "$target.tmp" "$url" || return
    if ! printf '%s  %s\n' "$digest" "$target.tmp" | sha256sum --check --status; then
      printRed "KernelPatch SHA-256 mismatch for $name"
      rm -f -- "$target.tmp"
      return 1
    fi
    mv -- "$target.tmp" "$target" || return
  done <<< "$assets"

  chmod +x .tmp/apatch/kptools || return
  KERNELPATCH_ASSET_DIGEST=$(printf '%s\n' "$repo" "$KERNELPATCH_VERSION" "$assets" |
    sha256sum | cut -d ' ' -f 1) || return
  printGreen "Using verified KernelPatch ${KERNELPATCH_VERSION} binaries from ${repo}"
}

function apatchPatchBootImage() {
  local stockBoot="$1"
  local dir='.tmp/apatch/build'
  mkdir -p "$dir" || return
  rm -f "$dir/boot.img" || return
  # Strip the AVB envelope so its hashes can be rebuilt after patching.
  .tmp/avbroot avb unpack --input "$stockBoot" \
    --output-info "$dir/avb.toml" --output-raw "$dir/stock-boot.img" --quiet || return

  local status=0
  .tmp/apatch/kptools -p -i "$dir/stock-boot.img" -k .tmp/apatch/kpimg \
    -o "$dir/patched-boot.img" > "$dir/kptools-patch.log" 2>&1 || status=$?
  if [[ "$status" -ne 0 ]]; then
    printRed "KernelPatch failed; see $dir/kptools-patch.log"
    return "$status"
  fi

  # Rebuild the AVB envelope while preserving KernelPatch's appended kernel data.
  local avbArgs=(avb pack --input-info "$dir/avb.toml"
    --input-raw "$dir/patched-boot.img" --output "$dir/boot.img" --key "$KEY_AVB" --quiet)
  if [[ -v PASSPHRASE_AVB ]]; then
    avbArgs+=(--pass-env-var PASSPHRASE_AVB)
  fi
  .tmp/avbroot "${avbArgs[@]}" || return

  APATCH_BOOT_FILE='.tmp/apatch/boot.img'
  mv -f -- "$dir/boot.img" "$APATCH_BOOT_FILE"
}
