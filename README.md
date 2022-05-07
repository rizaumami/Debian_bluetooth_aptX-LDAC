# Debian_bluetooth_aptX-LDAC
Script to install aptX and LDAC codecs for Debian system.

Choose backports turned on to install as deb-packages.

What does it do?
- Install the required sofware packages
- Backup the original libraries to `$HOME`.
- Clone the required sources from the EHfive project site and their submodules from pulseaudio and google-android repos
- Compile them 
- Install them
  - with backports turned on: as deb-packages named `libldac` and `pulseaudio-module-bluetooth` (uninstall possible)
  - w/o backports: normal `make install`
  - for Debian releases 'bullseye', 'bookworm' or 'sid' the dpkg-package method is used, as packages needed are available in th repos by default.
  
For more details see the comments in the script.
