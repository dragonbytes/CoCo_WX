
CoCo WX 2.x
Written By Todd Wallace

-= Description =-

So I am a bit of a weather geek. I even have my own outdoor wireless sensor
that can measure wind speed, direction, rainfall, etc. Weather "apps" are
available on almost every platform capable of connecting to the internet, so
how cool would it be to do it on a CoCo too? Well I found this cool web-based
poweruser-oriented online weather service called wttr.in. It's free to use
and has a very simple implementation. I figured out how to do a simple HTTP
request over a TCP connection made with DriveWire's virtual serial port
annddd VOILA!!

New in Version 2.0

I have completely rewritten the networking parts of the code to request and
parse weather data in JSON format from wttr.in as that medium contains a much
wider range of data and units of measure. This now lets the user view their
weather data in either metric or imperial measurements regardless of the
region they are checking the conditions of.

The biggest change though is the addition of a fully graphical output format
with full color icons and a segmented-display style font for displaying the
actual temperature, etc. The graphics output is actually the DEFAULT as of
version 2.0, however you can still use the original text-only format by
adding the -t flag. You can read more about the various supported CLI flags
by running "cocowx" without any parameters which will display all the syntax
information and the like.

-= Installation =-

CoCo WX 2.x is dependent on 3 graphics-support files which I decided to put
in the /dd/sys/cocowx/ directory. I will be including a script with this
that essentially creates that directory, and then copies those 3 graphics
files to it. The executable "cocowx" is then copied to /dd/cmds. You can, of
course, do all that manually yourself, but I figured a script might make
things easier on less-experienced users.
