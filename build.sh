#!/bin/bash
echo ""
echo "FluentOS Codename: Samurai Treble Buildbot"
echo "ATTENTION: this script syncs repo on each run"
echo "Executing in 5 seconds - CTRL-C to exit"
echo ""
sleep 5

# Abort early on error
set -eE
trap '(\
echo;\
echo \!\!\! An error happened during script execution;\
echo \!\!\! Please check console output for bad sync,;\
echo \!\!\! failed patch application, etc.;\
echo\
)' ERR

START=`date +%s`
BUILD_DATE="$(date +%Y%m%d)"
WITHOUT_CHECK_API=true
BL=$PWD/treble_fluent
BD=$HOME/builds

export FLUENT_BUILD_CODENAME=samurai

if [ ! -d .repo ]
then
    echo "Initializing FluentOS workspace"
    repo init -u https://github.com/FluentOS-Project/manifest -b samurai-gsi
    echo ""

    echo "Preparing local manifest"
    mkdir -p .repo/local_manifests
    cp $BL/manifest.xml .repo/local_manifests/fluent.xml
    echo ""
fi

echo "Syncing repos"
repo sync -c --force-sync --no-clone-bundle --no-tags -j$(nproc --all)
echo ""

echo "Setting up build environment"
source build/envsetup.sh &> /dev/null
mkdir -p $BD
echo ""

echo "Applying prerequisite patches"
bash $BL/apply-patches.sh $BL prerequisite
echo ""

echo "Applying PHH patches"
cd device/phh/treble
cp $BL/fluent.mk .
bash generate.sh fluent
cd ../../..
bash $BL/apply-patches.sh $BL phh
echo ""

echo "Applying personal patches"
bash $BL/apply-patches.sh $BL personal
echo ""

echo "Applying device specific patches"
bash $BL/apply-patches.sh $BL a40
echo ""

buildTrebleApp() {
    cd treble_app
    bash build.sh release
    cp TrebleApp.apk ../vendor/hardware_overlay/TrebleApp/app.apk
    cd ..
}

buildVariant() {
    lunch ${1}-userdebug
    make installclean
    make -j$(nproc --all) systemimage
    make vndk-test-sepolicy
    mv $OUT/system.img $BD/system-$1.img
    buildSlimVariant $1
    rm -rf out/target/product/phhgsi*
}

buildSlimVariant() {
    wget https://gist.github.com/ponces/891139a70ee4fdaf1b1c3aed3a59534e/raw/slim.patch -O /tmp/slim.patch
    (cd vendor/gapps && git am /tmp/slim.patch)
    lunch ${1}-userdebug
    make -j$(nproc --all) systemimage
    mv $OUT/system.img $BD/system-$1-slim.img
    (cd vendor/gapps && git reset --hard HEAD~1)
}

buildSasImages() {
    cd sas-creator
    sudo bash lite-adapter.sh 32 $BD/system-treble_a64_bvN.img
    cp s.img $BD/system-treble_a64_bvN-vndklite.img
    sudo bash lite-adapter.sh 64 $BD/system-treble_arm64_bvN.img
    cp s.img $BD/system-treble_arm64_bvN-vndklite.img
    sudo rm -rf s.img d tmp
    cd ..
}

generatePackages() {
    BASE_IMAGE=$BD/system-treble_a64_bvN.img
    xz -cv $BASE_IMAGE -T0 > $BD/FluentOS-$FLUENT_BUILD_CODENAME-12.0_arm32_binder64-ab-12.0-$BUILD_DATE-OFFICIAL.img.xz
    xz -cv ${BASE_IMAGE%.img}-vndklite.img -T0 > $BD/FluentOS-$FLUENT_BUILD_CODENAME-12.0_arm32_binder64-ab-vndklite-12.0-$BUILD_DATE-OFFICIAL.img.xz
    xz -cv ${BASE_IMAGE%.img}-slim.img -T0 > $BD/FluentOS-$FLUENT_BUILD_CODENAME-12.0_arm32_binder64-ab-slim-12.0-$BUILD_DATE-OFFICIAL.img.xz
    BASE_IMAGE=$BD/system-treble_arm64_bvN.img
    xz -cv $BASE_IMAGE -T0 > $BD/FluentOS-$FLUENT_BUILD_CODENAME-12.0_arm64-ab-12.0-$BUILD_DATE-OFFICIAL.img.xz
    xz -cv ${BASE_IMAGE%.img}-vndklite.img -T0 > $BD/FluentOS-$FLUENT_BUILD_CODENAME-12.0_arm64-ab-vndklite-12.0-$BUILD_DATE-OFFICIAL.img.xz
    xz -cv ${BASE_IMAGE%.img}-slim.img -T0 > $BD/FluentOS-$FLUENT_BUILD_CODENAME-12.0_arm64-ab-slim-12.0-$BUILD_DATE-OFFICIAL.img.xz
    rm -rf $BD/system-*.img
}

buildTrebleApp
buildVariant treble_a64_bvN
buildVariant treble_arm64_bvN
buildSasImages
generatePackages

END=`date +%s`
ELAPSEDM=$(($(($END-$START))/60))
ELAPSEDS=$(($(($END-$START))-$ELAPSEDM*60))
echo "Buildbot completed in $ELAPSEDM minutes and $ELAPSEDS seconds"
echo ""
