#!/bin/bash
# @author       Chris Iverach-Brereton <civerachb@clearpathrobotics.com>
# @author       David Niewinski <dniewinski@clearpathrobotics.com>
# @description  Restores a backup of a single robot's and upgrades it from ROS Kinetic to Melodic

############################## FUNCTION DEFINITIONS ############################

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

function changeRosDistroPackage {
  # change all occurences of the ROS distro codename in an arbitrary string to the new codename
  # usage: changeRosDistroPackage $from $to $package
  FROM="ros-$1"
  TO="ros-$2"
  PKG=$3
  echo "${PKG//$FROM/$TO}"
}

function changeRosDistroFile {
  # change all occurences of the ROS distro codename in a file to the new codename
  # this creates a backup of the original file too
  # usage: changeRosDistroPackage $from $to $file
  FROM="$1"
  TO="$2"
  FILE=$3

  echo "Attempting to migrate ROS distro in file $FILE from $FROM to $TO"
  if [ -f $FILE ];
  then
    cp $FILE $FILE.bak.$(date +"%Y%m%d%H%M%S")
    REGEX="s/$FROM/$TO/"
    CMD="sed -i '$REGEX' $FILE"
    bash -c "$CMD"
  else
    echo "WARNING: $FILE does not exist. Skipping migration"
  fi
}

function tryInstallApt {
  # usage: tryInstallApt $package
  PACKAGE=$1

  sudo apt-get install --reinstall --yes $PACKAGE
  RESULT=$?
  if [ $RESULT -ne 0 ];
  then
    echo -e "[WARN] ${RED}Failed to install $PACKAGE ${NC}"

    if [ ! -f $HOME/could_not_install_apt.sh ];
    then
      echo "#!/bin/bash" > $HOME/could_not_install_apt.sh
      echo "# The following packages could not be reinstalled" >> $HOME/could_not_install_apt.sh
      echo "sudo apt-get install --reinstall --yes \\" >> $HOME/could_not_install_apt.sh
    fi

    echo "    $PACKAGE \\" >> $HOME/could_not_install_apt.sh
  fi
}

function tryInstallPip {
  # usage: tryInstallPip $package $version

  PKG=$1
  VERSION=$2

  pip install -Iv $PKG==$VERSION
  RESULT=$?
  if [ $RESULT -ne 0 ];
  then
    echo -e "[WARN] ${RED}Failed to install $PACKAGE v$VERSION ${NC}"

    if [ ! -f $HOME/could_not_install_pip.sh ];
    then
      echo "#!/bin/bash" > $HOME/could_not_install_pip.sh
      echo "# The following packages could not be reinstalled" >> $HOME/could_not_install_pip.sh
    fi

    echo "pip install $PKG==$VERSION" >> $HOME/could_not_install_pip.sh
  fi

}

############################## ARGUMENT PARSING ############################

# the username used during the original backup
# by default on robots we ship this should always be "administrator"
USERNAME=administrator

# the version of _this_ script
VERSION=2.0.1

