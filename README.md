rooted-graphene
===

GrapheneOS over the air updates (OTAs) patched with Magisk allowing for AVB and locked bootloader *and* root access.  
Can be upgraded over the air using [Custota](https://github.com/chenxiaolong/Custota) and its own OTA server.  
Allows for switching between magisk and rootless via OTA upgrades.

> ⚠️ OS and root work in general. However, zygisk does not (and [likely never will](https://github.com/topjohnwu/Magisk/pull/7606)) 
> work, leading to magisk being easily discovered by other apps and lots of banking apps not working.  
 See [bellow](#using-other-rooting-mechanisms) for alternatives.

## Supported devices

See [rooted-graphene/ota | .github/workflows/release-multiple.yaml](https://github.com/rooted-graphene/ota/blob/main/.github/workflows/release-multiple.yaml).

I plan to support as many devices as the GitHub Action limit allows for as long as this project is useful to me.

If you would like to see more devices, add them via PR to the file mentioned above.  
Alternatively, it's easy to [set up your own builds](#setting-up-your-own-ota-builds), which also makes you the owner of the signing keys.

If this project is useful to you, please consider **[donating to GrapheneOS](https://grapheneos.org/donate)**.  
Please note that rooted-graphene is not an official GrapheneOS project.  
As they do most of the heavy lifting, I think they deserve every support they can get.

## Notable changelog

These are only changes related to rooted-graphene, not GrapheneOS itself.  
See [grapheneos.org/releases](https://grapheneos.org/releases) for that.

### 2025032500

The OTA builds moved into a separate GitHub organization to get full GitHub action minutes budget.  
With this, it is possible to add support for [devices discontinued lately](#2025030200) again 🥳.

> ⚠️ You need to change the OTA server url in custota app to either  
> https://rooted-graphene.github.io/ota/magisk  
> or  
> https://rooted-graphene.github.io/ota/rootless

Note that the old URL https://schnatterer.github.io/rooted-graphene/ will no longer receive new OTAs soon.

Some more details:
* A GitHub organization has 2000 free GitHub Action Minutes per month.
* Each device build takes 10 Minutes.
* There are about 4 stable releases per month.
* The budget should last for the current devices and even provide room to support more 🥳  

### 2025030200

* Discontinued some devices (Pixel 8 Pro (husky), Pixel 8 (shiba), Pixel 6a (bluejay)), because the amount of GitHub actions minutes required for 
  maintaining that many devices exceed my spending limit.  
  Please fork this repo and build your own OTAs (see [Supported Devices](#supported-devices)).  
  ![image](https://github.com/user-attachments/assets/11cf8fe9-b846-4979-8d7c-723408681354)
* Switch from custota signature file version 1 to 2 (introduced with [custota 5](https://github.com/chenxiaolong/Custota/blob/v5.0/CHANGELOG.md) in october 2024)
* If you're using custoa magisk module version < 5, please upgrade.  
  Even better: Delete custota magisk module, because it is now packaged in the OTA.

### 2025021100
* Start shipping custota app with OTA
* This allows for OTA updates even when rootless and relieves you of the burden to keep the magisk module up to date.  
  Starting with the next version, this will allow you to switch root and off by installing OTA updates!
* In the `-magisk` flavor of rooted-graphene, the custota magisk module should be automatically disabled 
  on start. You can safely remove it. Custota is now a system app.
* In the `-rootless` flavor the custota should be new, so no problems.  
  Except when you had it installed as magisk module before (using the `-magisk` flavor).  
  Then you should `adb sideload` the  `-magisk` first. Then custota should work as a system app.
  Then you should be able to switch to `-rootless` with custota working.
  Here are some troubleshooting tipps.
  * test, if an upgrading works by long pressing `Version` in custota and then selecting `Allow reinstall`.  
    This way you can also switch from `-magisk` to `-rootless` (and back if everything works as planned).
  * you might have to change ownership or delete these files:
    * `/sdcard/Android/data/com.chiller3.custota/`
    * `/data/ota_packagecare_map.pb`
  * If you no longer have root, you can always delete modules using `adb`, see [#82](https://github.com/schnatterer/rooted-graphene/issues/82).

## Initial installation of OS

### Hints 
* Make sure the versions of the unpatched version initially installed and the one taken from this repo match.
* You might want to start with the version before the latest to try if OTA is working before initializing your device.
* Don't mix up **factory image** and OTA
* The following steps are basically the ones described at [avbroot](https://github.com/chenxiaolong/avbroot#initial-setup)
  using the `avb_pkmd.bin` from [this repo](https://github.com/rooted-graphene/ota/).

### Installation

> ⚠️ In case you encounter an error on boot saying `Device is corrupt. It can't be trusted` you
> * might be able to bypass it by pressing the power button or
> * could try flashing the rootless variant first and then  
>   either flash/sideload the rooted variant (again) or [switch to root via OTA](#switching-between-root-and-rootless).
> 
> See [#89](https://github.com/schnatterer/rooted-graphene/issues/89) and [#96](https://github.com/schnatterer/rooted-graphene/issues/96) for details. 

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
    curl -s https://raw.githubusercontent.com/rooted-graphene/ota/refs/heads/main/avb_pkmd.bin > avb_pkmd.bin
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
* Remember: **Do not uncheck `OEM unlocking`!** (to avoid [hard-bricking](https://github.com/chenxiaolong/avbroot/blob/v3.12.0/README.md#warnings-and-caveats))  
  That is, in Graphene's startup wizard, leave this box unticked 👇️  
  <img src="https://github.com/schnatterer/rooted-graphene/assets/1824962/6ef90b46-2070-4d08-80d4-5f4a0e749cbe" width="216" height="480" alt="Screenshot of GrapheneOS recommending to lock">  
  Note: The OTA contains [OEMUnlockOnBoot](https://github.com/chenxiaolong/OEMUnlockOnBoot), so OEM locking should be impossible.  
  Still, better safe than sorry, keep it unlocked.

#### Set up OTA updates

* [Disable system updater app](https://github.com/chenxiaolong/avbroot#ota-updates).
* Open Custota app and set the OTA server URL to point to this OTA server: https://rooted-graphene.github.io/ota/magisk

Alternatively you could do updates manually via `adb sideload`:
* reboot the device and begin holding the volume down button until it boots up into the bootloader interface
* using volume buttons, toggle to recovery. Confirm by pressing power button
* If the screen is stuck at a `No command` message, press the volume up button once while holding down the power button.
* using volume buttons, toggle to `Apply update from ADB`. Confirm by pressing power button
* `adb sideload xyz.zip`
* See also [here](https://github.com/chenxiaolong/avbroot#updates).

## Switching between root and rootless

To remove root, you can change to the "rootless" flavor.

To do so, set the following URL in custota: https://rooted-graphene.github.io/ota/rootless/
And then upgrade.  
(if custota should tell you that you're on the latest version, you can force an upgrade by long pressing `Version` and 
then selecting `Allow reinstall`).

If you want to gain root again, just switch back to this URL in custota: https://rooted-graphene.github.io/ota/magisk/
And then upgrade.

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
* Alternatively, extract from the patched boot.img: 
  ```shell
  avbroot boot magisk-info \
  --image magisk_patched-*.img
  ```
* See also: https://github.com/chenxiaolong/avbroot/blob/master/README.md#magisk-preinit-device

## Setting up your own OTA builds

* Create your own keys `bash -c 'source rooted-ota.sh && generateKeys'` and store them in a dry and safe place.
* Fork the [ota repo](https://github.com/rooted-graphene/ota) and add the following Repository secrets (`https://github.com/$YOU/$YOUR_REPO/settings/secrets/actions`)
  * CERT_OTA_BASE64 (`base64 -w0 < ota.crt`)
  * KEY_AVB_BASE64 (`base64 -w0 < avb.key`)
  * KEY_OTA_BASE64 (`base64 -w0 < ota.key`)
  * PASSPHRASE_AVB (The passphrase for `avb.key`)
  * PASSPHRASE_OTA (The passphrase for `ota.key`)
* Uncomment or add your device(s) in `.github/workflows/release-multiple.yaml`
  See [Magisk preinit string](#magisk-preinit-strings).

This sets up a cron job that builds the latest version of GrapheneOS, nightly.

This way, you won't have too many maintenance efforts but own your own signing key!  
You can also add a 3rd-party-magisk package if you're willing to trust the authors
(see [Using other rooting mechanisms](#using-other-rooting-mechanisms)).

Alternatively, search the forks if someone maintains the device of your choice.    
Be aware that you would also have to trust them in addition to [me](https://github.com/schnatterer), [chenxiaolong](https://github.com/chenxiaolong) (the author of avbroot and Custota),
the authors of magisk, the authors of GrapheneOS, and the authors of the android open source project.

## Script

You can use the `rooted-ota.sh` script in this repo to create your own OTAs and run your own OTA server.

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
* [release multiple devices](https://github.com/rooted-graphene/ota/blob/main/.github/workflows/release-multiple.yaml) regularly (using cron)

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
Patching kernelsu is much more complex that patching magisk.
It might even be impossible to run GrapheneOS with it, without building GrapheneOS from scratch.
Also, some parts of kernelsu seem to be closed source, which feels suspicious and inappropriate for a tool with so much influence on your device.

Another alternative might be to use a version of magisk (like [the one maintained by pixincreate](https://github.com/pixincreate/Magisk)) that contains patches to make zygisk work.  
This still has some limitations, like [certain modules checking for magisk's signature won't work](https://github.com/schnatterer/rooted-graphene/commit/da0cd817c2665798df46df1aeb7caef9d98b79d0#r141746606).

Another option [might be](https://github.com/schnatterer/rooted-graphene/pull/73#issuecomment-2666870886) Kitsune magisk.

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

# Test only patching
  export PASSPHRASE_AVB=x PASSPHRASE_OTA=y
SKIP_CLEANUP=true DEVICE_ID=oriole MAGISK_PREINIT_DEVICE='metadata' bash -c '. rooted-ota.sh && createRootedOta'

# Test only releasing
  GITHUB_TOKEN=gh... \
 DEBUG=true \
GITHUB_REPO=schnatterer/rooted-graphene \
OTA_VERSION=2025021100 \
RELEASE_ID='' \
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

## References, Inspiration
https://github.com/MuratovAS/grapheneos-magisk/blob/main/docker/Dockerfile

https://xdaforums.com/t/guide-to-lock-bootloader-while-using-rooted-otaos-magisk-root.4510295/
