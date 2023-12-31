#!/usr/bin/env bash

# Requires git, jq, and curl

KEY_AVB=${KEY_AVB:-avb.key}
KEY_OTA=${KEY_OTA:-ota.key}
CERT_OTA=${CERT_OTA:-ota.crt}
# Or else, set these env vars
KEY_AVB_BASE64=${KEY_AVB_BASE64:-''}
KEY_OTA_BASE64=${KEY_OTA_BASE64:-''}
CERT_OTA_BASE64=${CERT_OTA_BASE64:-''}

# Set these env vars, or else these params will be queries interactively
# PASSPHRASE_AVB
# PASSPHRASE_OTA

# Enable debug output only after sensitive vars have been set, to reduce risk of leak
DEBUG=${DEBUG:-''}
if [[ -n "${DEBUG}" ]]; then set -x; fi

# Mandatory params
DEVICE_ID=${DEVICE_ID:-} # See here for device IDs https://grapheneos.org/releases
MAGISK_PREINIT_DEVICE=${MAGISK_PREINIT_DEVICE:-}
GITHUB_TOKEN=${GITHUB_TOKEN:-''}
GITHUB_REPO=${GITHUB_REPO:-''}

# Optional
MAGISK_VERSION=${MAGISK_VERSION:-'latest'}
OTA_VERSION=${OTA_VERSION:-'latest'}

SKIP_CLEANUP=${SKIP_CLEANUP:-''}
# Set asset released by this script to latest version, even when OTA_VERSION already exists for this device
FORCE_OTA_SERVER_UPLOAD=${FORCE_OTA_SERVER_UPLOAD:-'false'}

OTA_CHANNEL=${OTA_CHANNEL:-stable} # Alternative: 'alpha'
OTA_BASE_URL="https://releases.grapheneos.org"

# TODO use dependabot or renovate to upgrade these
AVB_ROOT_VERSION=3.0.0
CUSTOTA_VERSION=3.0

set -o nounset -o pipefail -o errexit

function generateKeys() {
  downloadAvBroot
  # https://github.com/chenxiaolong/avbroot/tree/077a80f4ce7233b0e93d4a1477d09334af0da246#generating-keys
  # Generate the AVB and OTA signing keys.
  .tmp/avbroot key generate-key -o $KEY_AVB
  .tmp/avbroot key generate-key -o $KEY_OTA

  # Convert the public key portion of the AVB signing key to the AVB public key metadata format.
  # This is the format that the bootloader requires when setting the custom root of trust.
  .tmp/avbroot key extract-avb -k $KEY_AVB -o avb_pkmd.bin

  # Generate a self-signed certificate for the OTA signing key. This is used by recovery to verify OTA updates when sideloading.
  .tmp/avbroot key generate-cert -k $KEY_OTA -o $CERT_OTA

  echo Upload these to your CI server, if necessary.
  echo The script takes these values as env or file
  key2base64
}

function key2base64() {
  KEY_AVB_BASE64=$(base64 -w0 "$KEY_AVB") && echo "KEY_AVB_BASE64=$KEY_AVB_BASE64"
  KEY_OTA_BASE64=$(base64 -w0 "$KEY_OTA") && echo "KEY_OTA_BASE64=$KEY_OTA_BASE64"
  CERT_OTA_BASE64=$(base64 -w0 "$CERT_OTA") && echo "CERT_OTA_BASE64=$CERT_OTA_BASE64"
  export KEY_AVB_BASE64 KEY_OTA_BASE64 CERT_OTA_BASE64
}

function createAndReleaseRootedOta() {
  createRootedOta
  releaseOta

  createOtaServerData
  uploadOtaServerData
}

function createRootedOta() {
  [[ "$SKIP_CLEANUP" != 'true' ]] && trap cleanup EXIT ERR

  findLatestVersion
  checkBuildNecessary
  downloadAndroidDependencies
  patchOta
}

