#!/bin/sh
#
####################################################################################################
#
# NAME
#	Power_Users.sh
#
# DESCRIPTION
#	This script is intended to create non-admin "Power Users". 
#   There are some locked Systems Preferences that non-admin users may need to access. 
#	This may be System Preferences like Energy Saver, Printers, Date & Time, Startup Disk, and Time Machine.
#	This can be accomplished using the "security authorizationdb" command.
#	For details on the "security authorizationdb" command see Rich Trouton's blog.
#	http://derflounder.wordpress.com/2014/02/16/managing-the-authorization-database-in-os-x-mavericks/
#	The inspiration for the script came from MattsMacBlog
#	http://mattsmacblog.wordpress.com/2012/01/05/making-use-of-the-etcauthorization-file-in-lion-10-7-x/ 
#
# SYNOPSIS
#	sudo Power_Users.sh
#	sudo Power_Users.sh <mountPoint> <computerName> <currentUsername> <AllowEnergysaverPrefs> <AllowPrintingPrefs> <AllowDatetimePrefs> <AllowStartupdiskPrefs> <AllowTimemachinePrefs> <AllowNetworkPrefs>
#	
#	Parameter 1, 2, and 3 will not be used in this script, but since they are passed by
#	Jamf Pro, we will start using parameters at parameter 4.
#	If no parameter is specified for parameters 4 - 9, the hardcoded value in the script
#	will be used.  If values are hardcoded in the script for the parameters, then they will override
#	any parameters that are passed by Jamf Pro.
#
#	Parameters $4 - $9 should be set to the following values. 		
#		"yes"
#		"no"
#	If a value is blank "no" is assumed. This is handy for undoing all.
#
####################################################################################################
#
### Ensure we are running this script as root ###
if [ "$(/usr/bin/whoami)" != "root" ] ; then
  /bin/echo "This script must be run as root or sudo."
  exit 1
fi
###
#
####################################################################################################
#
# DEFINE VARIABLES & READ IN PARAMETERS
#
####################################################################################################

# macOS Version
sw_vers_Full=$(/usr/bin/sw_vers -productVersion)
sw_vers_Full_Integer=$(/usr/bin/sw_vers -productVersion | /usr/bin/awk -F. '{for(i=1; i<=NF; i++) {printf("%02d",$i)}}')
sw_vers_Major=$(/usr/bin/sw_vers -productVersion | /usr/bin/cut -d. -f 1,2)
sw_vers_Major_Integer=$(/usr/bin/sw_vers -productVersion | /usr/bin/cut -d. -f 1,2 | /usr/bin/awk -F. '{for(i=1; i<=NF; i++) {printf("%02d",$i)}}')

# Jamf Environmental Positional Variables.
# $1 Mount Point
# $2 Computer Name
# $3 Current User Name - This can only be used with policies triggered by login or logout.
# Declare the Environmental Positional Variables so the can be used in function calls.
mountPoint=$1
computerName=$2
username=$3
currentUser=$(/bin/echo 'show State:/Users/ConsoleUser' | /usr/sbin/scutil | /usr/bin/awk '/Name / { print $3 }')
computerName=$(/usr/sbin/scutil --get ComputerName)

# Parameter 4 Label: Energy Saver Prefs (yes/no)
# Parameter 5 Label: Printing Prefs (yes/no)
# Parameter 6 Label: Date and Time Prefs (yes/no)
# Parameter 7 Label: Startup Disk Prefs (yes/no)
# Parameter 8 Label: Time Machine Prefs (yes/no)
# Parameter 9 Label: Network Prefs (yes/no)

