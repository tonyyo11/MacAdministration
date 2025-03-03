#!/bin/bash
#
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
# This script should detect the names of any present network ports and set IPv6 to Off.
#
# SYNOPSIS
#	sudo Configure_IPv6_Off.sh <mountPoint> <computerName> <currentUsername> <portsToIgnore>
#
#####################################################################################################
#
# DEFINE VARIABLES & READ IN PARAMETERS
#
####################################################################################################
#
# Set to the default BASH limiters
IFS=$' \t\n'
#
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

# HARDCODED VALUE FOR "portsToIgnore" IS SET HERE
# Jamf Parameter Value Label - Network ports to ignore
# Specify ports to ignore such as "Bluetooth FireWire iPhone iPad"
portsToIgnore="iBridge Bluetooth FireWire iPhone iPad"
# CHECK TO SEE IF A VALUE WAS PASSED IN PARAMETER 4 AND, IF SO, ASSIGN TO "portsToIgnore"
# If a value is specificed via a Jamf policy, it will override the hardcoded value in the script.
if [ "$4" != "" ];then
    portsToIgnore=$4
fi
portsToIgnore_Pattern=$( /bin/echo "disabled" $portsToIgnore | /usr/bin/sed 's/ /|/g' )

# HARDCODED VALUE FOR "SetIPv6" IS SET HERE
# Jamf Parameter Value Label - Set IPv6 (off | automatic)
SetIPv6="automatic"
# CHECK TO SEE IF A VALUE WAS PASSED IN PARAMETER 5 AND, IF SO, ASSIGN TO "SetIPv6"
# If a value is specificed via a Jamf policy, it will override the hardcoded value in the script.
if [ "$5" != "" ];then
    SetIPv6=$5
fi

/bin/echo "$computerName" is running macOS version "$sw_vers_Full"
/bin/echo "portsToIgnore_Pattern:	$portsToIgnore_Pattern"

/bin/echo "SetIPv6:	$SetIPv6"


#
#####################################################################################################
#
# Functions to call on
#
####################################################################################################

#
### Ensure we are running this script as root ###
rootcheck () {
if [ "$(/usr/bin/whoami)" != "root" ] ; then
	/bin/echo "This script must be run as root or sudo."
  exit 1
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

IFS=$'\n'
PortList=$(/usr/sbin/networksetup -listallnetworkservices | /usr/bin/egrep -v -e $portsToIgnore_Pattern)

# Now, for each port listed in PortList, turn off IPv6
# If an error presents during a config set (missing adapters), don't report the error, 1>/dev/null
for i in $PortList ; do
	IFS=$' \t\n'
	/usr/sbin/networksetup -setv6$SetIPv6 "$i" 1>/dev/null
	/bin/echo "port ": $i $(/usr/sbin/networksetup -getinfo "$i" | /usr/bin/grep "IPv6")
done

exit 0

#/usr/sbin/networksetup -setv6automatic "$i" 1>/dev/null
#/usr/sbin/networksetup -setv6off "$i" 1>/dev/null
