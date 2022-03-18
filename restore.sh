#!/bin/bash
# @author       Chris Iverach-Brereton <civerachb@clearpathrobotics.com>
# @author       David Niewinski <dniewinski@clearpathrobotics.com>
# @description  Restores a backup of a single robot's integration setup.
#               This script should be run locally on the robot

# the username used during the original backup
# by default on robots we ship this should always be "administrator"
USERNAME=administrator

# the version of _this_ script
VERSION=2.0.2

RED='\033[0;31m'
NC='\033[0m' # No Color

function cleanup {
  echo "Cleaning Up $(pwd)/$1"
  rm -rf $1
  echo "Done Cleaning"
}

function promptDefaultNo {
  # $1: the prompt
  # return: 0 for no, 1 for yes
  read -r -p "$1 [y/N] " response
  if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]];
  then
    echo 1
  else
    echo 0
  fi
}

function promptDefaultYes {
  # $1: the prompt
  # return: 0 for no, 1 for yes
  read -r -p "$1 [Y/n] " response
  if [[ "$response" =~ ^([nN][oO]|[nN])$ ]];
  then
    echo 0
  else
    echo 1
  fi
}

if [ $# -ge 1 ]
then
  if [ $# == 2 ];
  then
    echo "Overriding default username"
    USERNAME=$2
    echo "Username: $USERNAME"
  fi

  CUSTOMER=$1

  ######################## UNPACK ARCHIVE ##########################
  echo "Unpacking backup"
  tar -xf $CUSTOMER.tar.gz $CUSTOMER
  cd $CUSTOMER

  ############################ METADATA CHECK ###############################

  echo "Checking backup version"
  if [ ! -f "BKUP_VERSION" ];
  then
    echo "ERROR: no backup script version specified; cannot restore this backup!"
    exit 1
  else
    BKUP_VERSION=$(cat BKUP_VERSION)
    if [ "$VERSION" != "$BKUP_VERSION"  ];
    then
      cd ..
      cleanup "$1"
      echo "ERROR: backup was made with a different version; please download v$BKUP_VERSION of this script"
      exit 1
    else
      echo "Backup can be restored with this script"
    fi
  fi

  echo "Checking backup ROS distro"
  if [ ! -f "ROS_DISTRO" ];
  then
    echo "ERROR: no ROS distro specified in backup. Aborting."
    cd ..
    cleanup "$1"
    exit 1
  fi
  ROSDISTRO=$(cat ROS_DISTRO)
  echo "ROS distro in backup is $ROSDISTRO"

  if [ "$USERNAME" != "$(whoami)" ];
  then
    echo "WARNING: current user ($(whoami)) does not match expected account ($USERNAME)"
    CONTINUE=$(promptDefaultNo "Continue?")
    if [ $CONTINUE == 1 ]
    then
        echo "Ignoring username mismatch"
    else
        cd ..
        cleanup "$1"
        echo "User aborted"
        exit 0
    fi
  fi

  ############################ ROS & BRINGUP #############################
  if [ -f setup.bash ];
  then
    echo "Restoring etc/ros/setup.bash"
    sudo cp setup.bash /etc/ros/setup.bash
  else
    echo "Skipping setup.bash; no backup"
  fi

  if [ -d ros.d ];
  then
    echo "Restoring Bringup"
    sudo cp -r ros.d/. /etc/ros/$ROSDISTRO/ros.d
  else
    echo "Skipping bringup; no backup"
  fi

  if [ -d sbin ];
  then
    echo "Restoring sbin"
    sudo cp -r sbin/. /usr/sbin
  else
    echo "Skipping sbin; no backup"
  fi

  if [ -d rosdep ];
  then
    echo "Restoring RosDep sources"
    sudo cp -r rosdep/. /etc/ros/rosdep/
  else
    echo "Skipping rosdep sources; no backup"
  fi

  if [ -d system ];
  then
    echo "Restoring Systemd"
    sudo cp -r system/. /etc/systemd/system
  else
    echo "Skipping systemd; no backup"
  fi

  ############################ HOME FOLDER #############################
  echo "Restoring Home Folder"
  cp -r $USERNAME/. ~

  ############################ UDEV #############################
  if [ -d rules.d ];
  then
    echo "Restoring udev rules"
    sudo cp -r rules.d/. /etc/udev/rules.d
  else
    echo "Skipping udev rules; no backup"
  fi

  ############################ NETWORK #############################
  echo "Restoring Network Setup"
  if [ -f interfaces ];
  then
    echo "Restoring interfaces"
    sudo cp interfaces /etc/network/interfaces
  else
    echo "Skipping /etc/network/interfaces; no backup"
  fi
  if [ -d netplan ];
  then
    echo "Restoring netplan files"
    sudo cp -r netplan/. /etc/netplan
  else
    echo "Skipping netplan; no backup"
  fi
  if [ -f hostname ];
  then
    echo "Restoring hostname"
    sudo cp hostname /etc/hostname
  else
    echo "Skipping /etc/hostname; no backup"
  fi
  if [ -f hosts ];
  then
    echo "Restoring hosts"
    sudo cp hosts /etc/hosts
  else
    echo "Skipping /etc/hosts; no backup"
  fi
  if [ -d iptables ];
  then
    echo "Restoring iptables"
    sudo cp -r iptables/. /etc/iptables
  else
    echo "Skipping /etc/iptables; no backup"
  fi

  ############################ RC.LOCAL #############################
  if [ -f rc.local ];
  then
    echo "Restoring rclocal"
    sudo cp rc.local /etc/rc.local
  else
    echo "Skipping rc.local; no backup"
  fi

  ############################ USER GROUPS #############################
  echo "Restoring user groups"
  while read LINE; do
    for GROUP in ${LINE}; do
      echo "Adding user to group $GROUP"
      echo "sudo usermod -a -G $GROUP $(whoami)"
      sudo usermod -a -G $GROUP $(whoami)
    done
  done < groups

  ############################ APT #############################
  if [ -d sources.list.d ];
  then
    echo "Restoring APT sources"
    sudo cp -r sources.list.d/. /etc/apt/sources.list.d
  else
    echo "Skipping additional APT sources; no backup present"
  fi

  INSTALL_APT=$(promptDefaultYes "Reinstall APT packages?")
  if [ $INSTALL_APT == 1 ];
  then
    echo "Reinstalling APT packages"
  else
    echo "Creating a script to let you reinstall APT packages later"
    echo "#!/bin/bash" > $HOME/restore-apt.sh
    echo "# Automatically generated by $0 v$VERSION" >> $HOME/restore-apt.sh
    echo "# $(date)" >> $HOME/restore-apt.sh
    echo "sudo apt-get install --reinstall --yes \\" >> $HOME/restore-apt.sh
    chmod +x $HOME/restore-apt.sh
  fi
  while read PKG; do
    if [ $INSTALL_APT == 1 ];
    then
      sudo apt-get install --reinstall --yes $PKG
    else
      echo "    $PKG \\" >> $HOME/restore-apt.sh
    fi
  done < installed_pkgs.list

  ############################ PIP #############################
  # we have to do pip last, as some pip packages may be provided via apt
  # this should _only_ install pip packages that were manually installed
  INSTALL_PIP=$(promptDefaultYes "Restore PIP packages?")
  if [ $INSTALL_PIP == 1 ];
  then
    echo "Restoring pip packages"
    echo "If you have not already restored APT packages you may encounter errors"
  else
    echo "Creating script so you can restore PIP packages later..."
    echo "#!/bin/bash" > $HOME/restore-pip.sh
    echo "# Automatically generated by $0 v$VERSION" >> $HOME/restore-pip.sh
    echo "# $(date)" >> $HOME/restore-pip.sh
    chmod +x $HOME/restore-pip.sh
  fi
  while read line; do
    TOKENS=($line)
    PKG=${TOKENS[0]}
    VERSION=${TOKENS[1]}

    PIP_OUT=$(pip list|grep "^$PKG\s")
    TOKENS=($PIP_OUT)
    INSTALLED_PKG=${TOKENS[0]}
    INSTALLED_VERSION=${TOKENS[1]}

    if [ $INSTALL_PIP == 1 ];
    then
      # check if the package is installed, if it's not then install it
      if [[ "$INSTALLED_PKG" == "$PKG" && "$INSTALLED_VERSION" == "$VERSION" ]];
      then
        echo "pip package $PKG $VERSION is already installed"
      else
        echo "Installing pip package $PKG"
        pip install -Iv $PKG==$VERSION
      fi
    else
      # add this package to the install script
      if [[ "$INSTALLED_PKG" == "$PKG" && "$INSTALLED_VERSION" == "$VERSION" ]];
      then
        echo "pip package $PKG $VERSION is already installed"
      else
        echo "pip install -Iv $PKG==$VERSION" >> $HOME/restore-pip.sh
      fi

    fi
  done < pip.list

  ############################ CLEANUP #############################
  echo "Done Restoring Files"
  cd ..
  cleanup "$CUSTOMER"

  ############################ FINAL MESSAGES #############################

  if [ $INSTALL_APT == 0 ];
  then
    echo -e "Run ${RED}$HOME/restore-apt.sh${NC} to resintall APT packages"
  fi
  if [ $INSTALL_PIP == 0 ];
  then
    echo -e "Run ${RED}$HOME/restore-pip.sh${NC} to resintall PIP packages"
  fi
else
  echo "USAGE: bash restore.sh customer_name [username]"
fi
