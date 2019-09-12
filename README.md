# rpido

Shell script for config of Raspbian for Raspberry Pi inspired by a script of the same name written by Peter Lorenzen.

If you set up a number of Raspberry Pi configurations, need to configure a computer cluster or want to setup online access without a monitor and keyboard then you should find this script useful.

## Sept 12 2019

The structure for the config files and the multi host names is in place and working. When selecting host count -H now multiple copies of the image files will be created with the requested host name and the suffix.

I am now working on the structure that it takes to copy the config and target script file to the image / SD card and run it from the chroot command.

## Sept 7 2019

I have concentrated on adding config file support -c takes a number parameter 1 to 9. The file rpido-config1.sh (for example) will have a main function that echos the description to the console and has functions containing the items to configure.  The 0 parameter will look for each of these files and execute them so that the descriptions are shown along with the config number.  If there are no files present, then a rpido-configX.sh file will be created as a template for numbering, adding a description and picking options.

I have also added a host count -H right now the allowable values are 2 thru 9.  If working with images -i and specifying a hostname -h name and not wanting to keep the file system open -k then the specified hostname will have a number as a suffix.  The image file's name will also have the same suffix number and the specified number of files will be created.  So if making a cluster you can have the same base hostname for each computer.

URL / Rasbian version selection was added as an option -u with an parameter for chosing the full, normal and lite versions of rasbian to download.  This parameter defaults to normal if not specified. The choice will be overwritten by the value in a config file if you use the -c option.

Right now, this is my plan.  Basic options can be set on the command line. If what you want is to grab the latest version and write it to a card a config file will not be needed. Using a config file will allow over riding those options. The config file will be read (if used) and the image prepared. The emulator will be copied to the image to allow running programs. A config script and the rpido-target.sh file will be copied to the image and then chroot to run the script.  This should allow configuration of hardware devices, setting up SSH, wifi, VNC, and other Raspberry Pi hardware.  A template directory and -t will allow you to copy files to the file system for things like adding SSH keys, setting bash alias, etc...

## Aug 28 2019

My work on a project requiring the use of several raspberry pis lead me to the want an easy way to set up an image before ever inserting it into the Pi.

I found the article:
[SET UP A HEADLESS RASPBERRY PI, ALL FROM ANOTHER COMPUTER’S COMMAND LINE](https://hackaday.com/2018/11/24/set-up-a-headless-raspberry-pi-all-from-another-computers-command-line/)

Peter Lorenzen deserves credit for his very efficient shell script
Trying to get to [the page](http://peter.lorenzen.us/linux/headless-raspberry-pi-configuration) it never responded. So I went to [The Way Back Machine](https://archive.org) to get the [archived page](https://web.archive.org/web/20190131013305/http://peter.lorenzen.us/linux/headless-raspberry-pi-configuration) Using the final snapshot of this page is where I started.

I don't know if I got the latest version of the code. I decided to build a VMware Debian 10 machine with the Cinnamon desktop. I don't know what he used. This script would no longer run. The Raspberry Pi website obviously changed so in this initial version I:

- fixed the redirect

- I workedaround some problems with curl

- used awk to search for the name in the redirect

- I changed some of his defaults

- added more error checking and comments

## The Future

- Replace the rsync command with code to look at where the file is being copied to and set the ownership and permissions without the need for getting all of the files set up in the right condition

- Add a ability to select a config file

- Make Country, Keyboard, Timezone selectable in the config file

- Add the ability enable and disable the various hardware devices

- Add the ability to configure VNC after enabling it.

## Problems

I did a workaround for the curl command to get the latest file. It worked almost always from the command line when requesting the https URL and almost always failed when run from the shell script. Anyone have any idea what causes this?  I get a curl (35) error.
