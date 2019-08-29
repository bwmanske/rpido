#!/bin/bash
# 
VERBOSE=1
RPI_ROOT=sdcard

CurlAddr=://downloads.raspberrypi.org/raspbian_full_latest
#CurlAddr=://downloads.raspberrypi.org/raspbian_latest
#CurlAddr=://downloads.raspberrypi.org/raspbian_lite_latest

 vecho() { [ $VERBOSE -lt 1 ] || echo $* >/dev/stderr; }
vvecho() { [ $VERBOSE -lt 2 ] || echo $* >/dev/stderr; }
SUDO() {
    vecho SUDO $*
    sudo $*
}

# Set SD var to the basename for first SD/MMC card
set_SD() 
{
    for d in /dev/sd[a-f] ;do
        if sudo gdisk -l $d 2>/dev/null| grep "^Model:.*SD/MMC">/dev/null; then
            SD=$(basename $d)
            break;
        fi
    done
}

# Associate LoopDevice with block device-associate Kernel device name to image file
loopdev_SD() {
    LoopDev=$(sudo losetup -f)              # set LoopDev to first available device
    SUDO losetup -P $LoopDev $LATEST.img    # create loop device
    SD=$(basename ${LoopDev}p)              # set SD var to loop device name
}

is_mounted() {
    mount | grep $(realpath $1) >/dev/null
}

# unmount the SD card or image - it may not be mounted but try anyway
unmount_SD() {
    for i in /sys/block/${SD}/${SD}?;do
        SUDO umount /dev/$(basename $i) 2>/dev/null
    done
}

# mount the SD card or image
mount_SD() {
    unmount_SD
    mkdir -p $RPI_ROOT
    SUDO mount /dev/${SD}2 $RPI_ROOT
    SUDO mount /dev/${SD}1 $RPI_ROOT/boot
}

# write the image in the .zip file to the SD card 
write_SD() {
    unmount_SD
    unzip -p $zipfile $LATEST.img | sudo dd of=/dev/${SD} bs=4M
}

# 
unmount_all() {
    [ ! -z "$RPI_ROOT" ] || return 1
    [ -z "$keep_mount" ] || return 0
    FULLPATH=$(realpath ${RPI_ROOT})
    LoopDev=$(mount | grep "/dev/loop[0-9]*p2.*$FULLPATH" | sed 's/p2.*$//')
    # SUDO rm -f ${RPI_ROOT}/usr/bin/qemu-arm-static 
    for p in $(mount | grep $FULLPATH | cut -f3 -d' ' | sort -Vr); do
        SUDO umount $p
    done
    for d in $LoopDev; do
        SUDO losetup -d $d
        #SUDO rm -f ${d}*
    done
}

# I had problems with the HTTPS request sometimes failing
# So I allow it to drop back to HTTP if it fails
get_first_URL() {
    echo "**** Trying HTTPS requet"
    CurlResult=$(curl -s https${CurlAddr})
    GrepResult=$(echo $CurlResult | grep -i '.zip')
    if [ "$?" != "0" ]; then
        echo "Curl HTTPS request failed"
        echo "**** Trying HTTP requet"
        CurlResult=$(curl -s http${CurlAddr})
        GrepResult=$(echo $CurlResult | grep -i '.zip')
        if [ "$?" != "0" ]; then
            echo "Curl HTTP request failed"
            return 1    # fail
        fi
    fi
    return 0     # success
}

# The URL has moved from past position - so search for it
find_URL () {
    local URL_found="f"
    local occurance
    local GrepResult
    for occurance in {1..6}
    do
        echo "trying HTTP occurance # $occurance"
        URL=$(echo $CurlResult | awk -F\" '/http/ { print $'$occurance'}')
        GrepResult=$(echo $URL | grep -i '.zip')
        if [ "$?" == "0" ]; then
            URL_found="t"
            break
        fi
    done

    if [ "$URL_found" == "t" ]; then
        return 0    # success
    else
        return 1    # fail
    fi
}

# Display usage instructions for this script
usage() {
    unmount_all
    set +x
    [ $# == 0 ] || echo $*
    echo "usage: rpido <options> cmd"
    echo " -w       write raspian to sdcard (default)"
    echo " -i       image file operations"
    echo " -h name  sets /etc/hostname on rpi"
    echo " -s       start shell on raspian"
    echo " -v       verbose - shell debug mode"
    echo " -q       quiet"
    echo " cmd      chroot rpi cmd"
    echo "installs files from template"
    echo "configures wifi and sshd, and authorized keys"
    exit 1
}

while getopts ?h:ikqsv opt;do
    case $opt in
    h) hostname=$OPTARG ;;
    i) use_image_file=y ;;
    k) keep_mount=y ;;
    q) VERBOSE=0 ;;
    s) rpi_shell=y ;;
    v) VERBOSE=$(($VERBOSE+1)) ;;
    *) usage ;;
    esac
done
shift $(($OPTIND-1))
[ $VERBOSE -lt 2 ] || set -x
if [ "$rpi_shell" = y ]; then
    CMD="bash -i"
else
    CMD="$*"
fi

# the given URL is a known redirect - we need the redirect filename URL
get_first_URL
[ "$?" != "0" ] && ( echo "failed to get URL $URL"; exit 1 )

echo "Looking for redirect URL"
find_URL
[ "$?" != "0" ] && ( echo "failed to find URL $URL"; exit 1 )

# The unique filename is now in URL var
echo "Found '.zip'"
echo "URL="$URL

# Get just the file name
LATEST=$(basename $URL .zip)
zipfile=DIST/$LATEST.zip

# If the zip file with this name is missing then get it
[ -f $zipfile ] || curl --create-dirs -o $zipfile -L $URL # use -L to follow redirects
[ "$?" != "0" ] && ( echo "Curl HTTP request failed"; exit 1 )


# The default is to write to the SD card
if [ -z "$use_image_file" ]; then
    # **** use SD card
    set_SD

    if [ -z "$SD" ]; then
        echo "No SD card detected"
        exit 1
    else
        write_SD
    fi
else
    # **** Use image file

    # If the image file with this name is missing then extract it
    [ -f "$LATEST.img" ] || unzip -x $zipfile $LATEST.img

    # find loop device to use as mount point for image file
    loopdev_SD
fi

# mount the image or SD card
mount_SD
if [ -z "${RPI_ROOT}" -o ! -f "$RPI_ROOT/etc/rpi-issue" -o ! -f "$RPI_ROOT/boot/issue.txt" ]; then
    usage raspbian root not as expected
fi

# Sync the template folder to the mounted filesystem
#SUDO rsync -a template/. $RPI_ROOT

# create a new hostname file 
[ -z "$hostname" ] || echo $hostname | sudo tee $RPI_ROOT/etc/hostname >/dev/null

# if a user entered a command from the command line execute it on the mounted file system
if [ ! -z "$CMD" ]; then
    SUDO rsync /usr/bin/qemu-arm-static ${RPI_ROOT}/usr/bin/
    for f in proc dev sys;do
        is_mounted $RPI_ROOT/$f || SUDO mount --bind /$f $RPI_ROOT/$f
    done
    SUDO chroot ${RPI_ROOT} $CMD
fi

# unmount all - unless the user has specified -k option
unmount_all

# tell the file system to catch up before exiting
sync
