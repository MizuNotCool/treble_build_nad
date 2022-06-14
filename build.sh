#!/bin/bash
echo ""
echo "Miku UI SnowLand Unified Buildbot"
echo "Executing in 3 seconds - CTRL-C to exit"
echo ""

sleep 3
set -e

START=`date +%s`
BUILD_DATE="$(date +%Y%m%d)"
WITHOUT_CHECK_API=true
BL=$PWD/treble_build_miku
BD=$HOME/builds
VERSION="0.5.0"

syncrepo() {
if [ ! -d .repo ]
then
    echo "Initializing Miku UI workspace"
    repo init -u https://github.com/Miku-UI/manifesto -b snowland --depth=1
    echo ""
fi

if [ -d .repo ]
then
    if [ ! -d .repo/local_manifests ]
    then
     echo "Preparing local manifest"
     mkdir -p .repo/local_manifests
     cp ./treble_build_miku/local_manifests_treble/manifest.xml .repo/local_manifests/miku-treble.xml
     echo ""
    fi 
fi

echo "Syncing repos"
repo sync -c --force-sync --no-clone-bundle --no-tags -j$(nproc --all)
echo ""
}

applypatches() {
patches="$(readlink -f -- $1)"
tree="$2"

for project in $(cd $patches/patches/$tree; echo *);do
	p="$(tr _ / <<<$project |sed -e 's;platform/;;g')"
	[ "$p" == treble/app ] && p=treble_app
	[ "$p" == vendor/hardware/overlay ] && p=vendor/hardware_overlay
	pushd $p
	for patch in $patches/patches/$tree/$project/*.patch;do
		git am $patch || exit
	done
	popd
    done
}

applyingpatches() {
echo "Applying patches"
applypatches $BL phh
applypatches $BL personal
echo ""
}

initenvironment() {
echo "Setting up build environment"
source build/envsetup.sh &> /dev/null
mkdir -p $BD
echo ""

echo "Treble device generation"
rm -rf device/*/sepolicy/common/private/genfs_contexts
cd device/phh/treble
git clean -fdx
bash generate.sh miku
cd ../../..
echo ""
}

buildTrebleApp() {
    cd treble_app
    bash build.sh release
    cp TrebleApp.apk ../vendor/hardware_overlay/TrebleApp/app.apk
    cd ..
}

buildtreble() {
    lunch miku_treble_a64_bvS-userdebug
    make installclean
    make -j$(nproc --all) systemimage
    mv $OUT/system.img $BD/system-miku_treble_a64_bvS.img
    sleep 1
    lunch miku_treble_a64_bgS-userdebug
    make -j$(nproc --all) systemimage
    mv $OUT/system.img $BD/system-miku_treble_a64_bgS.img
}

buildSasImages() {
    cd sas-creator
    sudo bash lite-adapter.sh 64 $BD/system-miku_treble_a64_bvS.img
    cp s.img $BD/system-miku_treble_a64_bvS-vndklite.img
    sudo bash securize.sh s.img
    cp s-secure.img $BD/system-miku_treble_a64_bvS-vndklite-secure.img
    sudo rm -rf s.img  s-secure.img d tmp
    sudo bash lite-adapter.sh 64 $BD/system-miku_treble_a64_bgS.img
    cp s.img $BD/system-miku_treble_a64_bgS-vndklite.img
    sudo bash securize.sh s.img
    cp s-secure.img $BD/system-miku_treble_a64_bgS-vndklite-secure.img
    sudo rm -rf s.img  s-secure.img d tmp
    cd ..
}

generatePackages() {
    rm -rf $BD/MikuUI-*.img.xz
    BASE_IMAGE=$BD/system-miku_treble_a64_bvS.img
    xz -cv $BASE_IMAGE -T0 > $BD/MikuUI-SNOWLAND-$VERSION-a64-ab-$BUILD_DATE-UNOFFICIAL.img.xz
    xz -cv ${BASE_IMAGE%.img}-vndklite.img -T0 > $BD/MikuUI-SNOWLAND-$VERSION-a64-ab-vndklite-$BUILD_DATE-UNOFFICIAL.img.xz
    xz -cv ${BASE_IMAGE%.img}-vndklite-secure.img -T0 > $BD/MikuUI-SNOWLAND-$VERSION-a64-ab-vndklite-secure-$BUILD_DATE-UNOFFICIAL.img.xz
    BASE_IMAGE=$BD/system-miku_treble_a64_bgS.img
    xz -cv $BASE_IMAGE -T0 > $BD/MikuUI-SNOWLAND-$VERSION-a64-ab-gapps-$BUILD_DATE-UNOFFICIAL.img.xz
    xz -cv ${BASE_IMAGE%.img}-vndklite.img -T0 > $BD/MikuUI-SNOWLAND-$VERSION-a64-ab-vndklite-gapps-$BUILD_DATE-UNOFFICIAL.img.xz
    xz -cv ${BASE_IMAGE%.img}-vndklite-secure.img -T0 > $BD/MikuUI-SNOWLAND-$VERSION-a64-ab-vndklite-gapps-secure-$BUILD_DATE-UNOFFICIAL.img.xz
    rm -rf $BD/system-*.img
}

generateOtaJson() {
    prefix="MikuUI-SNOWLAND-$VERSION-"
    suffix="-$BUILD_DATE-UNOFFICIAL.img.xz"
    json="{\"version\": \"$VERSION\",\"date\": \"$(date +%s -d '-4hours')\",\"variants\": ["
    find $BD -name "*.img.xz" | {
        while read file; do
            packageVariant=$(echo $(basename $file) | sed -e s/^$prefix// -e s/$suffix$//)
            case $packageVariant in
                "a64-ab") name="miku_treble_a64_bvS";;
                "a64-ab-vndklite") name="miku_treble_a64_bvS-vndklite";;
                "a64-ab-vndklite-secure") name="miku_treble_a64_bvS-secure";;
                "a64-ab-gapps") name="miku_treble_a64_bgS";;
                "a64-ab-vndklite-gapps") name="miku_treble_a64_bgS-vndklite";;
                "a64-ab-vndklite-gapps-secure") name="miku_treble_a64_bgS-secure";;
            esac
            size=$(wc -c $file | awk '{print $1}')
            url="https://github.com/MizuNotCool/treble_build_miku/releases/download/$VERSION/$(basename $file)"
            json="${json} {\"name\": \"$name\",\"size\": \"$size\",\"url\": \"$url\"},"
        done
        json="${json%?}]}"
        echo "$json" | jq . > $BL/ota.json
        cp -r $BL/ota.json $BD/ota.json
    }
}

personal() {
  7z a -t7z -r $BD/all.7z $BD/*
  rm -rf $BD/*.img.xz
  rm -rf $BD/ota.json
}

syncrepo
applyingpatches
initenvironment
buildTrebleApp
buildtreble
buildSasImages
generatePackages
generateOtaJson
if [ $USER == xiaolegun ];then
personal
fi

END=`date +%s`
ELAPSEDM=$(($(($END-$START))/60))
ELAPSEDS=$(($(($END-$START))-$ELAPSEDM*60))
echo "Buildbot completed in $ELAPSEDM minutes and $ELAPSEDS seconds"
echo ""
