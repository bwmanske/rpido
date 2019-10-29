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
    local d

    for d in /dev/sd[a-f] ;do
        if sudo gdisk -l $d 2>/dev/null| grep "^Model:.*SD/MMC">/dev/null; then
            SD=$(basename $d)
            break;
        fi
    done
}

# Associate LoopDevice with block device-associate Kernel device name to image file
loopdev_SD() {  #param #1=suffix number
    local LD_Status

    LoopDev=$(sudo losetup -f)              # set LoopDev to first available device
    if [ "$IMG_DIR" == "" ]; then
        SUDO losetup -P $LoopDev $LATEST.img    # create loop device
    else
        if [ -z $1 ]; then
            SUDO losetup -P $LoopDev $IMG_DIR/$LATEST.img    # create loop device
        else
            SUDO losetup -P $LoopDev $IMG_DIR/$LATEST$1.img    # create loop device
        fi
    fi
    LD_Status="$?"
    [ "$LD_Status" != "0" ] && echo "losetup fail-exit code $LD_Status" && exit 1
    SD=$(basename ${LoopDev}p)              # set SD var to loop device name
}

is_mounted() {
    mount | grep $(realpath $1) >/dev/null
}

# unmount the SD card or image - it may not be mounted but try anyway
unmount_SD() {
    local i

    for i in /sys/block/${SD}/${SD}?; do
        SUDO umount /dev/$(basename $i) 2>/dev/null
    done
}

# mount the SD card or image
mount_SD() {
    unmount_SD
    mkdir -p $MY_SCRIPT_DIR/$RPI_ROOT
    SUDO mount /dev/${SD}2 $MY_SCRIPT_DIR/$RPI_ROOT
    sleep 2
    SUDO mount /dev/${SD}1 $MY_SCRIPT_DIR/$RPI_ROOT/boot
    sleep 2
}

# write the image in the .zip file to the SD card 
write_SD() {
    unmount_SD
    unzip -p $zipfile $LATEST.img | sudo dd of=/dev/${SD} bs=4M
    sync
}

