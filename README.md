# Robot Backup
This package will automatically backup a remote robot to your local machine into a single archive.  It will Backup:

- etc/setup.bash
- Home Folder
- udev rules
- Network Setup
- IPTables
- Bringup

## Usage - Backing things up
Ensure you have sshpass installed:

```sudo apt-get install sshpass```

Then run the backup script. It may take several minutes depending on the amount of data being transferred:

```bash backup.sh backup_name hostname [username [password]]```

e.g.

```bash backup.sh my_robot 10.0.1.42```

The script will log into the robot using SSH using and create a backup called backup_name.tar.gz (or my_robot.tar.gz, in the example above).  If your robot does not use the default Clearpath username "administrator" and default password "clearpath" you may specify the correct username & password as additional arguments.  For example, a Jackal using a Jetson TX2 would use:

```bash backup.sh my_robot 10.0.1.42 nvidia nvidia```

The backup script will copy the following data, which can be restored later (see below):

- all packages installed through APT
- all APT sources
- all ROSDEP sources
- ROS bringup configuration (/etc/ros/setup.bash, /etc/ros/<distro>/ros.d)
- networking configuration (iptables, interfaces, hosts, hostname)
- rc.local
- udev rules
- all packages installed through PIP
- systemd configuration
- contents of /usr/sbin
- contents of the provided user's home folder (/home/administrator by default)
- provided user's permission groups


## Usage - Restoring from a backup
Before restoring from the backup you may find it helpful to completely reset your robot to its factory OS.  You can download OS installation images from Clearpath Robotics here: http://packages.clearpathrobotics.com/stable/images/latest/.  Simply download the image appropriate to your robot, write it to a USB drive using unetbootin (or a similar tool), and follow the instructions in your robot's user manual for reinstalling the OS.  You can find the user guides & tutorials here: https://support.clearpathrobotics.com/hc/en-us

Once the OS has been reinstalled (or if you do not wish to reinstall the OS and just want to restore the backed-up files), simply copy the restore.sh script & the backup file you previously created onto the robot.  Then run

```bash restore.sh backup_name```

e.g.

```bash restore.sh my_robot```

Do not run the restore script as root, as doing so may result in errors.


## Troubleshooting
The backup.sh script can hang if you have not previously SSH'd into your robot, or if its SSH keys have changed.  If this occurs, run the following command on your local computer:

```mv ~/.ssh/known_hosts ~/.ssh/known_hosts.bak.$(date +"%Y%m%d%H%M")```

Then ssh into your robot again, and add its signature to your known hosts.  Then run backup.sh again.
