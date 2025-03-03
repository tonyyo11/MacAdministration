#!/bin/bash
#
####################################################################################################
#
# ABOUT THIS PROGRAM
#
# NAME
#	Check_AD_Network_Status.sh
#
#	This script checks to see if the specified Active Directory domain is available.
#	If the AD network is available a Jamf policy to bind to AD can be called with a customer trigger.
#
#	This can be used in an "On Enrollment" policy. 
#
####################################################################################################
#
# DEFINE VARIABLES & READ IN PARAMETERS
#
####################################################################################################
# HARDCODED VALUES ARE SET HERE
# macOS Version
sw_vers_Full=$(/usr/bin/sw_vers -productVersion)
sw_vers_Full_Integer=$(/usr/bin/sw_vers -productVersion | /usr/bin/awk -F. '{for(i=1; i<=NF; i++) {printf("%02d",$i)}}')
sw_vers_Major=$(/usr/bin/sw_vers -productVersion | /usr/bin/cut -d. -f 1,2)
sw_vers_Major_Integer=$(/usr/bin/sw_vers -productVersion | /usr/bin/cut -d. -f 1,2 | /usr/bin/awk -F. '{for(i=1; i<=NF; i++) {printf("%02d",$i)}}')
# Jamf Environmental Positional Variables.
# $1 Mount Point
# $2 Computer Name
# $3 Current User Name - This can only be used with policies triggered by login or logout.
# Declare the Enviromental Positional Variables so the can be used in function calls.
mountPoint=$1
computerName=$2
username=$3
currentUser=$(/bin/echo 'show State:/Users/ConsoleUser' | /usr/sbin/scutil | /usr/bin/awk '/Name / { print $3 }')
computerName=$(/usr/sbin/scutil --get ComputerName)
# HARDCODED VALUE FOR "FQDN" IS SET HERE
# Jamf Parameter Value Label - AD Domain FQDN
FQDN=""
# CHECK TO SEE IF A VALUE WAS PASSED IN PARAMETER 4 AND, IF SO, ASSIGN TO "FQDN"
# If a value is specified via a Jamf policy, it will override the hardcoded value in the script.
if [ "$4" != "" ];then
    FQDN=$4
fi
# HARDCODED VALUE FOR "ADTrigger" IS SET HERE
# Jamf Parameter Value Label - AD Policy custom trigger
ADTrigger=""
# CHECK TO SEE IF A VALUE WAS PASSED IN PARAMETER 5 AND, IF SO, ASSIGN TO "ADTrigger"
# If a value is specified via a Jamf policy, it will override the hardcoded value in the script.
if [ "$5" != "" ];then
    ADTrigger=$5
fi
#
/bin/echo "$computerName" is running is macOS version "$sw_vers_Full"
#
#####################################################################################################
#
# Functions to call on
#
####################################################################################################
#
### Ensure we are running this script as root ###
rootcheck () {
if [ "`/usr/bin/whoami`" != "root" ] ; then
  /bin/echo "This script must be run as root or sudo."
  exit 0
fi
}
###
#
#
### Verify the AD network is available then run AD bind policy ###
Check_AD_and_Bind () {
/usr/bin/nc -vz $FQDN 389
if [[ $? -eq 0 ]]; then
	/bin/echo "$FQDN is available"
	jamf policy -event $ADTrigger
else
	/bin/echo "$FQDN is NOT available"
fi
}
###
#
####################################################################################################
# 
# SCRIPT CONTENTS
#
####################################################################################################
rootcheck
Check_AD_and_Bind
exit 0
