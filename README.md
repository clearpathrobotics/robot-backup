# Robot Backup
This package will automatically backup a remote robot's core files and directories to your local machine into a single archive. This package will also restore the backed up files onto a robot. This package can also handle backing up files on a robot running an older ROS distro (i.e. ROS Kinetic), and restoring the backed files on a robot running a newer ROS distro (i.e. ROS Melodic).

## Usage - Backing things up
Ensure you have ```sshpass``` and ```rsync``` installed:

```sudo apt-get install sshpass```
```sudo apt-get install rsync```

Then run the backup script. It may take several minutes depending on the amount of data being transferred:

```bash backup.sh backup_name [user@]hostname [password]```

e.g.

```bash backup.sh my_robot 10.0.1.42```

The script will log into the robot using SSH using and create a backup called ```backup_name.tar.gz``` (or ```my_robot.tar.gz```, in the example above).  If your robot does not use the default Clearpath username "administrator" and default password "clearpath" you may specify the correct username & password as additional arguments.  For example, a Jackal using a Jetson TX2 would use:

```bash backup.sh my_robot nvidia@10.0.1.42 nvidia```

The backup script will copy the following data, which can be restored later (see below):

- Home Folder: ```~/```
- ```udev``` Rules: ```/etc/udev/rules.d```
- Network Setup:
  - ```/etc/network/interfaces```
  - ```/etc/netplan```
  - ```/etc/netplan```
  - ```/etc/hostname```
  - ```/etc/hosts```
- IP Tables: ```/etc/iptables```
- Bringup Files:
  - ```/etc/ros/setup.bash```
  - ```/etc/ros/$ROSDISTRO/ros.d```
  - ```/usr/sbin/*start```
  - ```/usr/sbin/*stop```
- ```rosdep``` sources: ```/etc/ros/rosdep```
- ```rc.local``` File: ```/etc/rc.local```
- ```pip``` packages
- ```systemd``` configuration: ```/etc/systemd/system```
- ```apt``` sources: ```/etc/apt/sources.list.d```
- ```apt``` packages
- User Permission Groups

## Usage - Restoring from a backup
Before restoring from the backup you may find it helpful to completely reset your robot to its factory OS.  You can download OS installation images from Clearpath Robotics here: http://packages.clearpathrobotics.com/stable/images/latest/.  Simply download the image appropriate to your robot, write it to a USB drive using unetbootin (or a similar tool), and follow the instructions in your robot's user manual for reinstalling the OS.  You can find the user guides & tutorials here: https://support.clearpathrobotics.com/hc/en-us

Once the OS has been reinstalled (or if you do not wish to reinstall the OS and just want to restore the backed-up files), simply copy the ```restore.sh``` script & the backup file you previously created onto the robot.  Then run

```bash restore.sh backup_name```

e.g.

```bash restore.sh my_robot```

Do not run the restore script as root, as doing so may result in errors.

## Usage - Upgrading ROS Distro
*WARNING* This feature is experimental and may not work 100% correctly yet.

You can also use the ```upgrade.sh``` script to restore your backup & upgrade from the backup's ROS distro to the robot's current's ROS distro. For example, you can backup the contents on a robot running ROS Melodic, upgrade the robot to ROS Noetic, then use the ```upgrade.sh``` script to restore and upgrade all the backed up files and directories to ROS Noetic.

To do this:
1. Back up your robot as normal. 
2. Download the desired installation image for your robot from http://packages.clearpathrobotics.com/stable/images/latest/ 
3. Install the image as normal.
4. Once the upgraded OS is installed, copy the backup ```tar.gz``` file & ```upgrade.sh``` to your robot and run the following command: ```bash upgrade.sh backup_name```

This will do the same procedure as the ```restore.sh script```, described above, but also attempt to change any references of the old ROS distro to the new ROS distro. For example, if upgrading from ROS Melodic to ROS Noetic, certain known files & folders will also be migrated:

- ```$HOME/.bashrc will``` have all instances of "melodic" replaced with "noetic"
- ```/etc/ros/setup.bash``` will have all instances of "melodic" replaced with "noetic"
- ```/etc/ros/melodic/*``` will be copied to ```/etc/ros/noetic/*```

Note that user-generated files in the home folder, as well as any files the user modified themselves elsewhere on the system may not be correctly migrated; in this case it is incumbant upon the user to migrate their own files manually as necessary.

We recommend using the default "No" option when asked to reinstall APT packages.  By default the upgrade script will make a file in the user's home folder called ```restore-apt.sh```, which will contain the names of all packages to be installed.  We advise double-checking this list and ensuring that all packages are correct before running ```restore-apt.sh```.

## Troubleshooting
The backup.sh script can hang if you have not previously SSH'd into your robot, or if its SSH keys have changed.  If this occurs, run the following command on your local computer:

```mv ~/.ssh/known_hosts ~/.ssh/known_hosts.bak.$(date +"%Y%m%d%H%M")```

Then ssh into your robot again, and add its signature to your known hosts.  Then run backup.sh again.