# HARDCODED VALUES SET HERE - There is no need to edit this if you are going to use this 
# script via a Jamf Pro JSS policy. Just specify "yes" or "no" in the policy parameters.
AllowEnergysaverPrefs="" 	# Allow the Energy Saver preference pane for the group everyone? yes/no
AllowPrintingPrefs=""		# Allow the Printing preference pane for the group everyone, and add the group everyone into the group lpadmin? yes/no
AllowDatetimePrefs=""		# Allow the Date and Time preference pane for the group everyone? yes/no
AllowStartupdiskPrefs=""	# Allow the Startup Disk preference pane for the group everyone? yes/no
AllowTimemachinePrefs="" 	# Allow the Time Machine preference pane for the group everyone? yes/no
AllowNetworkPrefs="" 		# Allow the Network preference pane for the group everyone? yes/no

# CHECK TO SEE IF VALUES WERE PASSED IN FOR PARAMETERS $4 THROUGH $9 AND, IF SO, ASSIGN THEM
if [ "$4" != "" ]; then
	AllowEnergysaverPrefs=$4
fi
#
if [ "$5" != "" ]; then
	AllowPrintingPrefs=$5
fi
#
if [ "$6" != "" ]; then
	AllowDatetimePrefs=$6
fi
#
if [ "$7" != "" ]; then
	AllowStartupdiskPrefs=$7
fi
#
if [ "$8" != "" ]; then
	AllowTimemachinePrefs=$8
fi
#
if [ "$9" != "" ]; then
	AllowNetworkPrefs=$9
fi
#
# If any system pref is to be unlocked the AllPrefs variable is marked "YES". 
AllPrefs="$AllowEnergysaverPrefs $AllowPrintingPrefs $AllowDatetimePrefs $AllowStartupdiskPrefs $AllowTimemachinePrefs $AllowNetworkPrefs"

/bin/echo "$computerName" is running macOS version "$sw_vers_Full"
/bin/echo ""
/bin/echo variable AllowEnergysaverPrefs is "$AllowEnergysaverPrefs"
/bin/echo variable AllowPrintingPrefs is "$AllowPrintingPrefs"
/bin/echo variable AllowDatetimePrefs is "$AllowDatetimePrefs"
/bin/echo variable AllowStartupdiskPrefs is "$AllowStartupdiskPrefs"
/bin/echo variable AllowTimemachinePrefs is "$AllowTimemachinePrefs"
/bin/echo variable AllowNetworkPrefs is "$AllowNetworkPrefs"
/bin/echo variable AllPrefs is "$AllPrefs"

####################################################################################################
# 
# SCRIPT CONTENTS
#
####################################################################################################

# Use the command "security authorizationdb" to give members of the group "everyone" access to specified System Preferences.
# This is a way to make "Power Users" without giving full admin rights.

### AllowSystemPrefs - This must be automatically set if you unlock any of the System prefs.
/bin/echo ""
/bin/echo "Set permissions for System Prefs"
if [[ "$AllPrefs" == *"yes"* ]] ; then
	/usr/bin/security authorizationdb read  system.preferences > /tmp/system.preferences.plist
	/usr/bin/defaults write /tmp/system.preferences.plist group everyone
	/usr/bin/security authorizationdb write system.preferences < /tmp/system.preferences.plist
else
	#Use this to undo the above command.
	/usr/bin/security authorizationdb read  system.preferences > /tmp/system.preferences.plist
	/usr/bin/defaults write /tmp/system.preferences.plist group admin
	/usr/bin/security authorizationdb write system.preferences < /tmp/system.preferences.plist
fi
	# Double Check the group setting.
	/bin/echo $(/usr/bin/defaults read /tmp/system.preferences.plist group)" has access to system prefs"

### AllowEnergysaverPrefs
/bin/echo ""
/bin/echo "Set permissions for Energy Saver Prefs"
if [[ "$AllowEnergysaverPrefs" == "yes" ]] ; then
	/bin/echo "Authorize non-admin users (everyone) access to the Energy Saver system pref"
	/usr/bin/security authorizationdb read  system.preferences.energysaver > /tmp/system.preferences.energysaver.plist
	/usr/bin/defaults write /tmp/system.preferences.energysaver.plist group everyone
	/usr/bin/security authorizationdb write system.preferences.energysaver < /tmp/system.preferences.energysaver.plist
