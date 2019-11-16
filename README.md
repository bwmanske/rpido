# rpido

Shell script for config of Raspbian for Raspberry Pi inspired by a script of the same name written by Peter Lorenzen.

If you set up a number of Raspberry Pi configurations, need to configure a computer cluster or want to setup online access without a monitor and keyboard then you should find this script useful.

## Nov 13 2019

I'm adding a page to this wiki for some explanation on directories for the project.

I have removed the -t template option.  If the template directory exists then it will be used.  For more information see the Project Directories wiki page.

I have removed some repetitive code sections thinking I was simplifying it.  Although now shorter, it is probably harder to understand.  Should scripts be written to simplify understanding of the function over any kind of optimization?  Anyone want to tell me their best practices for writing scripts?

VNC is still not working. I'm thinking I may need to make my own startup service to make some changes.

Last thought, this version hasn't had much testing.

## Oct 29 2019

A lot of effort has gone into updating the wiki for this project.  I will continue to work on it. Please check it out.

## Oct 27 2019

Added the ability to add users.  Users can be created with passwords and sudo privileges. Look in the example config for more.

I also added code to create a wifi config file, set the country code, keyboard. The code for this is very simple now but I don't really know what is required for other locals. I welcome any and all suggestions.

The VNC server RealVNC isn't working yet. I set up the files but they were reinitialized on the first run. I have confirmed that it will work. I'm looking into other ways of making it work.

## The Future

- Replace the rsync command with code to look at where the file is being copied to and set the ownership and permissions without the need for getting all of the files set up in the right condition

- Add the ability enable and disable the various hardware devices

- Add the ability to configure VNC after enabling it.

## Problems

I did a workaround for the curl command to get the latest file. It worked almost always from the command line when requesting the https URL and almost always failed when run from the shell script. Anyone have any idea what causes this?  I get a curl (35) error.

VNC is not working yet.  The initialization overwrites my settings.
