#!/bin/bash
# @author       Chris Iverach-Brereton <civerachb@clearpathrobotics.com>
# @author       David Niewinski <dniewinski@clearpathrobotics.com>
# @description  Creates a backup of a single robot's configuration after integration

# the username we use to SSH into the remote host
USERNAME=administrator

# the password associated with the user defined above
PASSWORD=clearpath

# the version of _this_ script
VERSION=2.0.2

if [ $# -ge 2 ]
then
  CUSTOMER=$1
  HOST=$2

  if [[ $HOST == *"@"* ]];
  then
    echo "Overriding default username"
    USERNAME=${HOST%@*}
    HOST=${HOST#*@}

    echo "Username: $USERNAME"
    echo "Host: $HOST"
  fi

  if [ $# == 3 ];
  then
    echo "Overriding default password"
    PASSWORD=$3

    echo "Password: $PASSWORD"
  fi

  echo "===== Starting Clearpath Robotics Robot Backup v$VERSION ====="
  echo "Creating backup for $USERNAME@$HOST"

  ############################ DEPENDENCY CHECK ###############################
  if ! command -v rsync &> /dev/null;
  then
    echo "rsync is not installed"
    echo "please run 'sudo apt-get install rsync'"
    exit 1
  fi
  if ! command -v sshpass &> /dev/null;
  then
    echo "sshpass is not installed"
    echo "please run 'sudo apt-get install sshpass'"
    exit 1
  fi

  ############################ CREATE WORKING DIRECTORY ###############################
  echo "Creating Directory <" $PWD"/"$CUSTOMER ">"
  mkdir "$CUSTOMER"
  cd "$CUSTOMER"

  ############################ BACKUP METADATA ###############################
  echo "Querying ROS Distro"
  # NOTE: we cannot reliably run rosversion -d, as on some systems a non-interactive ssh terminal
  # will _not_ source .bashrc, which in turn won't source /opt/ros/[distro]/setup.bash
  # therefore we check the /opt/ros folder for the appropriate distro folder and use that
  # if there's more than one folder we pick the last one
  ROSDISTRO=$(echo "ls -rt /opt/ros | tail -1" | sshpass -p "$PASSWORD" ssh -T $USERNAME@$HOST | tail -1)
  echo "ROS distro is $ROSDISTRO"
  echo "$ROSDISTRO" > ./ROS_DISTRO

  # create a command we can run _before_ any SSH commands that require ROS commands
  # this should be prepended to any commands (i.e. $SSH_SOURCE_CMD && <other stuff to run>)
  SSH_SOURCE_CMD="source /opt/ros/$ROSDISTRO/setup.bash"

  # record the version of this script so we can make sure the restore script is the same version
  echo "$VERSION" > ./BKUP_VERSION

  ############################ BACKUP #############################

  echo "Copying udev rules"
  sshpass -p "$PASSWORD" scp -r $USERNAME@$HOST:/etc/udev/rules.d .

  echo "Copying Network Setup"
  sshpass -p "$PASSWORD" scp $USERNAME@$HOST:/etc/network/interfaces .
  sshpass -p "$PASSWORD" scp -r $USERNAME@$HOST:/etc/netplan .
  sshpass -p "$PASSWORD" scp $USERNAME@$HOST:/etc/hostname .
  sshpass -p "$PASSWORD" scp $USERNAME@$HOST:/etc/hosts .

  echo "Copying IPTables"
  sshpass -p "$PASSWORD" scp -r $USERNAME@$HOST:/etc/iptables .

  echo "Copying Bringup"
  sshpass -p "$PASSWORD" scp $USERNAME@$HOST:/etc/ros/setup.bash .
  sshpass -p "$PASSWORD" scp -r $USERNAME@$HOST:/etc/ros/$ROSDISTRO/ros.d .
  mkdir -p usr/sbin
  sshpass -p "$PASSWORD" scp -r $USERNAME@$HOST:/usr/sbin/*start usr/sbin
  sshpass -p "$PASSWORD" scp -r $USERNAME@$HOST:/usr/sbin/*stop usr/sbin

  echo "Copying RosDep sources"
  sshpass -p "$PASSWORD" scp -r $USERNAME@$HOST:/etc/ros/rosdep .

  echo "Copying rclocal"
  sshpass -p "$PASSWORD" scp $USERNAME@$HOST:/etc/rc.local .

  echo "Copying pip packages"
  # strip the first 2 lines from pip list output; they're headers we don't need!
  echo "$SSH_SOURCE_CMD && pip list | tail -n +3 > /tmp/pip.list" | sshpass -p "$PASSWORD" ssh -T $USERNAME@$HOST
  sshpass -p "$PASSWORD" scp -r $USERNAME@$HOST:/tmp/pip.list .
  echo "rm /tmp/pip.list" | sshpass -p "$PASSWORD" ssh -T $USERNAME@$HOST

  echo "Copying Systemd"
  sshpass -p "$PASSWORD" scp -r $USERNAME@$HOST:/etc/systemd/system .

  echo "Copying user groups"
  echo "groups" | sshpass -p "$PASSWORD" ssh -T $USERNAME@$HOST | tail -1 > groups

  echo "Copying APT sources & packages"
  sshpass -p "$PASSWORD" scp -r $USERNAME@$HOST:/etc/apt/sources.list.d .
  echo "apt-mark showmanual > /tmp/installed_pkgs.list" | sshpass -p "$PASSWORD" ssh -T $USERNAME@$HOST
  sshpass -p "$PASSWORD" scp -r $USERNAME@$HOST:/tmp/installed_pkgs.list .
  echo "rm /tmp/installed_pkgs.list" | sshpass -p "$PASSWORD" ssh -T $USERNAME@$HOST

  echo "Copying Home Folder"
  # rather than doing an scp -r of the whole folder, use rsync to exclude
  # files that we know we don't care about
  BKUP_EXCLUDES="--exclude '*_ws/build' --exclude '*_ws/devel' --exclude '*_ws/install'"
  sshpass -p "$PASSWORD" rsync -ar --progress -e "ssh -l $USERNAME" $BKUP_EXCLUDES $HOST:/home/$USERNAME .

  cd ..
  echo "Done Transfer"
  #################################################################

  ######################## REMOVE BIN+DEV #########################
  #echo "Cleaning"
  rm -rf $1/$USERNAME/catkin_ws/build/
  rm -rf $1/$USERNAME/catkin_ws/devel/
  #echo "Done"
  #################################################################

  ########################## COMPRESSION ##########################
  echo "Compressing"
  tar -zcf $CUSTOMER.tar.gz $CUSTOMER
  echo "Done Compression"
  #################################################################

  ########################### CLEANING ############################
  echo "Cleaning Up"
  rm -rf $CUSTOMER
  echo "Done Cleaning"
  #################################################################

  echo "======= Done Clearpath Robotics Robot Backup v$VERSION ======="
else
  echo "USAGE: bash backup.sh customer_name [user@]hostname [password]"
fi