function cleanup() {
  echo "Cleaning up..."
  rm -rf .tmp
  unset KEY_AVB_BASE64 KEY_OTA_BASE64 CERT_OTA_BASE64
  echo "Cleanup complete."
}

function checkBuildNecessary() {
  POTENTIAL_RELEASE_NAME="$OTA_VERSION"
  # e.g. oriole-2023121200-v26.4-4647f74-dirty.zip
  POTENTIAL_ASSET_NAME="$DEVICE_ID-$OTA_VERSION-$MAGISK_VERSION-$(git rev-parse --short HEAD)$(createDirtySuffix).zip"
  RELEASE_ID=''
  local response

  if [[ -z "$GITHUB_REPO" ]]; then echo "Env Var GITHUB_REPO not set, skipping check for existing release" && return; fi

  checkMandatoryVariable 'GITHUB_REPO'
  echo "Potential release: $POTENTIAL_RELEASE_NAME"

  local params=()
  local url="https://api.github.com/repos/${GITHUB_REPO}/releases"

  if [ -n "${GITHUB_TOKEN}" ]; then
    params+=("-H" "Authorization: token ${GITHUB_TOKEN}")
  fi

  params+=("-H" "Accept: application/vnd.github.v3+json")
  response=$(
    curl --fail -s "${params[@]}" "${url}" |
      jq --arg release_tag "${POTENTIAL_RELEASE_NAME}" '.[] | select(.tag_name == $release_tag) | {id, tag_name, name, published_at, assets}'
  )

  if [[ -n ${response} ]]; then
    RELEASE_ID=$(echo "$response" | jq -r '.id')
    echo "Release ${POTENTIAL_RELEASE_NAME} exists"
    selected_asset=$(echo "$response" | jq -r --arg assetName "$POTENTIAL_ASSET_NAME" '.assets[] | select(.name == $assetName)')

    if [ -n "$selected_asset" ]; then
      printGreen "Asset with name '$POTENTIAL_ASSET_NAME' already exists. Exiting."
      echo "$selected_asset"
      exit 0 
    else
      echo "No asset found with name '$POTENTIAL_ASSET_NAME'."
    fi
  else
    echo "Release ${POTENTIAL_RELEASE_NAME} does not exist."
  fi

}

function checkMandatoryVariable() {
  for var_name in "$@"; do
    local var_value="${!var_name}"

    if [[ -z "$var_value" ]]; then
      printRed "Missing mandatory param $var_name"
      exit 1
    fi
  done
}

function createDirtySuffix() {
  if [[ -n "$(git status --porcelain --untracked-files=no)" ]]; then
    echo "-dirty"
  else
    echo ""
  fi
}

function downloadAndroidDependencies() {
  checkMandatoryVariable 'MAGISK_VERSION' 'OTA_TARGET'

  mkdir -p .tmp
  if ! ls ".tmp/magisk-$MAGISK_VERSION.apk" >/dev/null 2>&1; then
    curl --fail -Lo ".tmp/magisk-$MAGISK_VERSION.apk" "https://github.com/topjohnwu/Magisk/releases/download/$MAGISK_VERSION/Magisk-$MAGISK_VERSION.apk"
  fi

  if ! ls ".tmp/$OTA_TARGET.zip" >/dev/null 2>&1; then
    curl --fail -Lo ".tmp/$OTA_TARGET.zip" "$OTA_URL"
  fi
}

