#!/bin/bash
####################################################################################################
#
# The Apple Software is provided by Apple on an "AS IS" basis.  APPLE
# MAKES NO WARRANTIES, EXPRESS OR IMPLIED, INCLUDING WITHOUT LIMITATION
# THE IMPLIED WARRANTIES OF NON-INFRINGEMENT, MERCHANTABILITY AND FITNESS
# FOR A PARTICULAR PURPOSE, REGARDING THE APPLE SOFTWARE OR ITS USE AND
# OPERATION ALONE OR IN COMBINATION WITH YOUR PRODUCTS.
#
# IN NO EVENT SHALL APPLE BE LIABLE FOR ANY SPECIAL, INDIRECT, INCIDENTAL
# OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
# SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
# INTERRUPTION) ARISING IN ANY WAY OUT OF THE USE, REPRODUCTION,
# MODIFICATION AND/OR DISTRIBUTION OF THE APPLE SOFTWARE, HOWEVER CAUSED
# AND WHETHER UNDER THEORY OF CONTRACT, TORT (INCLUDING NEGLIGENCE),
# STRICT LIABILITY OR OTHERWISE, EVEN IF APPLE HAS BEEN ADVISED OF THE
# POSSIBILITY OF SUCH DAMAGE.
#
####################################################################################################
#
# DESCRIPTION
#	The purpose of this script is to configure the built in Apple application firewall from the command line.
#
#	When used in a build configuration the script priority must be set to: At Reboot
#
# SYNOPSIS
#	sudo Configure_Firewall.sh
#	sudo Configure_Firewall.sh <mountPoint> <computerName> <currentUsername> <setglobalstate> <setallowsigned> <setallowsignedapp> <setstealthmode>
#
#	Display FireWal Help
#	/usr/libexec/ApplicationFirewall/socketfilterfw -h
#
#####################################################################################################
#
# DEFINE VARIABLES & READ IN PARAMETERS
#
####################################################################################################
#
# macOS Version
sw_vers_Full=$(/usr/bin/sw_vers -productVersion)
sw_vers_Full_Integer=$(/usr/bin/sw_vers -productVersion | /usr/bin/awk -F. '{for(i=1; i<=NF; i++) {printf("%02d",$i)}}')
sw_vers_Major=$(/usr/bin/sw_vers -productVersion | /usr/bin/cut -d. -f 1,2)
sw_vers_Major_Integer=$(/usr/bin/sw_vers -productVersion | /usr/bin/cut -d. -f 1,2 | /usr/bin/awk -F. '{for(i=1; i<=NF; i++) {printf("%02d",$i)}}')
# Casper Environmental Positional Variables.
# $1 Mount Point
# $2 Computer Name
# $3 Current User Name - This can only be used with policies triggered by login or logout.
# Declare the Enviromental Positional Variables so the can be used in function calls.
mountPoint=$1
computerName=$2
username=$3
#
# HARDCODED VALUE FOR "setglobalstate" IS SET HERE on | off
setglobalstate="on"
# CHECK TO SEE IF A VALUE WAS PASSED IN PARAMETER 4 AND, IF SO, ASSIGN TO "setglobalstate"
# If a value is specificed via a Jamf policy, it will override the hardcoded value in the script.
if [ "$4" != "" ];then
    setglobalstate=$4
fi
#
# HARDCODED VALUE FOR "setblockall" IS SET HERE on | off
setblockall="off"
# CHECK TO SEE IF A VALUE WAS PASSED IN PARAMETER 5 AND, IF SO, ASSIGN TO "setblockall"
# If a value is specificed via a Jamf policy, it will override the hardcoded value in the script.
if [ "$5" != "" ];then
    setblockall=$5
fi
#
# HARDCODED VALUE FOR "setallowsigned" IS SET HERE on | off
setallowsigned="on"
# CHECK TO SEE IF A VALUE WAS PASSED IN PARAMETER 6 AND, IF SO, ASSIGN TO "setallowsigned"
# If a value is specificed via a Jamf policy, it will override the hardcoded value in the script.
if [ "$6" != "" ];then
    setallowsigned=$6
fi
#
# HARDCODED VALUE FOR "setallowsignedapp" IS SET HERE on | off
setallowsignedapp="on"
# CHECK TO SEE IF A VALUE WAS PASSED IN PARAMETER 7 AND, IF SO, ASSIGN TO "setallowsignedapp"
# If a value is specificed via a Jamf policy, it will override the hardcoded value in the script.
if [ "$7" != "" ];then
    setallowsignedapp=$7
fi
#
# HARDCODED VALUE FOR "setstealthmode" IS SET HERE on | off
setstealthmode="on"
# CHECK TO SEE IF A VALUE WAS PASSED IN PARAMETER 8 AND, IF SO, ASSIGN TO "setstealthmode"
# If a value is specificed via a Jamf policy, it will override the hardcoded value in the script.
if [ "$8" != "" ];then
    setstealthmode=$8
fi
#
/bin/echo "$computerName" is running macOS version "$sw_vers_Full"
/bin/echo "setglobalstate:		$setglobalstate"
/bin/echo "setblockall:		$setblockall"
/bin/echo "setallowsigned:		$setallowsigned"
/bin/echo "setallowsignedapp:	$setallowsignedapp"
/bin/echo "setstealthmode:		$setstealthmode"
#
#####################################################################################################
#
# Functions to call on
#
####################################################################################################
#
### Ensure we are running this script as root ###
function rootcheck () {
#/bin/echo Begin rootcheck
if [ "$(/usr/bin/whoami)" != "root" ] ; then
	/bin/echo "This script must be run as root or sudo."
  exit 2
fi
#
#/bin/echo "End rootcheck"
}
###
#
####################################################################################################
# 
# SCRIPT CONTENTS
#
####################################################################################################
rootcheck
/usr/libexec/ApplicationFirewall/socketfilterfw --setglobalstate $setglobalstate
/usr/libexec/ApplicationFirewall/socketfilterfw --setblockall $setblockall
/usr/libexec/ApplicationFirewall/socketfilterfw --setallowsigned $setallowsigned
/usr/libexec/ApplicationFirewall/socketfilterfw --setallowsignedapp $setallowsignedapp
/usr/libexec/ApplicationFirewall/socketfilterfw --setstealthmode $setstealthmode
/usr/libexec/ApplicationFirewall/socketfilterfw --getglobalstate
exit 0
