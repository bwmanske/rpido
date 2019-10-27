#!/bin/bash
# 

# Get the status of the vnc server
get_vnc() {
    # Infer status from the symlink
    #
    # Enabling VNC...Created symlink
    #     /etc/systemd/system/multi-user.target.wants/vncserver-x11-serviced.service → 
    #     /usr/lib/systemd/system/vncserver-x11-serviced.service.
    # Disabling VNC...Removed
    #     /etc/systemd/system/multi-user.target.wants/vncserver-x11-serviced.service.
    if [ -h /etc/systemd/system/multi-user.target.wants/vncserver-x11-serviced.service ]; then
        echo 1
    else
        echo 0
    fi
}

# VNC server Enable / Disable - $1 - 0=enable 1=disable 
do_vnc() {
    local status

    if [ $1 -eq 0 ]; then
        if [ ! -d /usr/share/doc/realvnc-vnc-server ] ; then
            apt-get install realvnc-vnc-server
        fi
        systemctl enable vncserver-x11-serviced.service &&
        status=enabled
    else
        systemctl disable vncserver-x11-serviced.service &&
        status=disabled
    fi
    echo "The VNC Server is $status"
}

# Get the status of the SPI hardware driver - enabled or disabled
get_spi() {
    if grep -q -E "^(device_tree_param|dtparam)=([^,]*,)*spi(=(on|true|yes|1))?(,.*)?$" $CONFIG; then
        echo 0
    else
        echo 1
    fi
}

# SPI Hardware driver Enable / Disable - $1 - 0=enable 1=disable 
do_spi() {
    DEFAULT=--defaultno
    if [ $(get_spi) -eq 0 ]; then
        DEFAULT=
    fi
    if [ "$INTERACTIVE" = True ]; then
        whiptail --yesno "Would you like the SPI interface to be enabled?" $DEFAULT 20 60 2
        RET=$?
    else
        RET=$1
    fi
    if [ $RET -eq 0 ]; then
        SETTING=on
        STATUS=enabled
    elif [ $RET -eq 1 ]; then
        SETTING=off
        STATUS=disabled
    else
        return $RET
    fi

    set_config_var dtparam=spi $SETTING $CONFIG &&
    if ! [ -e $BLACKLIST ]; then
        touch $BLACKLIST
    fi
    sed $BLACKLIST -i -e "s/^\(blacklist[[:space:]]*spi[-_]bcm2708\)/#\1/"
    dtparam spi=$SETTING

    if [ "$INTERACTIVE" = True ]; then
        whiptail --msgbox "The SPI interface is $STATUS" 20 60 1
    fi
}

get_i2c() {
    if grep -q -E "^(device_tree_param|dtparam)=([^,]*,)*i2c(_arm)?(=(on|true|yes|1))?(,.*)?$" $CONFIG; then
        echo 0
    else
        echo 1
    fi
}

do_i2c() {
    DEFAULT=--defaultno
    if [ $(get_i2c) -eq 0 ]; then
        DEFAULT=
    fi
    if [ "$INTERACTIVE" = True ]; then
        whiptail --yesno "Would you like the ARM I2C interface to be enabled?" $DEFAULT 20 60 2
        RET=$?
    else
        RET=$1
    fi
    if [ $RET -eq 0 ]; then
        SETTING=on
        STATUS=enabled
    elif [ $RET -eq 1 ]; then
        SETTING=off
        STATUS=disabled
    else
        return $RET
    fi
  
    set_config_var dtparam=i2c_arm $SETTING $CONFIG &&
    if ! [ -e $BLACKLIST ]; then
        touch $BLACKLIST
    fi
    sed $BLACKLIST -i -e "s/^\(blacklist[[:space:]]*i2c[-_]bcm2708\)/#\1/"
    sed /etc/modules -i -e "s/^#[[:space:]]*\(i2c[-_]dev\)/\1/"
    if ! grep -q "^i2c[-_]dev" /etc/modules; then
        printf "i2c-dev\n" >> /etc/modules
    fi
    dtparam i2c_arm=$SETTING
    modprobe i2c-dev
  
    if [ "$INTERACTIVE" = True ]; then
        whiptail --msgbox "The ARM I2C interface is $STATUS" 20 60 1
    fi
}

get_serial() {
    if grep -q -E "console=(serial0|ttyAMA0|ttyS0)" $CMDLINE ; then
        echo 0
    else
        echo 1
    fi
}

get_serial_hw() {
    if grep -q -E "^enable_uart=1" $CONFIG ; then
        echo 0
    elif grep -q -E "^enable_uart=0" $CONFIG ; then
        echo 1
    elif [ -e /dev/serial0 ] ; then
        echo 0
    else
        echo 1
    fi
}

