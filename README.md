rooted-graphene
===

⚠️ Not tested on a device, yet. Don't use for now.

GrapheneOS over the air updates (OTAs) patched with Magisk using [avbroot](https://github.com/chenxiaolong/avbroot) allowing for AVB and locked bootloader *and* root access.
Provides its own OTA server for [Custota](https://github.com/chenxiaolong/Custota) magisk module.

## Usage

* Initial installation of OS:
  * Follow the steps provided by [avbroot](https://github.com/chenxiaolong/avbroot#initial-setup) using the `avb_pkmd.bin` from this repo.
  * Make sure the versions of the unpatched version initially installed and the one used here match.
  * Hint: You might want to start with the version before the latest to try if OTA is working before initializing your device.
  * [Disable system updater app](https://github.com/chenxiaolong/avbroot#ota-updates).
* Updates: 
  * You could either do updates manually using `adb sideload` (see [here](https://github.com/chenxiaolong/avbroot#updates)),
  * or use the [Custota](https://github.com/chenxiaolong/Custota) magisk module.
  * To do so, download and install the Custota module in magsik and reboot.
  * Open Custota and set the OTA server URL to point to this OTA server: https://schnatterer.github.io/rooted-graphene/

## Script

You can use the script in this repo to create your own OTAs and run your own OTA server.

### Only create patched OTAs

```shell
# Generate keys
bash -c 'source rooted-ota.sh && generateKeys'

# Enter passphrases interactively
DEVICE_ID=oriole MAGISK_PREINIT_DEVICE='metadata' bash -c '. rooted-ota.sh && createRootedOta'  
 
# Enter passphrases via env (e.g. on CI)
  export PASSPHRASE_AVB=1
  export PASSPHRASE_OTA=1 
DEVICE_ID=oriole MAGISK_PREINIT_DEVICE='metadata' bash -c '. rooted-ota.sh && createRootedOta' 
```

For IDs see [grapheneos.org/releases](https://grapheneos.org/releases). For Magisk preinit see,e.g. [here](#magisk-preinit-strings).

### Upload patched OTAs as GH release and provide OTA server via GH pages

See [GitHub action](.github/workflows/release.yaml) for automating this.

```shell
GITHUB_TOKEN=gh... \
GITHUB_REPO=schnatterer/rooted-ota \
DEVICE_ID=oriole \
MAGISK_PREINIT_DEVICE=metadata \
bash -c '. rooted-ota.sh && createAndReleaseRootedOta'
```

## Development
```bash
# DEBUG some parts of the script interactively
DEBUG=1 bash --init-file rooted-ota.sh
# Test loading secrets from env
PASSPHRASE_AVB=1 PASSPHRASE_OTA=1 bash -c '. rooted-ota.sh && key2base64 && KEY_AVB=doesnotexist createAndReleaseRootedOta'        

# Avoid having to download OTA all over again: SKIP_CLEANUP=true or:
mkdir -p .tmp && ln -s $PWD/shiba-ota_update-2023121200.zip .tmp/shiba-ota_update-2023121200.zip

# Test only releasing
  GITHUB_TOKEN=gh... \
RELEASE_ID='' \
ASSET_EXISTS=false \
POTENTIAL_RELEASE_NAME=test \
POTENTIAL_ASSET_NAME=test.zip \
GITHUB_REPO=schnatterer/rooted-ota \
  bash -c '. rooted-ota.sh && releaseOta'

# Test only GH pages deployment
GITHUB_REPO=schnatterer/rooted-ota \
DEVICE_ID=oriole \
MAGISK_PREINIT_DEVICE=metadata \
  bash -c '. rooted-ota.sh && findLatestVersion && checkBuildNecessary && createOtaServerData && uploadOtaServerData'


# e2e test
  GITHUB_TOKEN=gh... \
GITHUB_REPO=schnatterer/rooted-ota \
DEVICE_ID=oriole \
MAGISK_PREINIT_DEVICE=metadata \
SKIP_CLEANUP=true \
DEBUG=1 \
  bash -c '. rooted-ota.sh && createAndReleaseRootedOta'
```

## Magisk preinit strings

```shell
preinit["cheetah"]="persist" # Pixel Pro 7 https://xdaforums.com/t/guide-to-lock-bootloader-while-using-rooted-otaos-magisk-root.4510295/page-5#post-88499289)
preinit["oriole"]="=metadata" # Pixel 6
```


## References, Inspiration
https://github.com/MuratovAS/grapheneos-magisk/blob/main/docker/Dockerfile

https://xdaforums.com/t/guide-to-lock-bootloader-while-using-rooted-otaos-magisk-root.4510295/