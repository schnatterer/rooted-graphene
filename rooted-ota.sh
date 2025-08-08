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
GITHUB_TOKEN=${GITHUB_TOKEN:-''}
GITHUB_REPO=${GITHUB_REPO:-''}

# Optional
# If you want an OTA patched with magisk, set the preinit for your device
MAGISK_PREINIT_DEVICE=${MAGISK_PREINIT_DEVICE:-}
# Skip creation of rootless OTA by setting to "true"
SKIP_ROOTLESS=${SKIP_ROOTLESS:-'false'}
# https://grapheneos.org/releases#stable-channel
OTA_VERSION=${OTA_VERSION:-'latest'}

# It's recommended to pin magisk version in combination with AVB_ROOT_VERSION.
# Breaking changes in magisk might need to be adapted in new avbroot version
# Find latest magisk version here: https://github.com/topjohnwu/Magisk/releases, or:
# curl --fail -sL -I -o /dev/null -w '%{url_effective}' https://github.com/topjohnwu/Magisk/releases/latest | sed 's/.*\/tag\///;'
# renovate: datasource=github-releases packageName=topjohnwu/Magisk versioning=semver-coerced
DEFAULT_MAGISK_VERSION=v29.0
MAGISK_VERSION=${MAGISK_VERSION:-${DEFAULT_MAGISK_VERSION}}

SKIP_CLEANUP=${SKIP_CLEANUP:-''}

# For committing to GH pages in different repo, clone it to a different folder and set this var
PAGES_REPO_FOLDER=${PAGES_REPO_FOLDER:-''}

# Set asset released by this script to latest version, even when OTA_VERSION already exists for this device
FORCE_OTA_SERVER_UPLOAD=${FORCE_OTA_SERVER_UPLOAD:-'false'}
# Forces the artifacts to be built (and uploaded to a release)
# even it a release already contains the combination of device and flavor.
# This will lead to multiple artifacts with different commits on the release (that are not linked in the OTA server and thus are likely never used).
# However, except for test builds, we want the changes to be rolled out with new version.
# So these artifacts are just a waste of storage resources. Example
# shiba-2025020500-3e0add9-rootless.zip
# shiba-2025020500-6718632-rootless.zip
FORCE_BUILD=${FORCE_BUILD:-'false'}
# Skip setting asset released by this script to latest version, even when OTA_VERSION is latest for this device
# Takes precedence over FORCE_OTA_SERVER_UPLOAD
SKIP_OTA_SERVER_UPLOAD=${SKIP_OTA_SERVER_UPLOAD:-'false'}
# Skip patching modules (custota and oemunlockunboot) into OTA
SKIP_MODULES=${SKIP_MODULES:-'false'}
# Upload OTA to test folder on OTA server
UPLOAD_TEST_OTA=${UPLOAD_TEST_OTA:-false}

OTA_CHANNEL=${OTA_CHANNEL:-stable} # Alternative: 'alpha'
NO_COLOR=${NO_COLOR:-''}
OTA_BASE_URL="https://releases.grapheneos.org"

# renovate: datasource=github-releases packageName=chenxiaolong/avbroot versioning=semver
AVB_ROOT_VERSION=3.19.0
# renovate: datasource=github-releases packageName=chenxiaolong/Custota versioning=semver-coerced
CUSTOTA_VERSION=5.14
# renovate: datasource=git-refs packageName=https://github.com/chenxiaolong/my-avbroot-setup currentValue=master
PATCH_PY_COMMIT=16636c3
# renovate: datasource=docker packageName=python
PYTHON_VERSION=3.13.6-alpine
# renovate: datasource=github-releases packageName=chenxiaolong/OEMUnlockOnBoot versioning=semver-coerced
OEMUNLOCKONBOOT_VERSION=1.2
# renovate: datasource=github-releases packageName=chenxiaolong/afsr versioning=semver
AFSR_VERSION=1.0.3

CHENXIAOLONG_PK='ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDOe6/tBnO7xZhAWXRj3ApUYgn+XZ0wnQiXM8B7tPgv4'
GIT_PUSH_RETRIES=10

set -o nounset -o pipefail -o errexit

declare -A POTENTIAL_ASSETS

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
  patchOTAs
}

