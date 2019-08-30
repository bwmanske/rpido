# rpido

Shell script for config of Raspbian for Raspberry Pi

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