else
	/bin/echo "Revoke non-admin users (everyone) access to the Energy Saver system pref" #Use this to undo the above command.
	/usr/bin/security authorizationdb read  system.preferences.energysaver > /tmp/system.preferences.energysaver.plist
	/usr/bin/defaults write /tmp/system.preferences.energysaver.plist group admin
	/usr/bin/security authorizationdb write system.preferences.energysaver < /tmp/system.preferences.energysaver.plist
fi
	# Double Check the group setting.
	/bin/echo $(/usr/bin/defaults read /tmp/system.preferences.energysaver.plist group)" has access to energysaver prefs"

### AllowPrintingPrefs
/bin/echo ""
/bin/echo "Set permissions for Printing Prefs"
if [[ "$AllowPrintingPrefs" == "yes" ]] ; then
	/bin/echo "Authorize non-admin users (everyone) access to the Printing system pref"
	/usr/bin/security authorizationdb read  system.preferences.printing > /tmp/system.preferences.printing.plist
	/usr/bin/defaults write /tmp/system.preferences.printing.plist group everyone
	/usr/bin/security authorizationdb write system.preferences.printing < /tmp/system.preferences.printing.plist
	/bin/echo "Adding the group everyone to the lpadmin group"
	/usr/sbin/dseditgroup -o edit -n /Local/Default -a "everyone" -t group lpadmin
else
	/bin/echo "Revoke non-admin users (everyone) access to the Printing system pref" #Use this to undo the above command.
	/usr/bin/security authorizationdb read  system.preferences.printing > /tmp/system.preferences.printing.plist
	/usr/bin/defaults write /tmp/system.preferences.printing.plist group admin
	/usr/bin/security authorizationdb write system.preferences.printing < /tmp/system.preferences.printing.plist
	/bin/echo "Removing the group everyone from the lpadmin group" #Use this to undo the above command.
	/usr/sbin/dseditgroup -o edit -n /Local/Default -d "everyone" -t group lpadmin
fi
	# Double Check the group setting.
	/bin/echo $(/usr/bin/defaults read /tmp/system.preferences.printing.plist group)" has access to printing system prefs"

### AllowDatetimePrefs
/bin/echo ""
/bin/echo "Set permissions for Date and Time Prefs"
if [[ "$AllowDatetimePrefs" == "yes" ]] ; then
	/bin/echo "Authorize non-admin users (everyone) access to the Date & Time system pref"
	/usr/bin/security authorizationdb read  system.preferences.datetime > /tmp/system.preferences.datetime.plist
	/usr/bin/defaults write /tmp/system.preferences.datetime.plist group everyone
	/usr/bin/security authorizationdb write system.preferences.datetime < /tmp/system.preferences.datetime.plist
else
	/bin/echo "Revoke non-admin users (everyone) access to the Date & Time system pref" #Use this to undo the above command.
	/usr/bin/security authorizationdb read  system.preferences.datetime > /tmp/system.preferences.datetime.plist
	/usr/bin/defaults write /tmp/system.preferences.datetime.plist group admin
	/usr/bin/security authorizationdb write system.preferences.datetime < /tmp/system.preferences.datetime.plist
fi
	# Double Check the group setting.
	/bin/echo $(/usr/bin/defaults read /tmp/system.preferences.datetime.plist group)" has access to datetime system prefs"

### AllowStartupdiskPrefs
/bin/echo ""
/bin/echo "Set permissions for Startup Disk Prefs"
if [[ "$AllowStartupdiskPrefs" == "yes" ]] ; then
	/bin/echo "Authorize non-admin users (everyone) access to the Startup Disk system pref"
	/usr/bin/security authorizationdb read  system.preferences.startupdisk > /tmp/system.preferences.startupdisk.plist
	/usr/bin/defaults write /tmp/system.preferences.startupdisk.plist group everyone
	/usr/bin/security authorizationdb write system.preferences.startupdisk < /tmp/system.preferences.startupdisk.plist