do_serial() {
    DEFAULTS=--defaultno
    DEFAULTH=--defaultno
    CURRENTS=0
    CURRENTH=0
    if [ $(get_serial) -eq 0 ]; then
        DEFAULTS=
        CURRENTS=1
    fi
    if [ $(get_serial_hw) -eq 0 ]; then
        DEFAULTH=
        CURRENTH=1
    fi
    if [ "$INTERACTIVE" = True ]; then
        whiptail --yesno "Would you like a login shell to be accessible over serial?" $DEFAULTS 20 60 2
        RET=$?
    else
        RET=$1
    fi
    if [ $RET -eq $CURRENTS ]; then
        ASK_TO_REBOOT=1
    fi
    if [ $RET -eq 0 ]; then
        if grep -q "console=ttyAMA0" $CMDLINE ; then
            if [ -e /proc/device-tree/aliases/serial0 ]; then
                sed -i $CMDLINE -e "s/console=ttyAMA0/console=serial0/"
            fi
        elif ! grep -q "console=ttyAMA0" $CMDLINE && ! grep -q "console=serial0" $CMDLINE ; then
            if [ -e /proc/device-tree/aliases/serial0 ]; then
                sed -i $CMDLINE -e "s/root=/console=serial0,115200 root=/"
            else
                sed -i $CMDLINE -e "s/root=/console=ttyAMA0,115200 root=/"
            fi
        fi
        set_config_var enable_uart 1 $CONFIG
        SSTATUS=enabled
        HSTATUS=enabled
    elif [ $RET -eq 1 ] || [ $RET -eq 2 ]; then
        sed -i $CMDLINE -e "s/console=ttyAMA0,[0-9]\+ //"
        sed -i $CMDLINE -e "s/console=serial0,[0-9]\+ //"
        SSTATUS=disabled
        if [ "$INTERACTIVE" = True ]; then
            whiptail --yesno "Would you like the serial port hardware to be enabled?" $DEFAULTH 20 60 2
            RET=$?
        else
            RET=$((2-$RET))
        fi
        if [ $RET -eq $CURRENTH ]; then
            ASK_TO_REBOOT=1
        fi
        if [ $RET -eq 0 ]; then
            set_config_var enable_uart 1 $CONFIG
            HSTATUS=enabled
        elif [ $RET -eq 1 ]; then
            set_config_var enable_uart 0 $CONFIG
            HSTATUS=disabled
        else
            return $RET
        fi
    else
        return $RET
    fi
    if [ "$INTERACTIVE" = True ]; then
        whiptail --msgbox "The serial login shell is $SSTATUS\nThe serial interface is $HSTATUS" 20 60 1
    fi
}

disable_raspi_config_at_boot() {
    if [ -e /etc/profile.d/raspi-config.sh ]; then
        rm -f /etc/profile.d/raspi-config.sh
        if [ -e /etc/systemd/system/getty@tty1.service.d/raspi-config-override.conf ]; then
            rm /etc/systemd/system/getty@tty1.service.d/raspi-config-override.conf
        fi
        telinit q
    fi
}

# process Target_VNC_enable in the included config file
Set_Target_VNC_enable () {
    local vnc_status
    local vnc_pdw

    vnc_status=$(get_vnc)
    echo -n "VNC=$Target_VNC_enable $vnc_status "
    case $Target_VNC_enable in
        D)  if [[ $vnc_status == 1 ]]; then
                echo -n "Disabling VNC..."
                do_vnc 1; 
                echo "VNC Disabled"
            else
                echo "VNC is presently disabled - nothing to do"
            fi
            ;;
        E)  if [[ $vnc_status == 0 ]]; then
                echo -n "Enabling VNC..."
                do_vnc 0; 

                # options
                if [[ $Target_VNC_VncAuth == "T" ]]; then
                    sed -i 's/Authentication=SystemAuth/Authentication=VncAuth/g' /root/.vnc/config.d/vncserver-x11
                else
                    sed -i 's/Authentication=VncAuth/Authentication=SystemAuth/g' /root/.vnc/config.d/vncserver-x11
                fi

                # vnc password
                echo $Target_vncpassword  >vncpasswd_input
                echo $Target_vncpassword >>vncpasswd_input
                cat vncpasswd_input
                vnc_pwd=$(vncpasswd -printf <vncpasswd_input)
                echo "Password=$vnc_pwd" >/etc/vnc/config.d/custom.custom
                rm vncpasswd_input

                echo "VNC Enabled"
            else
                echo "VNC is presently enabled - nothing to do"
            fi
            ;;
        N) echo "No VNC change" ;;
        *) echo "bad option $Target_VNC_enable" ;;
    esac
}

# process Target_SPI_enable in the included config file
Set_Target_SPI_enable () {
    local spi_status

    spi_status=$(get_spi)
    echo -n "SPI=$Target_SPI_enable $? "
    case $Target_SPI_enable in
        D) echo "Disable" ;;
        E) echo "Enable" ;;
        N) echo "Nothing" ;;
        *) echo "bad option $Target_SPI_enable" ;;
    esac
}

