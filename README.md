rooted-graphene
===


GrapheneOS over the air updates (OTAs) patched with Magisk using [avbroot](https://github.com/chenxiaolong/avbroot) allowing for AVB and locked bootloader *and* root access.
Provides its own OTA server for [Custota](https://github.com/chenxiaolong/Custota) magisk module.

> ⚠️ OS and root work in general. However, zygisk does not (and [likely never will](https://github.com/topjohnwu/Magisk/pull/7606)) work, leading to magisk being easily discovered by other apps and lots of banking apps not working.  
 See [bellow](#using-other-rooting-mechanisms) for alternatives.

## Usage

## Initial installation of OS

### Hints 
* Make sure the versions of the unpatched version initially installed and the one taken from this repo match.
* You might want to start with the version before the latest to try if OTA is working before initializing your device.
* Don't mix up **factory image** and OTA
* The following steps are basically the ones described at [avbroot](https://github.com/chenxiaolong/avbroot#initial-setup) using the `avb_pkmd.bin` from this repo.

### Installation

#### Install GrapheneOS

##### Web Installer

Using the web installier is easier, but will always install the latest version. 
So it's not possible to verify if OTA upgrades work right away.

Use the [web installer](https://grapheneos.org/install/web) to install GrapheneOS:
* Write down the installed version, e.g. `Downloaded caiman-install-2024123000.zip release`.
* Stop at `Locking the bootloader` and close the browser. 
  We'll lock the bootloader later!

##### Manual install

Alternative method to Web installer.

Download [**factory image**](https://grapheneos.org/releases) and follow the [official instructions](https://grapheneos.org/install/cli)  to install GrapheneOS.

TLDR:

* Enable OEM unlocking
* Obtain latest `fastboot`
* Unlock Bootloader:
  Enable usb debugging and execute `adb reboot bootloader`, or
  > The easiest approach is to reboot the device and begin holding the volume down button until it boots up into the bootloader interface.
   ```shell
   fastboot flashing unlock
   ```
* flash factory image

  ```shell
  bsdtar xvf DEVICE_NAME-factory-VERSION.zip # tar on windows and mac
  ./flash-all.sh # or .bat on windows
  ````
* Stop after that and reboot (leave bootloader unlocked)

#### Patch GrapheneOS with OTAs from this image

Once GrapheneOS is installed

* Download the [OTA from releases](https://github.com/schnatterer/rooted-graphene/releases/) with **the same version** that you just installed. 
* Obtain latest `fastboot`
* Install [avbroot](https://github.com/chenxiaolong/avbroot)
* Extract the partition images from the patched OTA that are different from the original.
    ```bash
    avbroot ota extract \
        --input /path/to/ota.zip.patched \
        --directory extracted \
        --fastboot
    ```
* Set this environment variable to match the extracted folder:

  For Linux/macOS:
  ```bash
  export ANDROID_PRODUCT_OUT=extracted
  ```

  For Windows (powershell):
  ```powershell
  $env:ANDROID_PRODUCT_OUT = "extracted"
  ```
  or (bat):
  ```bat
  set ANDROID_PRODUCT_OUT=extracted
  ```

* Flash the partitions using the command:
  ```bash
  fastboot flashall --skip-reboot
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
  That is, in Graphene's startup wizard, leave this box unticked 👇️
  <img src="https://github.com/schnatterer/rooted-graphene/assets/1824962/6ef90b46-2070-4d08-80d4-5f4a0e749cbe" width="216" height="480" alt="Screenshot of GrapheneOS recommending to lock">


#### Set up OTA updates

* [Disable system updater app](https://github.com/chenxiaolong/avbroot#ota-updates).
* Use the [Custota](https://github.com/chenxiaolong/Custota) magisk module.
  * To do so, download and install the Custota module in magsik and reboot.
  * Open Custota and set the OTA server URL to point to this OTA server:  https://schnatterer.github.io/rooted-graphene/magisk
* Alternatively you could do updates manually via `adb sideload`:
  * reboot the device and begin holding the volume down button until it boots up into the bootloader interface
  * using volume buttons, toggle to recovery. Confirm by pressing power button
  * If the screen is stuck at a `No command` message, press the volume up button once while holding down the power button.
  * using volume buttons, toggle to `Apply update from ADB`. Confirm by pressing power button
  * `adb sideload xyz.zip`
  * See also [here](https://github.com/chenxiaolong/avbroot#updates).

## Remove root / rootless

In order to remove root, you can change to the "rootless" flavor.

To do so, set the following URL in custota: https://schnatterer.github.io/rooted-graphene/rootless/

Note that you can update to this flavor to disable root. However, after the upgrade, custota will no longer work. For re-enabling root, you will have to use `adb sideload`.

In the future we might find a way to include an updater to the OTA, so rooting will also be possible via custota.

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

See GitHub actions for automating this:
* [release single device](.github/workflows/release-single.yaml)
* [release multiple devices](.github/workflows/release-multiple.yaml) regularly (using cron)

```shell
GITHUB_TOKEN=gh... \
GITHUB_REPO=schnatterer/rooted-graphene \
DEVICE_ID=oriole \
MAGISK_PREINIT_DEVICE=metadata \
bash -c '. rooted-ota.sh && createAndReleaseRootedOta'
```

### Using other rooting mechanisms

As [magisk does not seem a perfect match for GrapheneOS](https://github.com/topjohnwu/Magisk/pull/7606), you might be looking for alternatives.

I had a first go at [patching kernelsu](https://github.com/schnatterer/rooted-graphene/commit/201b6dc939ab3a202694fa892de6db2840e5c3d6) which booted but did not provide root. 
There even are some [artifacts](https://github.com/schnatterer/rooted-graphene/releases/tag/2024042100) to try. 

Patching kernelsu is much more complex that patching magisk. 
It might even be impossible to run GrapheneOS with it, without building GrapheneOS from scratch.

Also, some parts of kernelsu seem to be closed source, which feels suspicious and inappropriate for a tool with so much influence on your device.

Another alternative might be to use a version of magisk (like [the one maintained by pixincreate](https://github.com/pixincreate/Magisk)) that contains patches to make zygisk work.  
This still has some limitations, like [certain modules checking for magisk's signature won't work](https://github.com/schnatterer/rooted-graphene/commit/da0cd817c2665798df46df1aeb7caef9d98b79d0#r141746606). 

In general, using [magisk and especially zygisk with Graphene seems to have the risk of breaking things with every new release](https://github.com/chenxiaolong/avbroot/issues/213#issuecomment-1986637884).  
It's good to have the rootless version as a fallback! 

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
GITHUB_REPO=schnatterer/rooted-graphene \
  bash -c '. rooted-ota.sh && releaseOta'

# Test only GH pages deployment
GITHUB_REPO=schnatterer/rooted-graphene \
DEVICE_ID=oriole \
MAGISK_PREINIT_DEVICE=metadata \
  bash -c '. rooted-ota.sh && findLatestVersion && checkBuildNecessary && createOtaServerData && uploadOtaServerData'


# e2e test
  GITHUB_TOKEN=gh... \
GITHUB_REPO=schnatterer/rooted-graphene \
DEVICE_ID=oriole \
MAGISK_PREINIT_DEVICE=metadata \
SKIP_CLEANUP=true \
DEBUG=1 \
  bash -c '. rooted-ota.sh && createAndReleaseRootedOta'
```

## Magisk preinit strings

See [release-multiple.yaml](.github/workflows/release-multiple.yaml) for examples.

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
