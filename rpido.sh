#!/bin/bash
# 

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
    [ "$keep_mount"=="y" ] || return 0
    FULLPATH=$(realpath ${RPI_ROOT})
    LoopDev=$(mount | grep "/dev/loop[0-9]*p2.*$FULLPATH" | sed 's/p2.*$//')
    # SUDO rm -f ${RPI_ROOT}/usr/bin/qemu-arm-static 
    for p in $(mount | grep $FULLPATH | cut -f3 -d' ' | sort -Vr); do
        SUDO umount $p
    done
    for d in $LoopDev; do
        SUDO losetup -d $d
        #SUDO rm -f ${d}*  # in the original script - what for?
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
    for occurance in {1..6}; do
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

# create a config file template
config_template() {
    cat > $MY_INC_DIR/rpido-configX.sh << CONFIG_END
#!/bin/bash

# add the settings here
read_config_settings() {
    # URL for the Rasbian Image Download - uncomment one
    #CurlAddr=$CurlAddrFull         # link to Raspbian Full link (largest download)
    #CurlAddr=$CurlAddrNormal       # link to Raspbian link
    #CurlAddr=$CurlAddrLite         # Link to Raspbian Lite link (smallest download)

}

# main part of the file use for file description
echo -e "This config file is the template.\n"
echo -e "Addidional Details:"
echo -e "You Need to:"
echo -e " - change the capital X in the filename to a number between 1 and 9."
echo -e " - put you config discription here"
echo -e " - uncomment the CurlAddr for one of the raspbian distros."
echo -e "\n   ...   more to come   ..."
CONFIG_END
    chmod +x "$MY_INC_DIR/rpido-configX.sh"
    if [ "$?" == "0" ]; then            #check the return status of chmod
        echo "Template File $MY_INC_DIR/rpido-configX.sh created and made executable."
    fi
    sync
    exit 1
}

# Display usage instructions for this script
usage() {
    unmount_all
    set +x
    [ $# == 0 ] || echo $*
    echo    "usage: rpido <options> cmd"
    echo    " -c #     use config #=1..9  0-show descriptions from config files"
    echo    " -w       write raspian to sdcard (default)"
    echo    " -i       image file operations"
    echo    " -h name  sets /etc/hostname"
    echo    " -H #     #=2..9  number of sdcard images with hostname numbered"
    echo -e " -u ver   Rasbian version valid options \"full\", \"normal\" (default), \"lite\""
    echo    " -s       start shell on raspian"
    echo -e " -t       copy directory \"template\\\" to sdcard / image"
    echo    " -v       verbose - shell debug mode"
    echo    " -q       quiet"
    echo    " cmd      chroot rpi cmd"
    sync
    exit 1
}

#*************************************
# the script execution begins here
#*************************************
set +x   #tyrn on debug level info

# Initializations
MY_INC_DIR=$(dirname $(readlink -f $0))   # save the directory the script started in

VERBOSE=1                   # start with medium console out setting
RPI_ROOT=sdcard             # default to working with the SD Card
config_num=-1               # -1 if not used on the commandline
hostcount=0                 # 0 indicates no multiple images
keep_mount=n

# these are the URLs to the image filel downloads.
CurlAddrFull=://downloads.raspberrypi.org/raspbian_full_latest
CurlAddrNormal=://downloads.raspberrypi.org/raspbian_latest
CurlAddrLite=://downloads.raspberrypi.org/raspbian_lite_latest

CurlAddr=$CurlAddrNormal    # default to the middle sized image


while getopts ?c:h:H:ikqstu:v opt;do
    case $opt in
    c) config_num=$OPTARG ;;
    h) hostname=$OPTARG ;;
    H) hostcount=$OPTARG ;;
    i) use_image_file=y ;;
    k) keep_mount=y ;;
    q) VERBOSE=0 ;;
    s) rpi_shell=y ;;
    t) use_template=y ;;
    u) Rasbian_version=$OPTARG ;;
    v) VERBOSE=$(($VERBOSE+1)) ;;
    *) usage ;;
    esac