function cleanup() {
  print "Cleaning up..."
  rm -rf .tmp
  unset KEY_AVB_BASE64 KEY_OTA_BASE64 CERT_OTA_BASE64
  print "Cleanup complete."
}

function checkBuildNecessary() {
  local currentCommit
  currentCommit=$(git rev-parse --short HEAD)
  POTENTIAL_ASSETS=()
    
  if [[ -n "$MAGISK_PREINIT_DEVICE" ]]; then 
    # e.g. oriole-2023121200-magisk-v26.4-4647f74-dirty.zip
    POTENTIAL_ASSETS['magisk']="${DEVICE_ID}-${OTA_VERSION}-${currentCommit}-magisk-${MAGISK_VERSION}$(createAssetSuffix).zip"
  else 
    printGreen "MAGISK_PREINIT_DEVICE not set for device, not creating magisk OTA"
  fi
  
  if [[ "$SKIP_ROOTLESS" != 'true' ]]; then
    POTENTIAL_ASSETS['rootless']="${DEVICE_ID}-${OTA_VERSION}-${currentCommit}-rootless$(createAssetSuffix).zip"
  else
    printGreen "SKIP_ROOTLESS set, not creating rootless OTA"
  fi

  RELEASE_ID=''
  local response

  if [[ -z "$GITHUB_REPO" ]]; then print "Env Var GITHUB_REPO not set, skipping check for existing release" && return; fi

  print "Potential release: ${OTA_VERSION}"

  local params=()
  local url="https://api.github.com/repos/${GITHUB_REPO}/releases"

  if [ -n "${GITHUB_TOKEN}" ]; then
    params+=("-H" "Authorization: token ${GITHUB_TOKEN}")
  fi

  params+=("-H" "Accept: application/vnd.github.v3+json")
  response=$(
    curl --fail -sL "${params[@]}" "${url}" |
      jq --arg release_tag "${OTA_VERSION}" '.[] | select(.tag_name == $release_tag) | {id, tag_name, name, published_at, assets}'
  )

  if [[ -n ${response} ]]; then
    RELEASE_ID=$(echo "${response}" | jq -r '.id')
    print "Release ${OTA_VERSION} exists. ID=$RELEASE_ID"
    
    for flavor in "${!POTENTIAL_ASSETS[@]}"; do
      local selectedAsset POTENTIAL_ASSET_NAME="${POTENTIAL_ASSETS[$flavor]}"
      print "Checking if asset exists ${POTENTIAL_ASSET_NAME}"
      
      # Save some storage by not building and uploading every new commit as asset
      selectedAsset=$(echo "${response}" | jq -r --arg assetPrefix "${DEVICE_ID}-${OTA_VERSION}" \
        '.assets[] | select(.name | startswith($assetPrefix)) | .name' \
          | grep "${flavor}" || true)
  
      if [[ -n "${selectedAsset}" ]] && [[ "$FORCE_BUILD" != 'true' ]] && [[ "$UPLOAD_TEST_OTA" != 'true' ]]; then
        printGreen "Skipping build of asset name '$POTENTIAL_ASSET_NAME'. Because this flavor already is released with a different commit." \
          "Set FORCE_BUILD or UPLOAD_TEST_OTA to force. Assets found on release: ${selectedAsset//$'\n'/ }"
        unset "POTENTIAL_ASSETS[$flavor]"
      else
        print "No asset found with name '$POTENTIAL_ASSET_NAME'."
      fi
    done
    
    if [ "${#POTENTIAL_ASSETS[@]}" -eq 0 ]; then
      printGreen "All potential assets already exist. Exiting"
      exit 0
    fi
  else
    print "Release ${OTA_VERSION} does not exist."
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

function createAssetSuffix() {
  local suffix=''
  if [[ "${SKIP_MODULES}" == 'true' ]]; then
    suffix+='-minimal'
  fi 
  if [[ "${UPLOAD_TEST_OTA}" == 'true' ]]; then
    suffix+='-test'
  fi
  if [[ -n "$(git status --porcelain --untracked-files=no)" ]]; then
    suffix+='-dirty'
  fi
  echo "$suffix"
}

function downloadAndroidDependencies() {
  checkMandatoryVariable 'MAGISK_VERSION' 'OTA_TARGET'

  mkdir -p .tmp
  if ! ls ".tmp/magisk-$MAGISK_VERSION.apk" >/dev/null 2>&1 && [[ "${POTENTIAL_ASSETS['magisk']+isset}" ]]; then
    curl --fail -sLo ".tmp/magisk-$MAGISK_VERSION.apk" "https://github.com/topjohnwu/Magisk/releases/download/$MAGISK_VERSION/Magisk-$MAGISK_VERSION.apk"
  fi

  if ! ls ".tmp/$OTA_TARGET.zip" >/dev/null 2>&1; then
    curl --fail -sLo ".tmp/$OTA_TARGET.zip" "$OTA_URL"
  fi
}

function findLatestVersion() {
  checkMandatoryVariable DEVICE_ID

  if [[ "$MAGISK_VERSION" == 'latest' ]]; then
    MAGISK_VERSION=$(curl --fail -sL -I -o /dev/null -w '%{url_effective}' https://github.com/topjohnwu/Magisk/releases/latest | sed 's/.*\/tag\///;')
  fi
  print "Magisk version: $MAGISK_VERSION"

  # Search for a new version grapheneos.
  # e.g. https://releases.grapheneos.org/shiba-stable

  if [[ "$OTA_VERSION" == 'latest' ]]; then
    OTA_VERSION=$(curl --fail -sL "$OTA_BASE_URL/$DEVICE_ID-$OTA_CHANNEL" | head -n1 | awk '{print $1;}')
  fi
  GRAPHENE_TYPE=${GRAPHENE_TYPE:-'ota_update'} # Other option: factory
  OTA_TARGET="$DEVICE_ID-$GRAPHENE_TYPE-$OTA_VERSION"
  OTA_URL="$OTA_BASE_URL/$OTA_TARGET.zip"
  # e.g.  shiba-ota_update-2023121200
  print "OTA target: $OTA_TARGET; OTA URL: $OTA_URL"
}

function downloadAvBroot() {
  downloadAndVerifyFromChenxiaolong 'avbroot' "$AVB_ROOT_VERSION"
}

function downloadAndVerifyFromChenxiaolong() {
  local repo="$1"
  local version="$2"
  local artifact="${3:-$1}" # optional: If not set, use repo name
  
  local url="https://github.com/chenxiaolong/${repo}/releases/download/v${version}/${artifact}-${version}-x86_64-unknown-linux-gnu.zip"
  local downloadedZipFile
  downloadedZipFile="$(mktemp)"
  
  mkdir -p .tmp

  if ! ls ".tmp/${artifact}" >/dev/null 2>&1; then
    curl --fail -sL "${url}" > "${downloadedZipFile}"
    curl --fail -sL "${url}.sig" > "${downloadedZipFile}.sig"
    
    # Validate against author's public key
    ssh-keygen -Y verify -I chenxiaolong -f <(echo "chenxiaolong $CHENXIAOLONG_PK") -n file \
      -s "${downloadedZipFile}.sig" < "${downloadedZipFile}"
    
    echo N | unzip "${downloadedZipFile}" -d .tmp
    rm "${downloadedZipFile}"*
    chmod +x ".tmp/${artifact}" # e.g. .tmp/custota-tool
  fi
}

function patchOTAs() {

  downloadAvBroot
  downloadAndVerifyFromChenxiaolong 'afsr' "$AFSR_VERSION"
  if ! ls ".tmp/custota.zip" >/dev/null 2>&1; then
    curl --fail -sL "https://github.com/chenxiaolong/Custota/releases/download/v${CUSTOTA_VERSION}/Custota-${CUSTOTA_VERSION}-release.zip" > .tmp/custota.zip
    curl --fail -sL "https://github.com/chenxiaolong/Custota/releases/download/v${CUSTOTA_VERSION}/Custota-${CUSTOTA_VERSION}-release.zip.sig" > .tmp/custota.zip.sig
  fi
  if ! ls ".tmp/oemunlockonboot.zip" >/dev/null 2>&1; then
    curl --fail -sL "https://github.com/chenxiaolong/OEMUnlockOnBoot/releases/download/v${OEMUNLOCKONBOOT_VERSION}/OEMUnlockOnBoot-${OEMUNLOCKONBOOT_VERSION}-release.zip" > .tmp/oemunlockonboot.zip
    curl --fail -sL "https://github.com/chenxiaolong/OEMUnlockOnBoot/releases/download/v${OEMUNLOCKONBOOT_VERSION}/OEMUnlockOnBoot-${OEMUNLOCKONBOOT_VERSION}-release.zip.sig" > .tmp/oemunlockonboot.zip.sig
  fi
  if ! ls ".tmp/my-avbroot-setup" >/dev/null 2>&1; then
    git clone https://github.com/chenxiaolong/my-avbroot-setup .tmp/my-avbroot-setup
    (cd .tmp/my-avbroot-setup && git checkout ${PATCH_PY_COMMIT})
  fi

  base642key

  for flavor in "${!POTENTIAL_ASSETS[@]}"; do
    local targetFile=".tmp/${POTENTIAL_ASSETS[$flavor]}"

    if ls "$targetFile" >/dev/null 2>&1; then
      printGreen "File $targetFile already exists locally, not patching."
    else
      local args=()

      args+=("--output" "$targetFile")
      args+=("--input" ".tmp/$OTA_TARGET.zip")
      args+=("--sign-key-avb" "$KEY_AVB")
      args+=("--sign-key-ota" "$KEY_OTA")
      args+=("--sign-cert-ota" "$CERT_OTA")
      if [[ "$flavor" == 'magisk' ]]; then
        args+=("--patch-arg=--magisk" "--patch-arg" ".tmp/magisk-$MAGISK_VERSION.apk")
        args+=("--patch-arg=--magisk-preinit-device" "--patch-arg" "$MAGISK_PREINIT_DEVICE")
      fi

      # If env vars not set, passphrases will be queried interactively
      if [ -v PASSPHRASE_AVB ]; then
        args+=("--pass-avb-env-var" "PASSPHRASE_AVB")
      fi

      if [ -v PASSPHRASE_OTA ]; then
        args+=("--pass-ota-env-var" "PASSPHRASE_OTA")
      fi

      if [[ "${SKIP_MODULES}" != 'true' ]]; then
        args+=("--module-custota" ".tmp/custota.zip")
        args+=("--module-oemunlockonboot" ".tmp/oemunlockonboot.zip")
      fi
      # We create csig and device JSON for OTA later if necessary
      args+=("--skip-custota-tool")

      # We need to add .tmp to PATH, but we can't use $PATH: because this would be the PATH of the host not the container
      # Python image is designed to run as root, so chown the files it creates back at the end
      # ... room for improvement 😐️
      # shellcheck disable=SC2046
      docker run --rm -i $(tty &>/dev/null && echo '-t') -v "$PWD:/app"  -w /app \
        -e PATH='/bin:/usr/local/bin:/sbin:/usr/bin/:/app/.tmp' \
        --env-file <(env) \
        python:${PYTHON_VERSION} sh -c \
          "apk add openssh && \
           pip install -r .tmp/my-avbroot-setup/requirements.txt && \
           python .tmp/my-avbroot-setup/patch.py ${args[*]} ; result=\$?; \
           chown -R $(id -u):$(id -g) .tmp; exit \$result"
    
       printGreen "Finished patching file ${targetFile}"
    fi
    
  done
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

  local response changelog src_repo current_commit 

  if [[ -z "$RELEASE_ID" ]]; then
    src_repo=$(extractGithubRepo "$(git config --get remote.origin.url)")
    
    if [[ "${GITHUB_REPO}" == "${src_repo}" ]]; then
      changelog=$(curl -sL -X POST -H "Authorization: token $GITHUB_TOKEN" \
        -d "{
                \"tag_name\": \"$OTA_VERSION\",
                \"target_commitish\": \"main\"
              }" \
        "https://api.github.com/repos/$GITHUB_REPO/releases/generate-notes" | jq -r '.body // empty')
      # Replace \n by \\n to keep them as chars
      changelog="Update to [GrapheneOS ${OTA_VERSION}](https://grapheneos.org/releases#${OTA_VERSION}).\n\n$(echo "${changelog}" | sed ':a;N;$!ba;s/\n/\\n/g')"
    else 
      # When pushing to different repo's GH pages, generating notes does not make too much sense. Refer to the used repo's "version" instead. 
      current_commit=$(git rev-parse --short HEAD)
      changelog="Update to [GrapheneOS ${OTA_VERSION}](https://grapheneos.org/releases#${OTA_VERSION}).\n\nRelease created using ${src_repo}@${current_commit}. See [Changelog](https://github.com/${src_repo}/blob/${current_commit}/README.md#notable-changelog)."
    fi
    
    response=$(curl -sL -X POST -H "Authorization: token $GITHUB_TOKEN" \
      -d "{
              \"tag_name\": \"$OTA_VERSION\",
              \"target_commitish\": \"main\",
              \"name\": \"$OTA_VERSION\",
              \"body\": \"${changelog}\"
            }" \
      "https://api.github.com/repos/$GITHUB_REPO/releases")
    RELEASE_ID=$(echo "${response}" | jq -r '.id // empty')
    if [[ -n "${RELEASE_ID}" ]]; then
      printGreen "Release created successfully with ID: ${RELEASE_ID}"
    elif echo "${response}" | jq -e '.status == "422"' > /dev/null; then
      # In case release has been created in the meantime (e.g. matrix job for multiple devices concurrently)
      RELEASE_ID=$(curl -sL \
        -H "Authorization: token $GITHUB_TOKEN" \
        -H "Accept: application/vnd.github.v3+json" \
            "https://api.github.com/repos/${GITHUB_REPO}/releases" | \
            jq -r --arg release_tag "${OTA_VERSION}" '.[] | select(.tag_name == $release_tag) | .id // empty')
      if [[ -n "${RELEASE_ID}" ]]; then
        printGreen "Cannot create release but found existing release for ${OTA_VERSION}. ID=$RELEASE_ID"
      else
        printRed "Cannot create release for ${OTA_VERSION} because it seems to exist but still cannot find ID."
        exit 1
      fi
    else
      errors=$(echo "${response}" | jq -r '.errors')
      printRed "Failed to create release for ${OTA_VERSION}. Errors: ${errors}"
      exit 1
    fi
  fi

  for flavor in "${!POTENTIAL_ASSETS[@]}"; do
    local assetName="${POTENTIAL_ASSETS[$flavor]}"
    uploadFile ".tmp/$assetName" "$assetName" "application/zip"
  done
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

  for flavor in "${!POTENTIAL_ASSETS[@]}"; do
    local POTENTIAL_ASSET_NAME="${POTENTIAL_ASSETS[$flavor]}"
    local targetFile=".tmp/${POTENTIAL_ASSET_NAME}"
    
    local args=()
  
    args+=("--input" "${targetFile}")
    args+=("--output" "${targetFile}.csig")
    args+=("--key" "$KEY_OTA")
    args+=("--cert" "$CERT_OTA")
  
    # If env vars not set, passphrases will be queried interactively
    if [ -v PASSPHRASE_OTA ]; then
      args+=("--passphrase-env-var" "PASSPHRASE_OTA")
    fi
  
    .tmp/custota-tool gen-csig "${args[@]}"
  
    mkdir -p ".tmp/${flavor}"
    
    local args=()
    args+=("--file" ".tmp/${flavor}/${DEVICE_ID}.json")
    # e.g. https://github.com/schnatterer/rooted-graphene/releases/download/2023121200-v26.4-e54c67f/oriole-ota_update-2023121200.zip
    # Instead of constructing the location we could also parse it from the upload response
    args+=("--location" "https://github.com/$GITHUB_REPO/releases/download/$OTA_VERSION/$POTENTIAL_ASSET_NAME")
  
    .tmp/custota-tool gen-update-info "${args[@]}"
  done
}

function downloadCusotaTool() {
  downloadAndVerifyFromChenxiaolong 'Custota' "$CUSTOTA_VERSION" 'custota-tool'
}

function uploadOtaServerData() {

  # Update OTA server (github pages)
  local current_branch current_commit base_dir src_repo
  current_commit=$(git rev-parse --short HEAD)
  folderPrefix=''
  
  if [[ "${UPLOAD_TEST_OTA}" == 'true' ]]; then
    folderPrefix='test/'
  fi

  (
    base_dir="$(pwd)"
    src_repo=$(extractGithubRepo "$(git config --get remote.origin.url)")
    if [[ -n "${PAGES_REPO_FOLDER}" ]]; then
      cd "${PAGES_REPO_FOLDER}"
    fi
    
    current_branch=$(git rev-parse --abbrev-ref HEAD)
    git checkout gh-pages
    
    for flavor in "${!POTENTIAL_ASSETS[@]}"; do
      local POTENTIAL_ASSET_NAME="${POTENTIAL_ASSETS[$flavor]}"
      local targetFile="${folderPrefix}${flavor}/${DEVICE_ID}.json"
  
      uploadFile "${base_dir}/.tmp/${POTENTIAL_ASSET_NAME}.csig" "$POTENTIAL_ASSET_NAME.csig" "application/octet-stream"
      
      mkdir -p "${folderPrefix}${flavor}"
      # update only, if current $DEVICE_ID.json does not contain $OTA_VERSION
      # We don't want to trigger users to upgrade on new commits from this repo or new magisk versions
      # They can manually upgrade by downloading the OTAs from the releases and "adb sideload" them
      if ! grep -q "$OTA_VERSION" "${targetFile}" || [[ "$FORCE_OTA_SERVER_UPLOAD" == 'true' ]] && [[ "$SKIP_OTA_SERVER_UPLOAD" != 'true' ]]; then
        cp "${base_dir}/.tmp/${flavor}/$DEVICE_ID.json" "${targetFile}"
        git add "${targetFile}"
      elif grep -q "${OTA_VERSION}" "${targetFile}"; then
        printGreen "Skipping update of OTA server, because ${OTA_VERSION} already in ${folderPrefix}${flavor}/${DEVICE_ID}.json and FORCE_OTA_SERVER_UPLOAD is false."
      else
        printGreen "Skipping update of OTA server, because SKIP_OTA_SERVER_UPLOAD is true."
      fi
    done
    
    if ! git diff-index --quiet HEAD; then
      # Commit and push only when there are changes
      git config user.name "GitHub Actions" && git config user.email "actions@github.com"
      git commit \
          --message "Update device ${DEVICE_ID} basing on ${src_repo}@${current_commit}" \
    
      gitPushWithRetries
    fi
  
    # Switch back to the original branch
    git checkout "$current_branch"
  )
}

extractGithubRepo() {
  # Works for both HTTPS and SSH, e.g.
  # https://github.com/schnatterer/rooted-graphene
  # git@github.com:schnatterer/rooted-graphene.git

  local remote_url="$1"
  local repo

  # Remove the protocol and .git suffix
  remote_url=$(echo "$remote_url" | sed -e 's/.*:\/\/\|.*@//' -e 's/\.git$//')

  # Extract the owner/repo part
  repo=$(echo "$remote_url" | sed -e 's/.*[:\/]\([^\/]*\/[^\/]*\)$/\1/')

  echo "$repo"
}

function gitPushWithRetries() {
  local count=0

  while [ $count -lt $GIT_PUSH_RETRIES ]; do
    git pull --rebase
    if git push origin gh-pages; then
      break
    else
      count=$((count + 1))
      printGreen "Retry $count/$GIT_PUSH_RETRIES failed. Retrying..."
      sleep 2
    fi
  done
  
  if [ $count -eq $GIT_PUSH_RETRIES ]; then
    printRed "Failed to push to gh-pages after $GIT_PUSH_RETRIES attempts."
    exit 1
  fi
}

function print() {
  echo -e "$(date '+%Y-%m-%d %H:%M:%S'): $*"
}

function printGreen() {
  if [[ -z "${NO_COLOR}" ]]; then
    echo -e "\e[32m$(date '+%Y-%m-%d %H:%M:%S'): $*\e[0m"
  else
      print "$@"
  fi
}

function printRed() {
  if [[ -z "${NO_COLOR}" ]]; then
   echo -e "\e[31m$(date '+%Y-%m-%d %H:%M:%S'): $*\e[0m"
  else
      print "$@"
  fi
}
