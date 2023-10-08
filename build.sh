#!/bin/bash

echo
echo "--------------------------------------"
echo "      Evolution X 13.0 Buildbot       "
echo "                  by                  "
echo "                ponces                "
echo "--------------------------------------"
echo

set -e

BL=$PWD/treble_build_evo
BD=$HOME/builds

initRepos() {
    if [ ! -d .repo ]; then
        echo "--> Initializing workspace"
        repo init -u https://github.com/Evolution-X/manifest -b udc
        echo

        echo "--> Preparing local manifest"
        mkdir -p .repo/local_manifests
        cp $BL/manifest.xml .repo/local_manifests/evo.xml
        echo
    fi
}

syncRepos() {
    echo "--> Syncing repos"
    repo sync -c --force-sync --no-clone-bundle --no-tags -j$(nproc --all)
    echo
}

applyPatches() {
    echo "--> Applying prerequisite patches"
    bash $BL/apply-patches.sh $BL prerequisite
    echo

    echo "--> Applying TrebleDroid patches"
    bash $BL/apply-patches.sh $BL trebledroid
    echo

    echo "--> Applying personal patches"
    bash $BL/apply-patches.sh $BL personal
    echo

    echo "--> Generating makefiles"
    cd device/phh/treble
    cp $BL/evo.mk .
    bash generate.sh evo
    cd ../../..
    echo
}

setupEnv() {
    echo "--> Setting up build environment"
    source build/envsetup.sh &>/dev/null
    mkdir -p $BD
    echo
}

buildTrebleApp() {
    echo "--> Building treble_app"
    cd treble_app
    bash build.sh release
    cp TrebleApp.apk ../vendor/hardware_overlay/TrebleApp/app.apk
    cd ..
    echo
}

buildVariant() {
    echo "--> Building treble_arm64_bvN"
    lunch treble_arm64_bvN-userdebug
    make -j$(nproc --all) installclean
    make -j$(nproc --all) systemimage
    mv $OUT/system.img $BD/system-treble_arm64_bvN.img
    echo
}

buildMiniVariant() {
    echo "--> Building treble_arm64_bvN-mini"
    (cd vendor/evolution && git am $BL/patches/mini.patch)
    make -j$(nproc --all) systemimage
    (cd vendor/evolution && git reset --hard HEAD~1)
    mv $OUT/system.img $BD/system-treble_arm64_bvN-mini.img
    echo
}

buildPicoVariant() {
    echo "--> Building treble_arm64_bvN-pico"
    (cd vendor/evolution && git am $BL/patches/pico.patch)
    make -j$(nproc --all) systemimage
    (cd vendor/evolution && git reset --hard HEAD~1)
    mv $OUT/system.img $BD/system-treble_arm64_bvN-pico.img
    echo
}

buildVndkliteVariant() {
    echo "--> Building treble_arm64_bvN-vndklite"
    cd sas-creator
    sudo bash lite-adapter.sh 64 $BD/system-treble_arm64_bvN.img
    cp s.img $BD/system-treble_arm64_bvN-vndklite.img
    sudo rm -rf s.img d tmp
    cd ..
    echo
}

generatePackages() {
    echo "--> Generating packages"
    buildDate="$(date +%Y%m%d)"
    xz -cv $BD/system-treble_arm64_bvN.img -T0 > $BD/evolution_arm64-ab-7.9.8-unofficial-$buildDate.img.xz
    xz -cv $BD/system-treble_arm64_bvN-vndklite.img -T0 > $BD/evolution_arm64-ab-vndklite-7.9.8-unofficial-$buildDate.img.xz
#    xz -cv $BD/system-treble_arm64_bvN-mini.img -T0 > $BD/evolution_arm64-ab-mini-7.9.8-unofficial-$buildDate.img.xz
#    xz -cv $BD/system-treble_arm64_bvN-pico.img -T0 > $BD/evolution_arm64-ab-pico-7.9.8-unofficial-$buildDate.img.xz
    rm -rf $BD/system-*.img
    echo
}

generateOta() {
    echo "--> Generating OTA file"
    version="$(date +v%Y.%m.%d)"
    timestamp="$START"
    json="{\"version\": \"$version\",\"date\": \"$timestamp\",\"variants\": ["
    find $BD/ -name "evolution_*" | sort | {
        while read file; do
            filename="$(basename $file)"
            if [[ $filename == *"vndklite"* ]]; then
                name="treble_arm64_bvN-vndklite"
            elif [[ $filename == *"mini"* ]]; then
                name="treble_arm64_bvN-mini"
            elif [[ $filename == *"pico"* ]]; then
                name="treble_arm64_bvN-pico"
            else
                name="treble_arm64_bvN"
            fi
            size=$(wc -c $file | awk '{print $1}')
            url="https://github.com/ponces/treble_build_evo/releases/download/$version/$filename"
            json="${json} {\"name\": \"$name\",\"size\": \"$size\",\"url\": \"$url\"},"
        done
        json="${json%?}]}"
        echo "$json" | jq . > $BL/ota.json
    }
    echo
}

START=$(date +%s)

initRepos
syncRepos
applyPatches
setupEnv
buildTrebleApp
buildVariant
#buildMiniVariant
#buildPicoVariant
buildVndkliteVariant
generatePackages
#generateOta

END=$(date +%s)
ELAPSEDM=$(($(($END-$START))/60))
ELAPSEDS=$(($(($END-$START))-$ELAPSEDM*60))

echo "--> Buildbot completed in $ELAPSEDM minutes and $ELAPSEDS seconds"
echo
