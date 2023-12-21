rooted-graphene
===

Script for creating GrapheneOS over the air updates (OTAs) patched with Magisk using [avbroot](https://github.com/chenxiaolong/avbroot).

Eventually this should provide its own OTA server via [Custota](https://github.com/chenxiaolong/Custota).

## Obtain patched OTAs

```shell
# Generate keys
bash -c 'source rooted-graphene.sh && generateKeys'

# Enter passphrases interactively
GRAPHENE_ID=oriole MAGISK_PREINIT_DEVICE='metadata' bash -c '. rooted-graphene.sh && createRootedGraphene'  
 
# Enter passphrases via env (e.g. on CI)
  export PASSPHRASE_AVB=1
  export PASSPHRASE_OTA=1 
GRAPHENE_ID=oriole MAGISK_PREINIT_DEVICE='metadata' bash -c '. rooted-graphene.sh && createRootedGraphene' 
```

For IDs see [grapheneos.org/releases](https://grapheneos.org/releases). For Magisk preinit see,e.g. [here](#magisk-preinit-strings).

## Upload patched OTAs as GitHub release

```shell
GITHUB_TOKEN=gh... \
GITHUB_REPO=schnatterer/rooted-graphene \
GRAPHENE_ID=oriole \
MAGISK_PREINIT_DEVICE=metadata \
bash -c '. rooted-graphene.sh && releaseRootedGraphene'
```

## Development
```bash
# DEBUG some parts of the script interactively
DEBUG=1 bash --init-file rooted-graphene.sh

# Test loading secrets from env
PASSPHRASE_AVB=1 PASSPHRASE_OTA=1 bash -c '. rooted-graphene.sh && key2base64 && KEY_AVB=doesnotexist releaseRootedGraphene'        

# Avoid having to download OTA all over again: SKIP_CLEANUP=true or:
mkdir -p .tmp && ln -s $PWD/shiba-ota_update-2023121200.zip .tmp/shiba-ota_update-2023121200.zip

# Test releasing
  export GITHUB_TOKEN=gh...
export RELEASE_ID=''
export ASSET_EXISTS=false
export POTENTIAL_RELEASE_NAME=test
export POTENTIAL_ASSET_NAME=test.zip
export GITHUB_REPO=schnatterer/rooted-graphene
  bash -c '. rooted-graphene.sh && releaseOta'


# e2e test
  GITHUB_TOKEN=gh... \
GITHUB_REPO=schnatterer/rooted-graphene \
GRAPHENE_ID=oriole \
MAGISK_PREINIT_DEVICE=metadata \
SKIP_CLEANUP=true \
DEBUG=1 \
  bash -c '. rooted-graphene.sh && releaseRootedGraphene'
```

## Magisk preinit strings

```shell
preinit["cheetah"]="persist" # Pixel Pro 7 https://xdaforums.com/t/guide-to-lock-bootloader-while-using-rooted-grapheneos-magisk-root.4510295/page-5#post-88499289)
preinit["oriole"]="=metadata" # Pixel 6
```


## References, Inspiration
https://github.com/MuratovAS/grapheneos-magisk/blob/main/docker/Dockerfile

https://xdaforums.com/t/guide-to-lock-bootloader-while-using-rooted-grapheneos-magisk-root.4510295/

## Future work: Hosting your own update server on GitHub (pages)

Building from source will likely not work on GitHub, because of huge amount of RAM, CPU time and storage needed.

Alternative idea

https://github.com/chenxiaolong/Custota - can we host on github pages after all?

Former idea:

* Build own update client app and inject into system.img
  * https://github.com/GrapheneOS/platform_packages_apps_Updater/blob/14/res/values/config.xml 
  * For building, we will need this 
    * `source build/envsetup.sh`
    * https://github.com/GrapheneOS/platform_build/blob/14/envsetup.sh
    * https://grapheneos.org/build
    * https://source.android.com/docs/setup/build/building
  * The APK needs to be signed with the system sign key to be recognized as a system app.
    Might work with this: https://github.com/erfanoabdi/ROM_resigner
  * Example for generating a signing key: keytool -genkey -v -keystore vanadium.keystore -storetype pkcs12 -alias vanadium -keyalg RSA -keysize 4096 -sigalg SHA512withRSA -validity 10000 -dname "cn=GrapheneOS"
  * Then add to system.img: `mount` and replace updater?
  * Finally, replace system.img in OTA https://github.com/chenxiaolong/avbroot#replacing-partitions
* Hosting update server
  * release signing script generates the necessary metadata alongside the release file: https://grapheneos.org/build#update-server
  * Example:  https://releases.grapheneos.org/shiba-stable
    `2023121200 1702410493 shiba stable`
    Points to this file: `shiba-ota_update-2023121200.zip`
  * Unfortunately, hosting the whole page on GH pages won't work, because of size limits.
    https://docs.github.com/en/repositories/working-with-files/managing-large-files/about-large-files-on-github
  * The artifacts could be hosted in a release, though: 2gb per file max
  * Is it possible to link from release page to a binary that is somewhere else? Not relative to the page?

-> Sounds like some dev effort and unsure if it will work at all.

Also feels fragile, might change with every (major) android version