function findLatestVersion() {
  checkMandatoryVariable DEVICE_ID

  if [[ "$MAGISK_VERSION" == 'latest' ]]; then
    MAGISK_VERSION=$(curl --fail -sL -I -o /dev/null -w '%{url_effective}' https://github.com/topjohnwu/Magisk/releases/latest | sed 's/.*\/tag\///;')
  fi
  echo "Magisk version: $MAGISK_VERSION"

  # Search for a new version grapheneos.
  # e.g. https://releases.grapheneos.org/shiba-stable

  if [[ "$OTA_VERSION" == 'latest' ]]; then
    OTA_VERSION=$(curl --fail -s "$OTA_BASE_URL/$DEVICE_ID-$OTA_CHANNEL" | head -n1 | awk '{print $1;}')
  fi
  GRAPHENE_TYPE=${GRAPHENE_TYPE:-'ota_update'} # Other option: factory
  OTA_TARGET="$DEVICE_ID-$GRAPHENE_TYPE-$OTA_VERSION"
  OTA_URL="$OTA_BASE_URL/$OTA_TARGET.zip"
  # e.g.  shiba-ota_update-2023121200
  echo "OTA target: $OTA_TARGET; OTA URL: $OTA_URL"
}

function downloadAvBroot() {
  mkdir -p .tmp

  if ! ls ".tmp/avbroot" >/dev/null 2>&1; then
    curl --fail -sL "https://github.com/chenxiaolong/avbroot/releases/download/v$AVB_ROOT_VERSION/avbroot-$AVB_ROOT_VERSION-x86_64-unknown-linux-gnu.zip" >.tmp/avb.zip &&
      echo N | unzip .tmp/avb.zip -d .tmp &&
      rm .tmp/avb.zip &&
      chmod +x .tmp/avbroot
  fi
}

function patchOta() {
  checkMandatoryVariable MAGISK_PREINIT_DEVICE

  if ls ".tmp/$OTA_TARGET.zip.patched" >/dev/null 2>&1; then return; fi

  downloadAvBroot
  base642key

  local args=()

  args+=("--output" ".tmp/$OTA_TARGET.zip.patched")
  args+=("--input" ".tmp/$OTA_TARGET.zip")
  args+=("--key-avb" "$KEY_AVB")
  args+=("--key-ota" "$KEY_OTA")
  args+=("--cert-ota" "$CERT_OTA")
  args+=("--magisk" ".tmp/magisk-$MAGISK_VERSION.apk")
  args+=("--magisk-preinit-device" "$MAGISK_PREINIT_DEVICE")

  # If env vars not set, passphrases will be queried interactively
  if [ -v PASSPHRASE_AVB ]; then
    args+=("--pass-avb-env-var" "PASSPHRASE_AVB")
  fi

  if [ -v PASSPHRASE_OTA ]; then
    args+=("--pass-ota-env-var" "PASSPHRASE_OTA")
  fi

  .tmp/avbroot ota patch "${args[@]}"
}

function base642key() {
  set +x # Don't expose secrets to log
  if [ -n "$KEY_AVB_BASE64" ]; then
    echo "$KEY_AVB_BASE64" | base64 -d >.tmp/$KEY_AVB
    KEY_AVB=.tmp/$KEY_AVB
  fi

  if [ -n "$KEY_OTA_BASE64" ]; then
    echo "$KEY_OTA_BASE64" | base64 -d >.tmp/$KEY_OTA
    KEY_OTA=.tmp/$KEY_OTA
  fi

  if [ -n "$CERT_OTA_BASE64" ]; then
    echo "$CERT_OTA_BASE64" | base64 -d >.tmp/$CERT_OTA
    CERT_OTA=.tmp/$CERT_OTA
  fi

  if [[ -n "${DEBUG}" ]]; then set -x; fi
}

function releaseOta() {
  checkMandatoryVariable 'GITHUB_REPO' 'GITHUB_TOKEN'

  local response
  if [[ -z "$RELEASE_ID" ]]; then
    response=$(curl --fail -X POST -H "Authorization: token $GITHUB_TOKEN" \
      -d "{
              \"tag_name\": \"$POTENTIAL_RELEASE_NAME\",
              \"target_commitish\": \"main\",
              \"name\": \"$POTENTIAL_RELEASE_NAME\",
              \"body\": \"See [Changelog](https://grapheneos.org/releases#$OTA_VERSION).\"
            }" \
      "https://api.github.com/repos/$GITHUB_REPO/releases")
    RELEASE_ID=$(echo "$response" | jq -r '.id')
  fi

  uploadFile ".tmp/$OTA_TARGET.zip.patched" "$POTENTIAL_ASSET_NAME" "application/zip"
}

function uploadFile() {
  local sourceFileName="$1"
  local targetFileName="$2"
  local contentType="$3"

  # Note that --data-binary might lead to out of memory
  curl --fail -X POST -H "Authorization: token $GITHUB_TOKEN" \
    -H "Content-Type: $contentType" \
    --upload-file "$sourceFileName" \
    "https://uploads.github.com/repos/$GITHUB_REPO/releases/$RELEASE_ID/assets?name=$targetFileName"
}

function createOtaServerData() {
  downloadCusotaTool

  local args=()

  args+=("--input" ".tmp/$OTA_TARGET.zip.patched")
  args+=("--output" ".tmp/$OTA_TARGET.zip.csig")
  args+=("--key" "$KEY_OTA")
  args+=("--cert" "$CERT_OTA")

  # If env vars not set, passphrases will be queried interactively
  if [ -v PASSPHRASE_OTA ]; then
    args+=("--passphrase-env-var" "PASSPHRASE_OTA")
  fi

  .tmp/custota-tool gen-csig "${args[@]}"

  local args=()
  args+=("--file" ".tmp/$DEVICE_ID.json")
  # e.g. https://github.com/schnatterer/rooted-graphene/releases/download/2023121200-v26.4-e54c67f/oriole-ota_update-2023121200.zip
  # Instead of constructing the location we could also parse it from the upload response
  args+=("--location" "https://github.com/$GITHUB_REPO/releases/download/$POTENTIAL_RELEASE_NAME/$POTENTIAL_ASSET_NAME")

  .tmp/custota-tool gen-update-info "${args[@]}"
}

function downloadCusotaTool() {
  mkdir -p .tmp
  # TODO verify, avbroot as well
  # https://github.com/chenxiaolong/Custota/releases/download/v3.0/custota-tool-3.0-x86_64-unknown-linux-gnu.zip.sig

  if ! ls ".tmp/custota-tool" >/dev/null 2>&1; then
    curl --fail -sL "https://github.com/chenxiaolong/Custota/releases/download/v$CUSTOTA_VERSION/custota-tool-$CUSTOTA_VERSION-x86_64-unknown-linux-gnu.zip" >.tmp/custota.zip &&
      echo N | unzip .tmp/custota.zip -d .tmp &&
      rm .tmp/custota.zip &&
      chmod +x .tmp/custota-tool
  fi
}

function uploadOtaServerData() {
  uploadFile ".tmp/$OTA_TARGET.zip.csig" "$POTENTIAL_ASSET_NAME.csig" "application/octet-stream"

  # Update OTA server (github pages)
  local current_branch current_commit current_author
  current_branch=$(git rev-parse --abbrev-ref HEAD)
  current_commit=$(git rev-parse --short HEAD)
  current_author=$(git log -1 --format="%an <%ae>")

  git checkout gh-pages
  
  # update only, if current $DEVICE_ID.json does not contain $OTA_VERSION
  # We don't want to trigger users to upgrade on new commits from this repo or new magisk versions
  # They can manually upgrade by downloading the OTAs from the releases and "adb sideload" them
  if ! grep -q "$OTA_VERSION" "$DEVICE_ID.json" || [[ "$FORCE_OTA_SERVER_UPLOAD" == 'true' ]]; then
    cp ".tmp/$DEVICE_ID.json" $DEVICE_ID.json
    git add "$DEVICE_ID.json"
    git config user.name "GitHub Actions" && git config user.email "actions@github.com"
    git commit \
      --message "Update device $DEVICE_ID basing on commit $current_commit" \
      --author="$current_author"
  
    git push origin gh-pages
  
    # Switch back to the original branch
    git checkout "$current_branch"
  else
    printGreen "Skipping update of OTA server, because $OTA_VERSION already in $DEVICE_ID.json and FORCE_OTA_SERVER_UPLOAD is false."
  fi
}

function printGreen() {
    echo -e "\e[32m$1\e[0m"
}

function printRed() {
    echo -e "\e[31m$1\e[0m"
}