RED='\e[31m'
GREEN='\e[32m'
NC='\e[39m' # No Color

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

  echo "Checking ROS distro"
  if [ ! -f "ROS_DISTRO" ];
  then
    echo "ERROR: no ROS distro specified in backup. Aborting."
    cd ..
    cleanup "$1"
    exit 1
  fi
  ROSDISTRO=$(cat ROS_DISTRO)
  echo "ROS distro in backup is $ROSDISTRO"

  # check that the ROS distribution in the backup is kinetic
  if [ "$ROSDISTRO" != "kinetic" ];
  then
    echo "ERROR: this backup is using ROS $ROSDISTRO; only upgrading from kinetic is currently supported. Aborting."
    cleanup "$1"
    exit 1
  else
    OLD_ROSDISTRO="$ROSDISTRO"
    ROSDISTRO="melodic"
    echo "+++++ Upgrading from ROS $OLD_ROSDISTRO to $ROSDISTRO +++++"
  fi

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

    sudo bash -c "$(declare -f changeRosDistroFile); changeRosDistroFile $OLD_ROSDISTRO $ROSDISTRO /etc/ros/setup.bash"
  else
    echo "Skipping setup.bash; no backup"
  fi

  if [ -d ros.d ];
  then
    echo "Restoring Bringup"
    sudo mkdir -p /etc/ros/$ROSDISTRO/ros.d
    sudo cp -r ros.d/. /etc/ros/$ROSDISTRO/ros.d
  else
    echo "Skipping bringup; no backup"
  fi

  if [ -d usr/sbin ];
  then
    echo "Restoring sbin"
    if [ -f usr/sbin/ros-start ];
    then
        changeRosDistroFile $OLD_ROSDISTRO $ROSDISTRO usr/sbin/ros-start
    fi
    sudo cp -r usr/sbin/. /usr/sbin
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
  changeRosDistroFile $OLD_ROSDISTRO $ROSDISTRO ~/.bashrc

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
  if [ -f iptables ];
  then
    echo "Restoring iptables"
    sudo cp iptables /etc/iptables
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
    # only reinstall ROS packages; there are too many other packages whose versions/names/etc... may have changed
    # to be able to reliably reinstall them all
    if [[ $PKG = ros-$OLD_ROSDISTRO-* ]];
    then
      # packages that are of the form ros-kinetic-* need to be upgraded to ros-melodic-*
      NEW_PKG=$(changeRosDistroPackage "$OLD_ROSDISTRO" "$ROSDISTRO" $PKG)

      if [ $INSTALL_APT == 1 ];
      then
        tryInstallApt $NEW_PKG
      else
        echo "    $NEW_PKG \\" >> $HOME/restore-apt.sh
      fi
    else
      # other packages we'll try to install, but they may not be available
      if [ $INSTALL_APT == 1 ];
      then
        tryInstallApt $PKG
      else
        echo "    $PKG \\" >> $HOME/restore-apt.sh
      fi
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
  # the default format of pip list is changing, so to keep this script working explicitly use the legacy format if it's not already
  echo "Setting PIP to use legacy list format"
  echo "To revert this change, edit $HOME/.config/pip/pip.conf"
  if [ ! -f $HOME/.config/pip/pip.conf ];
  then
    mkdir -p $HOME/.config/pip/
    touch $HOME/.config/pip/pip.conf
  fi
  echo "[list]" >> $HOME/.config/pip/pip.conf
  echo "format=legacy" >> $HOME/.config/pip/pip.conf
  while read line; do
    TOKENS=($line)
    PKG=${TOKENS[0]}
    VERSION=$(echo ${TOKENS[1]} | sed 's/[)(]//g')

    PIP_OUT=$(pip list|grep "^$PKG\s")
    TOKENS=($PIP_OUT)
    INSTALLED_PKG=${TOKENS[0]}
    INSTALLED_VERSION=$(echo ${TOKENS[1]} | sed 's/[)(]//g')

    if [ $INSTALL_PIP == 1 ];
    then
      # check if the package is installed, if it's not then install it
      if [[ "$INSTALLED_PKG" == "$PKG" && ("$INSTALLED_VERSION" == "$VERSION" || "$INSTALLED_VERSION" > "$VERSION") ]];
      then
        echo "pip package $PKG $VERSION (or newer) is already installed"
      else
        echo "Installing pip package $PKG"
        tryInstallPip $PKG $VERSION
      fi
    else
      # add this package to the install script
      if [[ "$INSTALLED_PKG" == "$PKG" && ("$INSTALLED_VERSION" == "$VERSION" || "$INSTALLED_VERSION" > "$VERSION") ]];
      then
        echo "pip package $PKG $VERSION (or newer) is already installed"
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
    echo -e "Run ${GREEN}$HOME/restore-apt.sh${NC} to resintall APT packages"
  else
    if [ -f $HOME/could_not_install_apt.sh ];
    then
      echo -e "[WARN] ${RED}Some APT packages could not be installed.  See ${GREEN}$HOME/could_not_install_apt.sh${RED} for more details.${NC}"
    fi
  fi
  if [ $INSTALL_PIP == 0 ];
  then
    echo -e "Run ${GREEN}$HOME/restore-pip.sh${NC} to resintall PIP packages"
  else
    if [ -f $HOME/could_not_install_pip.sh ];
    then
      echo -e "[WARN] ${RED}Some PIP packages could not be installed.  See ${GREEN}$HOME/could_not_install_pip.sh${RED} for more details.${NC}"
    fi
  fi
else
  echo "USAGE: bash restore.sh customer_name [username]"
fi