Set_Target_I2C_enable () {
#    get_i2c
    echo -n "I2C=$Target_I2C_enable $? "
    case $Target_I2C_enable in
        D) echo "Disable" ;;
        E) echo "Enable" ;;
        N) echo "Nothing" ;;
        *) echo "bad option $Target_I2C_enable" ;;
    esac
}

Set_Target_Serial_enable () {
#    get_serial
    echo -n "Serial=$Target_Serial_enable $? "
    case $Target_Serial_enable in
        D) echo "Disable" ;;
        E) echo "Enable" ;;
        N) echo "Nothing" ;;
        *) echo "bad option $Target_Serial_enable" ;;
    esac
}

Set_Target_boot_config_enable () {
    echo -n "boot cfg=$Target_boot_config_enable "
    case $Target_boot_config_enable in
        D) echo "Disable" ;;
        E) echo "Enable" ;;
        N) echo "Nothing" ;;
        *) echo "bad option $Target_boot_config_enable" ;;
    esac
}

Add_User_Accounts() {
    local user_num
    local user_pwd
    local user_group
    local name_idx
    local pwd_idx
    local salt_idx
    local sudo_idx

    user_num=0
    while [ ! -z ${Target_New_Users[$user_num*4]} ]; do
        name_idx=$(($user_num * 4 + 0))
        pwd_idx=$(($user_num * 4 + 1))
        salt_idx=$(($user_num * 4 + 2))
        sudo_idx=$(($user_num * 4 + 3))

        if [[ $user_num == 0 ]]; then
            echo "Adding user accounts"
        fi
        echo -n " ${Target_New_Users[$name_idx]} "

        # add the user
        if [[ ${Target_New_Users[$pwd_idx]} != "Ypwd" ]]; then
            # add to sudoers group
            if [[ ${Target_New_Users[$sudo_idx]} != "Ysudo" ]]; then
                user_group="-g sudo"
            fi

            if [[ ${Target_New_Users[$salt_idx]} == "(ns)" ]]; then
                Target_New_Users[$salt_idx]=""
            fi
            
            # add a password - password will be username+salt
            user_pwd=$(openssl passwd -1 ${Target_New_Users[$name_idx]}${Target_New_Users[$salt_idx]})
            useradd -m -s /bin/bash $user_group -p $user_pwd ${Target_New_Users[$name_idx]}
        else
            # if there is no password - there is no way to be added to sudoers
            useradd -m -s /bin/bash ${Target_New_Users[$name_idx]}
        fi

        ((user_num++))
    done
    if [[ $user_num > 0 ]]; then
        echo
    fi
}

country_time_settings() {
    # make the timezone file
    echo $Target_timezone  >/etc/timezone

    # make a keyboard file
    echo "XKBMODEL=$Target_keyboard"    >/etc/default/keyboard
    echo "XKBLAYOUT=$Target_kblayout"  >>/etc/default/keyboard
    echo "XKBVARIANT="                 >>/etc/default/keyboard
    echo "XKBOPTIONS="                 >>/etc/default/keyboard
    echo "BACKSPACE=guess"             >>/etc/default/keyboard

    # make a wpa_supplicant.conf
    echo "ctrl_interface=DIR=/var/run/wpa_supplicant GROUP=netdev"  >/etc/wpa_supplicant/wpa_supplicant.conf
    echo "update_config=1"                                         >>/etc/wpa_supplicant/wpa_supplicant.conf
    echo "country=$Target_2char_country_code"                      >>/etc/wpa_supplicant/wpa_supplicant.conf
    echo                                                           >>/etc/wpa_supplicant/wpa_supplicant.conf
    echo "network={"                                               >>/etc/wpa_supplicant/wpa_supplicant.conf
    echo -e "	ssid=\"$Target_wpa_ssid\""                         >>/etc/wpa_supplicant/wpa_supplicant.conf
    echo -e "	psk=\"$Target_wpa_password\""                      >>/etc/wpa_supplicant/wpa_supplicant.conf
    echo    "	key_mgmt=WPA-PSK"                                  >>/etc/wpa_supplicant/wpa_supplicant.conf
    echo "}"                                                       >>/etc/wpa_supplicant/wpa_supplicant.conf
}

#*************************************
# the script execution begins here
#*************************************
set +x   #turn on debug level info

# Initializations
MY_TARGET_SCRIPT_DIR=$(dirname $(readlink -f $0))   # save the directory the script started in
CONFIG=/boot/config.txt

# make the script dir the working dir
cd $MY_TARGET_SCRIPT_DIR

# load the settings from the config file
. rpido-config.sh
read_config_settings

country_time_settings

Add_User_Accounts

# hardware settings
Set_Target_VNC_enable
Set_Target_SPI_enable
Set_Target_I2C_enable
Set_Target_Serial_enable
Set_Target_boot_config_enable
