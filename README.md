rooted-graphene
===

⚠️ Not tested on a device, yet. Don't use for now.

Script for creating GrapheneOS over the air updates (OTAs) patched with Magisk using [avbroot](https://github.com/chenxiaolong/avbroot).

Provides its own OTA server for [Custota](https://github.com/chenxiaolong/Custota) magisk module: https://schnatterer.github.io/rooted-graphene/

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

# Test releasing
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