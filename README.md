rooted-graphene
===


GrapheneOS over the air updates (OTAs) patched with Magisk using [avbroot](https://github.com/chenxiaolong/avbroot) allowing for AVB and locked bootloader *and* root access.
Provides its own OTA server for [Custota](https://github.com/chenxiaolong/Custota) magisk module.

> ⚠️ OS and root work in general. However, zygisk does not (and [likely never will](https://github.com/topjohnwu/Magisk/pull/7606)) work, leading to magisk being easily discovered by other apps and lots of banking apps not working.  
KernelSU support is work in progress.

## Usage

## Initial installation of OS

### Hints 
* Make sure the versions of the unpatched version initially installed and the one taken from this repo match.
* You might want to start with the version before the latest to try if OTA is working before initializing your device.
* Don't mix up **factory image** and OTA
* The following steps are basically the ones described at [avbroot](https://github.com/chenxiaolong/avbroot#initial-setup) using the `avb_pkmd.bin` from this repo.

### Installation

#### Install GrapheneOS

Download [**factory image**](https://grapheneos.org/releases) and follow the [official instructions](https://grapheneos.org/install/cli)  to install GrapheneOS.

TLDR: 

* Enable OEM unlocking
* Obtain latest `fastboot`
* Unlock Bootloader:
  Enable usb debugging and execute `adb reboot bootloader`, or
      >The easiest approach is to reboot the device and begin holding the volume down button until it boots up into the bootloader interface.
   ```shell
   fastboot flashing unlock
   ```
* flash factory image

  ```shell
  tar xvf DEVICE_NAME-factory-VERSION.zip
  ./flash-all.sh # or .bat on windows
  ````
* Stop after that and reboot (leave bootloader unlocked)

#### Patch GrapheneOS with OTAs from this image

* Download the [OTA from releases](https://github.com/schnatterer/rooted-graphene/releases/) with **the same version** that you just installed. 
* Extract the partition images from the patched OTA that are different from the original.
    ```bash
    avbroot ota extract \
        --input /path/to/ota.zip.patched \
        --directory extracted
    ```
* Flash the partition images that were extracted.  
  For each partition inside `extracted/`, except for `system`, run:
    ```bash
    fastboot flash <partition> extracted/<partition>.img
    ```
* Then, reboot into recovery's fastbootd mode and flash `system`:
    ```bash
    fastboot reboot fastboot
    fastboot flash system extracted/system.img
    ```
* Set up the custom AVB public key in the bootloader.
    ```bash
    fastboot reboot-bootloader
    fastboot erase avb_custom_key
    curl -s https://raw.githubusercontent.com/schnatterer/rooted-graphene/main/avb_pkmd.bin > avb_pkmd.bin
    fastboot flash avb_custom_key avb_pkmd.bin
    ```
* **[Optional]** Before locking the bootloader, reboot into Android once to confirm that everything is properly signed.  
   Install the Magisk or KernelSU app and run the following command:
    ```bash
    adb shell su -c 'dmesg | grep libfs_avb'
    ```
   If AVB is working properly, the following message should be printed out:
    ```bash
    init: [libfs_avb]Returning avb_handle with status: Success
    ```
* Reboot back into fastboot and lock the bootloader. This will trigger a data wipe again.
    ```bash
    fastboot flashing lock
    ```
* Confirm by pressing volume down and then power. Then reboot.
* Remember: **Do not uncheck `OEM unlocking`!** 

#### Set up OTA updates

* [Disable system updater app](https://github.com/chenxiaolong/avbroot#ota-updates).
* You could either do updates manually using `adb sideload` (see [here](https://github.com/chenxiaolong/avbroot#updates)),
* or use the [Custota](https://github.com/chenxiaolong/Custota) magisk module.
* To do so, download and install the Custota module in magsik and reboot.
* Open Custota and set the OTA server URL to point to this OTA server:  https://schnatterer.github.io/rooted-graphene/magisk

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
GITHUB_REPO=schnatterer/rooted-graphene \
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
preinit["shiba"]="=sda10" # Pixel 8
```

How to extract:

* Get boot.img either from factory image or from OTA via
  ```shell
     avbroot ota extract \
     --input /path/to/ota.zip \
     --directory . \
     --boot-only
  ```
* Install magisk, patch boot.img, look for this string in the output:  
  `Pre-init storage partition device ID: <name>`
* Alternatively extract from the pachted boot.img: 
  ```shell
  avbroot boot magisk-info \
  --image magisk_patched-*.img
  ```
* See also: https://github.com/chenxiaolong/avbroot/blob/master/README.md#magisk-preinit-device


## References, Inspiration
https://github.com/MuratovAS/grapheneos-magisk/blob/main/docker/Dockerfile

https://xdaforums.com/t/guide-to-lock-bootloader-while-using-rooted-otaos-magisk-root.4510295/