# 
unmount_all() {
    local p
    local d

    [ ! -z "$MY_SCRIPT_DIR/$RPI_ROOT" ] || return 1
    FULLPATH=$(realpath ${RPI_ROOT})
    LoopDev=$(mount | grep "/dev/loop[0-9]*p2.*$FULLPATH" | sed 's/p2.*$//')
    # SUDO rm -f ${RPI_ROOT}/usr/bin/qemu-arm-static 
    for p in $(mount | grep $FULLPATH | cut -f3 -d' ' | sort -Vr); do
        SUDO umount $p
    done
    for d in $LoopDev; do
        SUDO losetup -d $d
        SUDO rm -f $d/*
        SUDO rm -f $d"p*"
    done
    sync
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

# Multi-image generation with unique hostnames
image_gen () {
    local old_name

    image_gen_index=2
    while [[ $image_gen_index -le $hostcount ]]; do
        # copy image file to the new file name
        echo "----------------------------------------"
        echo " copying image file to $LATEST$image_gen_index.img"
        echo "----------------------------------------"
        cp $IMG_DIR/$LATEST$(($image_gen_index-1)).img $IMG_DIR/$LATEST$image_gen_index.img
        sync

        # mount the image
        loopdev_SD $image_gen_index
        mount_SD

        # change the host name
        old_name=$(sudo cat $RPI_ROOT/etc/hostname)
        echo $hostname$image_gen_index | sudo tee $RPI_ROOT/etc/hostname >/dev/null
        echo "----------------------------------------"
        echo " HostName  Old: $old_name New: $hostname$image_gen_index"
        echo "----------------------------------------"

        # unmount the image
        unmount_all
        sleep 5
        (( image_gen_index = image_gen_index + 1 ))
    done
}

# create a config file template
config_template() {
    cat > $MY_SCRIPT_DIR/config$config_num/rpido-config$1.sh << CONFIG_END
#!/bin/bash

# add the settings here
read_config_settings() {
    # URL for the Rasbian Image Download - uncomment one
    #CurlAddr=$CurlAddrFull         # link to Raspbian Full link (largest download)
    #CurlAddr=$CurlAddrNormal       # link to Raspbian link
    #CurlAddr=$CurlAddrLite         # Link to Raspbian Lite link (smallest download)

    # Target hardware settings - E=enable D=disable N=don't change
    Target_VNC_enable="N"
    Target_SPI_enable="N"
    Target_I2C_enable="N"
    Target_Serial_enable="N"
    Target_boot_config_enable="N"

    # VNC options when enabled
    Target_VNC_VncAuth="T"                  # T=true  F=false
    Target_VNC_password="abcd1234"

    # Country and time settings
    Target_2char_country_code="us"
    Target_timezone="America/Chicago"       # /etc/timezone
    Target_keyboard="pc105"                 # /etc/default/keyboard
    Target_kblayout="$Target_2char_country_code"

    # wpa ssid and password
    Target_wpa_ssid="ssid"                  # /etc/wpa_supplicant/wpa_supplicant.conf
    Target_wpa_password="password"

    # user to add - set password - salt - sudoers
    # Password create Ypwd=create password  Npwd=No password
    #      if created, password will be user name + salt (a string use quotes for numbers)
    #      reserved salt values
    #        - "(ns)" represents a blank value
    #        - "Ysudo" and "Nsudo" will cause the script to think salt is blank
    # sudoers - Ysudo=add to sudoers  Nsudo=don't add
    #      You must have a password to be added to list
    Target_New_Users+=(adam  Ypwd "1234" Ysudo)
    Target_New_Users+=(bill  Npwd "(ns)" Nsudo)
    Target_New_Users+=(chris Ypwd onion  Ysudo)
    Target_New_Users+=(deb   Ypwd "(ns)" Ysudo)
}

# main part of the file use for file description
echo -e "----------------------------------------"
echo -e "This config file is the template.\n"
echo -e "Additional Details:"
echo -e "You Need to:"
echo -e " - put you config description here"
echo -e " - uncomment the CurlAddr for one of the Raspbian distros."
echo -e " - set the 2 char country code"
echo -e " - uncomment a timezone"
echo -e " - set wpa ssid and password"
echo -e " - set new users to add"
echo -e "\n   ...   more to come   ..."
echo -e "----------------------------------------"
CONFIG_END
    chmod +x "$MY_SCRIPT_DIR/config$config_num/rpido-config$1.sh"
    if [ "$?" == "0" ]; then            #check the return status of chmod
        echo "Template File $MY_SCRIPT_DIR/config$config_num/rpido-config$1.sh created and made executable."
    fi
}

# Check the config file for values in all the settings force the user to keep the config up to date
verify_config_settings() {
    local user_num
    local name_idx
    local pwd_idx
    local salt_idx
    local sudo_idx

    echo "Addr=$CurlAddr"
    [ "$CurlAddr" == "" ] && return 1

    [ "$Target_VNC_enable" == "" ] && ( echo "Target_VNC_enable is missing"; return 1 )
    if [[ "$Target_VNC_enable" != "D"         && "$Target_VNC_enable" != "E"         && "$Target_VNC_enable" != "N" ]]; then
        echo -ne "Target_VNC_enable has a bad value=\"$Target_VNC_enable\""
        echo "---$?"
        return 1
    fi

    [ "$Target_SPI_enable" == "" ] && ( echo "Target_SPI_enable is missing"; return 1 )
    if [[ "$Target_SPI_enable" != "D"         && "$Target_SPI_enable" != "E"         && "$Target_SPI_enable" != "N" ]]; then
        echo -ne "Target_SPI_enable has a bad value=\"$Target_SPI_enable\""
        echo "---$?"
        return 1
    fi

    [ "$Target_I2C_enable" == "" ] && ( echo "Target_I2C_enable is missing"; return 1 )
    if [[ "$Target_I2C_enable" != "D"         && "$Target_I2C_enable" != "E"         && "$Target_I2C_enable" != "N" ]]; then
        echo -ne "Target_I2C_enable has a bad value=\"$Target_I2C_enable\""
        echo "---$?"
        return 1
    fi

    [ "$Target_Serial_enable" == "" ] && ( echo "Target_Serial_enable is missing"; return 1 )
    if [[ "$Target_Serial_enable" != "D"      && "$Target_Serial_enable" != "E"      && "$Target_Serial_enable" != "N" ]]; then
        echo -ne "Target_Serial_enable has a bad value=\"$Target_Serial_enable\""
        echo "---$?"
        return 1
    fi

    [ "$Target_boot_config_enable" == "" ] && ( echo "Target_boot_config_enable is missing"; return 1 )
    if [[ "$Target_boot_config_enable" != "D" && "$Target_boot_config_enable" != "E" && "$Target_boot_config_enable" != "N" ]]; then
        echo -ne "Target_boot_config_enable has a bad value=\"$Target_boot_config_enable\""
        echo "---$?"
        return 1
    fi

    user_num=0
    while [ ! -z ${Target_New_Users[$user_num*4]} ]; do
        name_idx=$(($user_num * 4 + 0))
        pwd_idx=$(($user_num * 4 + 1))
        salt_idx=$(($user_num * 4 + 2))
        sudo_idx=$(($user_num * 4 + 3))

        echo -n "Found user - " ${Target_New_Users[$name_idx]}

        # check for password value
        if [ ! -z ${Target_New_Users[$pwd_idx]} ]; then
            if [[ ${Target_New_Users[$pwd_idx]} != "Ypwd" && ${Target_New_Users[$pwd_idx]} != "Npwd" ]]; then
                echo "User password indicator bad value="${Target_New_Users[$pwd_idx]}
                return 1
            fi
        else
            echo "password indicator not found"
        fi
        echo -n ", "${Target_New_Users[$pwd_idx]}

        # check for salt
        if [[ ${Target_New_Users[$salt_idx]} == "Ysudo" || ${Target_New_Users[$salt_idx]} == "Nsudo" ]]; then
            echo "User ${Target_New_Users[$name_idx]} missing salt value use \"(ns)\" for no salt"
            return 1
        fi
        if [[ ${Target_New_Users[$salt_idx]} == "(ns)" ]]; then
            Target_New_Users[$salt_idx]="\"\""
        fi
        echo -n ", "${Target_New_Users[$salt_idx]}

        # check the sudoers value
        if [ ! -z ${Target_New_Users[$sudo_idx]} ]; then
            if [[ ${Target_New_Users[$sudo_idx]} != "Ysudo" && ${Target_New_Users[$sudo_idx]} != "Nsudo" ]]; then
                echo "User sudoers indicator bad value="${Target_New_Users[$sudo_idx]}
                return 1
            fi
            if [[ ${Target_New_Users[$sudo_idx]} == "Ysudo" && ${Target_New_Users[$pwd_idx]} == "Npwd" ]]; then
                echo "User ${Target_New_Users[$name_idx]} must have a password to get sudo privledges"
                return 1
            fi
        else
            echo "sudoers indicator not found"
        fi
        echo ", "${Target_New_Users[$sudo_idx]}

        ((user_num++)) # next user number
    done

    return 0    # all checks passed
}

# Display usage instructions for this script
usage() {
    unmount_all
    set +x
    [ $# == 0 ] || echo $*
    echo    "usage: rpido <options>"
    echo    " -c #     use config #=1..9  0-show descriptions from config files"
    echo    " -w       write raspian to sdcard (default)"
    echo    " -i       image file operations"
    echo    " -h name  sets /etc/hostname"
    echo    " -H #     #=2..9  number of sdcard images with hostname numbered"
    echo -e " -u ver   Rasbian version valid options \"full\", \"normal\" (default), \"lite\""
    echo -e " -s       start shell on raspian - \"exit\" to close the shell"
    echo -e " -t       copy directory \"template/\" to sdcard or image"
    echo    " -v       verbose - shell debug mode"
    echo    " -q       quiet"
    sync
    exit 1
}

#*************************************
# the script execution begins here
#*************************************
set +x   #turn on debug level info

# Initializations
MY_SCRIPT_DIR=$(dirname $(readlink -f $0))   # save the directory the script started in

VERBOSE=1                   # start with medium console out setting
RPI_ROOT=sdcard             # default to working with the SD Card
config_num=-1               # -1 if not used on the commandline
hostcount=0                 # 0 indicates no multiple images

# these are the URLs to the image filel downloads.
CurlAddrFull=://downloads.raspberrypi.org/raspbian_full_latest
CurlAddrNormal=://downloads.raspberrypi.org/raspbian_latest
CurlAddrLite=://downloads.raspberrypi.org/raspbian_lite_latest

CurlAddr=$CurlAddrNormal    # default to the middle sized image


while getopts ?c:h:H:iqstu:v opt;do
    case $opt in
    c) config_num=$OPTARG ;;
    h) hostname=$OPTARG ;;
    H) hostcount=$OPTARG ;;
    i) use_image_file=y ;;
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

if [ -z Rasbian_version ]; then
    # set the curl address based on the requested version
    case $($Rasbian_version,,) in
    full)   CurlAddr=$CurlAddrFull ;;         # select the fill image
    normal) CurlAddr=$CurlAddrNormal ;;       # select the normal image
    lite)   CurlAddr=$CurlAddrLite ;;         # select the lite image
    *) usage invalid Rasbian selection ;;     # show usage error and exit
    esac
fi

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
fi

# check for a requested config file
if [ $config_num != -1 ]; then         # no config command line parameter so skip this
    files_found=0
    if [ $config_num -eq 0 ]; then
        # test each possible file name
        for i in {1..9}; do
            # Print the number and description for each existing file
            MY_CONFIG_FILE=$MY_SCRIPT_DIR/config$i/rpido-config$i.sh
            if [ -e $MY_CONFIG_FILE ]; then
                files_found=$(($files_found+1))
                echo "Config File #$i found"
                . $MY_CONFIG_FILE     # run the script to show the description
            fi
        done
        # if no files were found create a template file if it doesn't exist already
        if [[ $files_found == 0 ]]; then
            echo "No config files found. Using -c # will create a directory and template"
        fi
        exit 1
    else
        if [[ ( $config_num -ge 1 ) && ( $config_num -le 9 ) ]]; then
            # number is valid - build the config file name
            MY_CONFIG_FILE=config$config_num/rpido-config$config_num.sh
        else
            usage illegal config number    # usage forces an exit
        fi
    fi

    #include the indicated file if it can be found
    echo "DBG---$MY_SCRIPT_DIR/$MY_CONFIG_FILE"
    if [ -e "$MY_SCRIPT_DIR/$MY_CONFIG_FILE" ]; then
        echo "Config File #$config_num found"
        chmod +x $MY_SCRIPT_DIR/$MY_CONFIG_FILE
        . $MY_SCRIPT_DIR/$MY_CONFIG_FILE
        read_config_settings
        verify_config_settings
        if [ $? -ne 0 ]; then
            echo "config file is not up to date or has an error"
            pushd config$config_num
            [ -e rpido-configX.sh ] && rm rpido-configX.sh
            config_template "X"
            popd
            exit 1
        fi
    else
        echo    "Config File #$config_num does not exist"
        echo -e "creating dir \"config$config_num/\" and template"
        rm -rf config$config_num 
        mkdir config$config_num
        [ "$?" != "0" ] && echo -e "failed create dir \"config$config_num/\"" && exit 1
        pushd config$config_num
        config_template $config_num
        mkdir template
        mkdir template/etc
        mkdir template/etc/default
        mkdir template/etc/wpa_supplicant
        mkdir template/boot
        mkdir template/home
        popd
        sync
        exit 1
    fi
fi

# the given URL is a known redirect - we need the redirect filename URL
get_first_URL
[ "$?" != "0" ] && echo "failed to get URL $URL" && exit 1

echo "Looking for redirect URL"
find_URL
[ "$?" != "0" ] && echo "failed to find URL $URL" && exit 1

# The unique filename is now in URL var
echo "Found '.zip'"
echo "URL="$URL

# Get just the file name
LATEST=$(basename $URL .zip)
zipfile=DIST/$LATEST.zip
if [[ ( $config_num -ge 1 ) && ( $config_num -le 9 ) ]]; then
    # number is valid - set the config dir location for the image
    IMG_DIR=config$config_num
else
    IMG_DIR=""
fi

# If the zip file with this name is missing then get it
[ -e $zipfile ] || curl --create-dirs -o $zipfile -L $URL # use -L to follow redirects
[ "$?" != "0" ] && echo "Curl HTTP request failed" && exit 1


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

    # For multiple images hostcount will be non-zero and hostname will be given
    if [[ ( $hostcount -ne 0 ) && ( ! -z $hostname ) ]]; then
        # extract image & for multiple image handling number the image file
        if [ ! -f $IMG_DIR/$LATEST"1.img" ]; then
            echo "----------------------------------------"
            echo " unzip image file to "$IMG_DIR/$LATEST"1.img"
            echo "----------------------------------------"
            unzip -x $zipfile -d $IMG_DIR $LATEST".img"
            if [ "$?" != "0" ]; then
                echo "unzip request failed "$IMG_DIR/$LATEST"1.img"
                exit 1
            fi
            mv $IMG_DIR/$LATEST".img" $IMG_DIR/$LATEST"1.img"
        fi

        # find loop device to use as mount point for image file
        loopdev_SD "1"
    else
        if [ "$config_num" -eq "-1" ]; then
            # extract the image file - No Config File 
            if [ ! -f "$LATEST.img" ]; then
                echo "----------------------------------------"
                echo " unzip image file to "$LATEST".img"
                echo "----------------------------------------"
                unzip -x $zipfile $LATEST.img
                if [ "$?" != "0" ]; then
                    echo "unzip request failed $LATEST.img"
                    exit 1
                fi
            fi
        else
            # extract the image file into the Config File dir
            if [ ! -f "$IMG_DIR/$LATEST.img" ]; then
                echo "----------------------------------------"
                echo " unzip image file to "$IMG_DIR/$LATEST".img"
                echo "----------------------------------------"
                unzip -x $zipfile -d $IMG_DIR $LATEST".img"
                if [ "$?" != "0" ]; then
                    echo "unzip request failed $IMG_DIR/$LATEST.img"
                    exit 1
                fi
            fi
        fi

        # find loop device to use as mount point for image file
        loopdev_SD
    fi
fi

# mount the image or SD card
mount_SD
sync
if [ -z "${RPI_ROOT}" -o ! -f "$RPI_ROOT/etc/rpi-issue" -o ! -f "$RPI_ROOT/boot/issue.txt" ]; then
    usage raspbian root not as expected
fi

# Sync the template folder to the mounted filesystem
if [ "$use_template" = y ]; then
    SUDO rsync -a template/. $RPI_ROOT
fi

# create a new hostname file 
if [ ! -z "$hostname" ]; then
    if [ $hostcount -eq "0" ]; then
        echo "----------------------------------------"
        echo " Setting HostName  $hostname"
        echo "----------------------------------------"
        echo $hostname | sudo tee $RPI_ROOT/etc/hostname >/dev/null
    else
        echo "----------------------------------------"
        echo " Setting HostName  "$hostname"1"
        echo "----------------------------------------"
        echo $hostname"1" | sudo tee $RPI_ROOT/etc/hostname >/dev/null
    fi
fi

# if a user entered a command from the command line execute it on the mounted file system
if [[ $config_num -gt 0 || $rpi_shell == "y" ]]; then
    SUDO rsync /usr/bin/qemu-arm-static ${RPI_ROOT}/usr/bin/
    for f in proc dev sys;do
        is_mounted $RPI_ROOT/$f || SUDO mount --bind /$f $RPI_ROOT/$f
    done
    # ld.so.preload fix
    SUDO sed -i 's/^/#CHROOT#/g' $RPI_ROOT/etc/ld.so.preload

    if [ $config_num -gt 0 ]; then
        # copy the target script file and make it executable
        cp rpido-target.sh $RPI_ROOT/home/pi/rpido-target.sh
        chmod +x $RPI_ROOT/home/pi/rpido-target.sh

        # copy the target script file and make it executable
        cp $MY_SCRIPT_DIR/$MY_CONFIG_FILE $RPI_ROOT/home/pi/rpido-config.sh
        chmod +x $RPI_ROOT/home/pi/rpido-config.sh

        # execute the target configuration on the image / SD card
        SUDO chroot ${RPI_ROOT} /home/pi/rpido-target.sh
    fi

    if [[ $rpi_shell == "y" ]]; then
        SUDO chroot ${RPI_ROOT} /bin/bash -i
    fi

    # remove the script and config file
    [ -e $RPI_ROOT/home/pi/rpido-target.sh ] && rm $RPI_ROOT/home/pi/rpido-target.sh
    [ -e $RPI_ROOT/home/pi/rpido-config.sh ] && rm $RPI_ROOT/home/pi/rpido-config.sh

    # revert ld.so.preload fix
    SUDO sed -i 's/^#CHROOT#//g' $RPI_ROOT/etc/ld.so.preload
fi

# unmount all - unless the user has specified -k option
unmount_all

# if multiple copies for multiple host names copy mount set the host name and unmount
if [ $hostcount -ge "2" ]; then
    image_gen
fi

# tell the file system to catch up before exiting
sync