done
shift $(($OPTIND-1))              # remove used options

[ $VERBOSE -lt 2 ] || set -x      # turn off script debug if VERBOSE < 2
                                  # regular output if VERBOSE = 1
                                  # Quiet operation if VERBOSE = 0

# set the curl address based on the requested version
case $($Rasbian_version,,) in
full)   CurlAddr=$CurlAddrFull          # select the fill image
normal) CurlAddr=$CurlAddrNormal        # select the normal image
lite)   CurlAddr=$CurlAddrLite          # select the lite image
*) usage invalid Rasbian selection ;;   # show usage error and exit
esac

# check for hostcount conflicts
if [ $hostcount -ne 0 ]; then
    # hostcount was set so check for valid settings

    # check for value in range
    if [[ ( $hostcount<=1 ) && ( $hostcount>=10 ) ]]; then
        usage invalid number of host images selected 
    fi

    # make sure a host name was entered
    if [ -z hostname ]; then
        usage to get multiple host images specify a host name
    fi

    # not allowed to keep a mount if requesting multiple images
    if [ "$keep_mount" == 'y' ]; then
        usage the -k keep_mount option can not be used with multi host image
    fi
fi

# check for a requested config file
if [ $config_num!=-1 ]; then         # no config command line parameter so skip this
    files_found=0
    if [ $config_num -eq 0 ]; then
        # test each possible file name
        for i in {1..9}; do
            # Print the number and description for each existing file
            MY_INC_FILE=$MY_INC_DIR/rpido-config$i.sh
            if [ -e $MY_INC_FILE ]; then
                files_found=$(($files_found+1))
                echo "Config File #$i found"
                . $MY_INC_FILE     # run the script to show the description
            fi
        done
        # if no files were found create a template file if it doesn't exist already
        if [[( $files_found==0 ) && ( ! -e $MY_INC_DIR/"rpido-configX.sh" )]]; then
            config_template
        fi
        exit 1
    else
        if [[ ( $config_num -ge 1 ) && ( $config_num -le 9 ) ]]; then
            # number is valid - build the config file name 
            MY_INC_FILE=rpido-config$config_num.sh
        else
            usage illegal config number    # usage forces an exit
        fi
    fi

    #include the indicated file if it can be found
    if [ -e $MY_INC_DIR/$MY_INC_FILE ]; then
        echo "Config File #$config_num found"
        chmod +x $MY_INC_DIR/$MY_INC_FILE
        . $MY_INC_DIR/$MY_INC_FILE
        read_config_settings
    else
        echo "Config File #$config_num does not exist"
        exit 1
    fi
fi

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
    if [[ ( $hostcount -ne 0 ) && ( -z $hostname) ]]; then
        # for multiple image handling number the image file
        [ -f $LATEST"1.img" ] || unzip -x $zipfile $LATEST"1.img"
    else
        [ -f "$LATEST.img" ] || unzip -x $zipfile $LATEST.img
    fi

    # find loop device to use as mount point for image file
    loopdev_SD
fi

# mount the image or SD card
mount_SD
if [ -z "${RPI_ROOT}" -o ! -f "$RPI_ROOT/etc/rpi-issue" -o ! -f "$RPI_ROOT/boot/issue.txt" ]; then
    usage raspbian root not as expected
fi

# Sync the template folder to the mounted filesystem
if [ "$use_template" = y ]; then
    SUDO rsync -a template/. $RPI_ROOT
fi

# create a new hostname file 
if [ -z "$hostname" ]; then
    if [ $hostcount -eq 0]; then
        echo $hostname | sudo tee $RPI_ROOT/etc/hostname >/dev/null
    else
        echo $hostname"1" | sudo tee $RPI_ROOT/etc/hostname >/dev/null
    fi
fi

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

for i in {2..$hostcount}; do
    # copy image file to the new file name
    # mount the image
    # change the host name
    # unmount the image
done

# tell the file system to catch up before exiting
sync
