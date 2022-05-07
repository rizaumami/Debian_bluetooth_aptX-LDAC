#!/usr/bin/env bash

# Compiles the libraries and bluetooth modules to be able to use aptX and LDAC codecs via bluetooth on Debian.

####
#
# Based on the great projects of EHfive:
# https://github.com/EHfive/pulseaudio-modules-bt
# https://github.com/EHfive/ldacBT
#
####

# VARIABLES --------------------------------------------------------------------

BTAPTXLDAC="$HOME/bt-aptX-LDAC"
BAKDIR="$BTAPTXLDAC/backup/$(printf '%(%F_%T)T')"

# FUNCTIONS --------------------------------------------------------------------

# Print message in brown.
warning() {
  printf '\e[33m:: %s\n\e[m' "$@"
}

hint() {
  printf '\e[32m:: %s\n\e[m' "$@"
}

print_usage() {
  printf '%s\n' "
  ${0##*/} is a script to compiles the libraries and bluetooth
  modules to be able to use aptX and LDAC codecs via bluetooth on Debian.

  Usage: ${0##*/} OPTION

  OPTION:
    -a            Automatically compiles libraries and modules.
    -h  --help    Show this message and exit.

  Example:
    - ${0##*/} -a
    - ${0##*/} -h
"
  exit
}

# MAIN -------------------------------------------------------------------------

case "$1" in
 -a)
    mkdir -p "$BAKDIR"
    cd "$BTAPTXLDAC" || exit
    
    # Add contrib and non-free repos as they are needed for some codecs (like AAC) to install.
    sudo apt-add-repository contrib
    sudo apt-add-repository non-free
    sudo apt-get update
    # Should be installed by default - just to be safe:
    sudo apt-get install -y lsb-release
    
    # Test on the CPU architecture used whether to install the fdkaac package.
    if [[ "$(uname -m)" == 'x86_64' ]]; then
      fdkaac='fdkaac'
    else
      fdkaac=''
    fi
    
    # Ask user if the backports-repository should be activated to install this has to be done but only if the version of the system is 'buster' and not already enabled.
    if [[ "$(lsb_release -cs)" == 'buster' ]]; then
      if ! apt-cache policy | grep -q buster-backports; then
        read -r -p 'Do you want to enable the backports repository on your system in order to use debian-packages installation ? [y/N]' backports_enabled
    
        if [[ "$backports_enabled" == 'y' ]]; then
          # Add backports-repository to the source and reload apt cache to enable the necessary packages.
          sudo apt-add-repository 'deb http://deb.debian.org/debian buster-backports main'
    
          # Reload package-cache.
          sudo apt-get update
        fi
      else
        backports_enabled='y'
      fi
    elif [[ "$(lsb_release -cs)" == 'bullseye' ]]; then
      backports_enabled='y'
    elif [[ "$(lsb_release -cs)" == 'bookworm' ]]; then
      backports_enabled='y'
    elif [[ "$(lsb_release -cs)" == 'sid' ]]; then
      backports_enabled='n'
    else
      warning 'This Debian release is not suported.' 
      exit 1
    fi
    
    # Installs the packages needed.
    if [[ "$backports_enabled" == 'y' ]]; then
      sudo apt-get install git bluez-hcidump pkg-config cmake "$fdkaac" libtool libpulse-dev libdbus-1-dev libsbc-dev libbluetooth-dev libavcodec-dev libfdk-aac-dev libltdl-dev git checkinstall
    else
      sudo apt-get install git bluez-hcidump pkg-config cmake "$fdkaac" libtool libpulse-dev libdbus-1-dev libsbc-dev libavcodec-dev libbluetooth-dev libfdk-aac-dev libltdl-dev git
    fi
    
    # Backup original libraries.
    MODDIR=$(pkg-config --variable=modlibexecdir libpulse)
    hint "Backing up $MODDIR" 
    mkdir -p "$BAKDIR/$MODDIR"
    sudo find "$MODDIR" -regex ".*\(bluez5\|bluetooth\).*\.so" -exec cp {} "$BAKDIR/$MODDIR" \;
    
    # Compile libldac.
    # Check out the source from github.
    git clone --recurse-submodules https://github.com/EHfive/ldacBT.git
    # Jump into the dir.
    cd ldacBT/ || exit
    # Create a directory.
    mkdir -p build
    # Jump in.
    cd build || exit
    # Use the c-compiler with the given options.
    cmake -DCMAKE_INSTALL_PREFIX=/usr -DINSTALL_LIBDIR=/usr/lib -DLDAC_SOFT_FLOAT=OFF ../
    # Install the compiled thing.
    
    if [[ "$backports_enabled" == 'y' ]]; then
      hint 'You can just agree to all asked questions here with <enter>'
      sleep 4
      sudo checkinstall -D --install=yes --pkgname libldac
    else
      sudo make DESTDIR="$DEST_DIR" install
    fi
    
    # Compile pulseaudio-modules-bt - same as above.
    cd "$BTAPTXLDAC" || exit
    
    git clone --recurse-submodules https://github.com/EHfive/pulseaudio-modules-bt.git
    cd pulseaudio-modules-bt || exit
    git -C pa/ checkout v"$(pkg-config libpulse --modversion | sed 's/[^0-9.]*\([0-9.]*\).*/\1/')"
    mkdir -p build
    cd build || exit
    cmake ..
    make
    
    if [[ "$backports_enabled" == 'y' ]]; then
      hint 'You can just agree to all asked questions here with <enter>'
      sleep 4
      sudo checkinstall -D --install=yes --pkgname pulseaudio-module-bluetooth
    else
      sudo make install
    fi
    
    # Configure pulseaudio to use LDAC in high quality - ask user if this has to be done.
    read -r -p '
    Do you want to force using LDAC-codec in high quality? [y/N]' answer
    if [[ "$answer" == 'y' ]]; then
      # Exchange text in the pulseaudio config - in front make a copy name <filename.bak> in same folder.
      cp -v /etc/pulse/default.pa "$BAKDIR"
      sudo sed -i 's/^load-module module-bluetooth-discover$/load-module module-bluetooth-discover a2dp_config="ldac_eqmid=hq ldac_fmt=f32"/g' /etc/pulse/default.pa
    fi
    
    # Restart pulseaudio and bluetooth service.
    pulseaudio -k
    sudo systemctl restart bluetooth.service
    
    # If error: br-connection-profile-unavailable.
    pacmd load-module module-bluetooth-policy
    pacmd load-module module-bluetooth-discover
    
    # User messages and infos.
    printf '%s\n' "
  To test which codec is used for your device:
  1. disconnect your device
  2. start this command: 
     sudo hcidump | grep -A 10 -B 10 'Set config'
  3. reconnect your device.
  
  Check the line with 'Media Codec - non-A2DP (xyz)' below 'Set config'
  
  To configure the codec manually check the options for /etc/pulse/default.pa
  here: https://github.com/EHfive/pulseaudio-modules-bt#configure'
    "
  ;;
  *)
    print_usage
  ;;
esac 