else
	/bin/echo "Revoke non-admin users (everyone) access to the Startup Disk system pref" #Use this to undo the above command.
	/usr/bin/security authorizationdb read  system.preferences.startupdisk > /tmp/system.preferences.startupdisk.plist
	/usr/bin/defaults write /tmp/system.preferences.startupdisk.plist group admin
	/usr/bin/security authorizationdb write system.preferences.startupdisk < /tmp/system.preferences.startupdisk.plist
fi
	# Double Check the group setting.		
	/bin/echo $(/usr/bin/defaults read /tmp/system.preferences.startupdisk.plist group)" has access to startupdisk system prefs"

### AllowTimemachinePrefs
/bin/echo ""
/bin/echo "Set permissions for Time Machine Prefs"
if [[ "$AllowTimemachinePrefs" == "yes" ]] ; then
	/bin/echo "Authorize non-admin users (everyone) access to the Time Machine system pref"
	/usr/bin/security authorizationdb read  system.preferences.timemachine > /tmp/system.preferences.timemachine.plist
	/usr/bin/defaults write /tmp/system.preferences.timemachine.plist group everyone
	/usr/bin/security authorizationdb write system.preferences.timemachine < /tmp/system.preferences.timemachine.plist
else
	/bin/echo "Revoke non-admin users (everyone) access to the Time Machine system pref" #Use this to undo the above command.
	/usr/bin/security authorizationdb read  system.preferences.timemachine > /tmp/system.preferences.timemachine.plist
	/usr/bin/defaults write /tmp/system.preferences.timemachine.plist group admin
	/usr/bin/security authorizationdb write system.preferences.timemachine < /tmp/system.preferences.timemachine.plist
fi
	# Double Check the group setting.
	/bin/echo $(/usr/bin/defaults read /tmp/system.preferences.timemachine.plist group)" has access to timemachine system prefs"

### AllowNetworkPrefs
/bin/echo ""
/bin/echo "Set permissions for Network Prefs"
if [[ "$AllowNetworkPrefs" == "yes" ]] ; then
	/bin/echo "Authorize non-admin users (everyone) access to the Network system pref"
	/usr/bin/security authorizationdb read  system.preferences.network > /tmp/system.preferences.network.plist
	/usr/bin/defaults write /tmp/system.preferences.network.plist group everyone
	/usr/bin/security authorizationdb write system.preferences.network < /tmp/system.preferences.network.plist
#
	/usr/bin/security authorizationdb read  system.services.systemconfiguration.network > /tmp/system.services.systemconfiguration.network.plist
	/usr/bin/defaults write /tmp/system.services.systemconfiguration.network.plist group everyone
	/usr/bin/security authorizationdb write system.services.systemconfiguration.network < /tmp/system.services.systemconfiguration.network.plist
else
	/bin/echo "Revoke non-admin users (everyone) access to the Network system pref" #Use this to undo the above command.
	/usr/bin/security authorizationdb read  system.preferences.network > /tmp/system.preferences.network.plist
	/usr/bin/defaults write /tmp/system.preferences.network.plist group admin
	/usr/bin/security authorizationdb write system.preferences.network < /tmp/system.preferences.network.plist
	#
	/usr/bin/security authorizationdb read  system.services.systemconfiguration.network > /tmp/system.services.systemconfiguration.network.plist
	/usr/bin/defaults write /tmp/system.services.systemconfiguration.network.plist group admin
	/usr/bin/security authorizationdb write system.services.systemconfiguration.network < /tmp/system.services.systemconfiguration.network.plist
fi
	# Double Check the group setting.
	/bin/echo $(/usr/bin/defaults read /tmp/system.preferences.network.plist group)" has access to network system prefs"
	/bin/echo $(/usr/bin/defaults read /tmp/system.services.systemconfiguration.network.plist group)" has access to network systemconfiguration"

exit 0
