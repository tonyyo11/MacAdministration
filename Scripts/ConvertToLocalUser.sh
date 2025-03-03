#!/bin/bash
#
## =======================================================================================
## Script:	ConvertToLocalUser.sh
## Author:	Apple Professional Services
## Revision History:
## Date			Version	Personnel	Notes
## ----			-------	---------	-----
## 2016-10-01	1.0		Apple		Script created
## 2016-12-13	2.0		Apple		Added FileVault functionality - If the computer is FileVault Encrypted, and the current "Managed, Mobile" user is part of the FileVault users,
##									the "new" local account is added to the FileVault users. FileVault does not have to be decrypted. 
## 2017-03-19	2.1		Apple		"killall jamf" and  "killall Self \Service" was being used to stop the process and the reboot when a user canceled the self service policy.
##									That caused problems when trying to re-run the policy. Now it is just "killall Self \Service" and calling another policy just for the reboot.
##									Additionally, back-ticks for `code` have been replaced with $(code)
## 2017-04-18	2.2		Apple		Changed reboot method to call a separate reboot policy. Added RebootTrigger variable.
## 2017-06-06	2.2.1	Apple		Fixed the full path for /usr/bin/grep in a few lines.
## 2017-10-20	2.3		Apple		Non Destructive version. Uses dscl to Remove the account attributes that identify it as an Active Directory mobile account.
## 2018-09-12	2.4		Apple		Added an AC power check.
## 2018-12-19	2.5		Apple		Modified /usr/bin/dscl . -create /users/$currentuser AuthenticationAuthority "${shadowhash}"
##									https://derflounder.wordpress.com/2018/06/16/updated-migrateadmobileaccounttolocalaccount-script-now-available-to-fix-migration-bug/
## 2019-02-05	3.0		Apple		Updated for Mojave TCC support. Added option to keep original UID. This helps with TCC.
##									Removed need to call a separate reboot policy.
## 2019-04-04	3.1		Apple		Changed currentuser lookup to better handle multiple logged-in users
##									Modified how we handle AuthenticationAuthority to remove Kerberosv5 and LocalCachedUser (10.14.4 fix)
##									also, our previous method removed the SecureToken, which would prevent enabling FileVault2 after demobilizing an account, 
##									and potential issues down the road if already enabled.
##									Add warning for changing UID
## 2020-08-30	3.2		Apple		Modified sw_vers_Major_Integer to account for Big Sur macOS 11.0
## 
## =======================================================================================
#
####################################################################################################
#
# The Apple Software is provided by Apple on an "AS IS" basis.  APPLE
# MAKES NO WARRANTIES, EXPRESS OR IMPLIED, INCLUDING WITHOUT LIMITATION
# THE IMPLIED WARRANTIES OF NON-INFRINGEMENT, MERCHANTABILITY AND FITNESS
# FOR A PARTICULAR PURPOSE, REGARDING THE APPLE SOFTWARE OR ITS USE AND
# OPERATION ALONE OR IN COMBINATION WITH YOUR PRODUCTS.
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
#	The purpose of this script is to convert the currently logged in user from an AD "Managed, Mobile" network account 
#	to a local account. This can be useful when using Enterprise Connect.
#
#	If the computer is FileVault encrypted, and the current "Managed, Mobile" user is part of the FileVault users, 
#	the "new" converted local account is still a FileVault user. FileVault does not have to be decrypted.
#	An admin user will remain and admin user. A non-admin user will remain a non-admin user.
#
#	This script is intended to run as a Jamf Pro Self Service policy.
#	Jamf Pro - Convert to Local User Self Service policy settings:
#		General > Display Name (Suggested): Convert to Local User
#		General > Execution Frequency: Ongoing
#		Scripts: ConverttoLocalUser
#		Scripts > Parameter 4 (AskForUserPassword): no (Suggested)
#		Scripts > Parameter 5 (ChangeUID): no (Suggested)
#		Self Service > Make the policy available in Self Service: checked
#		Self Service > Button Name (Suggested): "Convert User"
#		Self Service > Description (Suggested): "This will convert your current network user account to a local account. 
#		When complete, your computer will REBOOT. 
#		Please SAVE all files and QUIT all apps before proceeding."
#		Self Service > Ensure that users view the description: checked
#
#	The policy running the script should NOT be set to restart or recon the computer. This script is configured to initiate the needed restart and recon.
#
# Caveats
#
#	If a local password policy is used and is more strict than the Active Directory password policy, 
#	the new converted local user account will be created but the user may not be able to log in.
#	Resetting the local user's password to meet the password local pasword policy will fix this after the fact. 
#	To avoid this, ensure the local and the Active Directory password policies are balanced, or the local policy 
#	is less strict or a local password policy is not used.
#
# Exit codes
#	rootcheck               exit 1
#	OSXVersioncheck         exit 2
#	MobileAccountcheck      exit 4
#	MessageToUser           exit 5
#	pmsetPowerStatus        exit 6
#	UserPassword_cancel     exit 7
#	ConvertToLocalAccount   exit 8
#
#####################################################################################################
#
# DEFINE VARIABLES & READ IN PARAMETERS
#
#####################################################################################################
#
# macOS Version
sw_vers_Full=$(/usr/bin/sw_vers -productVersion)
sw_vers_Full_Integer=$(/usr/bin/sw_vers -productVersion | /usr/bin/awk -F. '{for(i=1; i<=NF; i++) {printf("%02d",$i)}}')
sw_vers_Major=$(/usr/bin/sw_vers -productVersion | /usr/bin/cut -d. -f 1,2)
sw_vers_Major_Integer=$(/usr/bin/sw_vers -productVersion | /usr/bin/cut -d. -f 1,2 | /usr/bin/awk -F. '{for(i=1; i<=NF; i++) {printf("%02d",$i)}}')
computerName=$(/usr/sbin/scutil --get ComputerName)
currentuser=$(/bin/echo 'show State:/Users/ConsoleUser' | /usr/sbin/scutil | /usr/bin/awk '/Name / { print $3 }')
currentuserID=$(/usr/bin/id -u $currentuser)
DisplayDialogMessage=""
#
# HARDCODED VALUE FOR "AskForUserPassword" IS SET HERE - Ask for the user's password before converting to a local account? Yes or No
# Jamf Parameter Value Label - Ask For User Password (yes/no)
AskForUserPassword="no"
# CHECK TO SEE IF A VALUE WAS PASSED IN PARAMETER 4 AND, IF SO, ASSIGN TO "AskForUserPassword"
# If a value is specified via a casper policy, it will override the hardcoded value in the script.
if [ "$4" != "" ];then
	AskForUserPassword=$4
fi
#
# HARDCODED VALUE FOR "ChangeUID" IS SET HERE - Change User ID and Group ID to the next available ID over 501? Yes or No
# TCC can interfere with this option. ONLY use this if a Configuration Profile with a Privacy Preferences Policy Control payload for Jamf.
# Note that changing User ID can break User APNS (mdmclient agent), meaning that User-scoped profiles may not work anymore.
# It's probably easier (and safer) to keep User ID.
# Jamf Parameter Value Label - Change User ID (yes/no)
ChangeUID="no"
# CHECK TO SEE IF A VALUE WAS PASSED IN PARAMETER 5 AND, IF SO, ASSIGN TO "ChangeUID"
# If a value is specified via a casper policy, it will override the hardcoded value in the script.
if [ "$5" != "" ];then
	ChangeUID=$5
fi
#
/bin/echo "$computerName" is running is macOS version "$sw_vers_Full"
/bin/echo "currentuser: $currentuser"
/bin/echo "AskForUserPassword:  $AskForUserPassword"
/bin/echo "ChangeUID:   $ChangeUID"
#
#####################################################################################################
#
# Functions to call on
#
#####################################################################################################
#
### Ensure we are running this script as root ###
function rootcheck () {
/bin/echo "begin function rootcheck"
if [ "$(/usr/bin/whoami)" != "root" ] ; then
	/bin/echo "This script must be run as root or sudo."
	exit 1
fi
/bin/echo "end function rootcheck"
}
###
#

#
### Ensure we are running at least OS X 10.10.x ###
function OSXVersioncheck () {
/bin/echo "begin function OSXVersioncheck"
if [ "$sw_vers_Major_Integer" -lt 1010 ]; then
	/bin/echo "This script requires OS X 10.10 or greater."
	exit 2
fi
/bin/echo "end function OSXVersioncheck"
}
###
#

#
### Check to see if the current user is an AD mobile account ###
function ADMobileAccountcheck () {
/bin/echo "begin function ADMobileAccountcheck"
accountAuthAuthority=$(/usr/bin/dscl . -read /Users/"$currentuser" AuthenticationAuthority | tr -d '\n')
if [[ ! "$accountAuthAuthority" =~ "LocalCachedUser" ]] ; then
	/bin/echo "This is not an Active Directory mobile account."
	DisplayDialogMessage="This is not an Active Directory mobile account."
	/usr/bin/sudo -u "$currentuser" /usr/bin/osascript -e "display dialog \"$DisplayDialogMessage\" with icon stop buttons {\"End\"} default button 1"
	#/usr/bin/killall Self\ Service
	exit 4
fi
/bin/echo "end function ADMobileAccountcheck"
}
###
#

#
### Message to user, explaining what this script will do. ###
function MessageToUser () {
/bin/echo "begin function MessageToUser"
DisplayDialogMessage="This will convert $currentuser to a local account.
When complete, your computer will REBOOT.
Please SAVE all files and QUIT all apps before proceeding."
/usr/bin/sudo -u "$currentuser" /usr/bin/osascript -e "display dialog \"$DisplayDialogMessage\" with title \"Reboot Warning\" with icon caution" >/dev/null 2>&1
# Stop everything if the cancel button is pressed.
if [ $? -eq 1 ];
	then /bin/echo "User canceled policy.";
	#/usr/bin/killall Self\ Service
	exit 5
fi
/bin/echo "end function MessageToUser"
}
###
#

#
### Check to see if the system is connected to AC power. ###
function pmsetPowerStatus () {
/bin/echo "begin function pmsetPowerStatus"
PowerDraw=$(/usr/bin/pmset -g ps | /usr/bin/awk -F "'" '{ print $2;exit }')
until [ "$PowerDraw" == "AC Power" ]; do
	/bin/echo "Now drawing from 'Battery Power'"
	DisplayDialogMessage="Please connected your system to AC power."
	/usr/bin/sudo -u "$currentuser" /usr/bin/osascript -e "display dialog \"$DisplayDialogMessage\" with title \"Power Warning\" with icon stop" >/dev/null 2>&1
	# Stop everything if the cancel button is pressed.
	if [ $? -eq 1 ];
		then /bin/echo "User canceled policy.";
		#/usr/bin/killall Self\ Service
		exit 6
	fi
	/bin/sleep 2
	PowerDraw=$(/usr/bin/pmset -g ps | /usr/bin/awk 'NR>1{exit};1' | /usr/bin/awk '{print $4,$5}' | /usr/bin/sed "s/'//g")
done
/bin/echo "Now drawing from AC Power"
/bin/echo "end function pmsetPowerStatus"
}
###
#

#
### Begin Password stuff ###
# This is not specifically required for the script to work.
# It may be nice to check that the currently user knows their password.
function UserPassword () {
/bin/echo "begin function UserPassword"
# Display Dialog to capture user password.
DisplayDialogMessage="Please enter the password for user account - $currentuser."
PASSWORD=$(/usr/bin/sudo -u "$currentuser" /usr/bin/osascript -e "text returned of (display dialog \"$DisplayDialogMessage\" default answer \"\" buttons {\"Ok\" , \"Cancel\"} default button 1 with title\"Password\" with hidden answer)") >/dev/null 2>&1
# Stop everything if the cancel button is pressed.
if [ $? -eq 1 ];
	then /bin/echo "User canceled policy.";
	#/usr/bin/killall Self\ Service
	exit 7
fi
# Blank passwords don't work.
while [ "$PASSWORD" == "" ];
do
	/bin/echo "Password is blank";
	DisplayDialogMessage="A BLANK PASSWORD IS INVALID.
	Please enter the password for user account - $currentuser."
	PASSWORD=$(/usr/bin/sudo -u "$currentuser" /usr/bin/osascript -e "text returned of (display dialog \"$DisplayDialogMessage\" default answer \"\" buttons {\"Ok\" , \"Cancel\"} default button 1 with title\"Password\" with hidden answer)") >/dev/null 2>&1
	# Stop everything if the cancel button is pressed.
	if [ $? -eq 1 ];
		then /bin/echo "User canceled policy.";
		#/usr/bin/killall Self\ Service
		exit 7
	fi
done
# Verify user Password is correct
PASSWORDCHECK=$(/usr/bin/dscl /Local/Default -authonly $currentuser $PASSWORD)
until [ "$PASSWORDCHECK" == "" ];
do
	/bin/echo "Incorrect password, please retry."
	DisplayDialogMessage="INCORRECT PASSWORD
	Please re-enter the password for user account - $currentuser."
	PASSWORD=$(/usr/bin/sudo -u "$currentuser" /usr/bin/osascript -e "text returned of (display dialog \"$DisplayDialogMessage\" default answer \"\" buttons {\"Ok\" , \"Cancel\"} default button 1 with title\"Password\" with hidden answer)") >/dev/null 2>&1
	# Stop everything if the cancel button is pressed.
	if [ $? -eq 1 ];
		then /bin/echo "User canceled policy.";
		#/usr/bin/killall Self\ Service
		exit 7
	fi
	# Blank passwords don't work.
	while [ "$PASSWORD" == "" ];
	do
		/bin/echo "Password is blank";
		DisplayDialogMessage="A BLANK PASSWORD IS INVALID.
		Please enter the password for user account - $currentuser."
		PASSWORD=$(/usr/bin/sudo -u "$currentuser" /usr/bin/osascript -e "text returned of (display dialog \"$DisplayDialogMessage\" default answer \"\" buttons {\"Ok\" , \"Cancel\"} default button 1 with title\"Password\" with hidden answer)") >/dev/null 2>&1
		# Stop everything if the cancel button is pressed.
		if [ $? -eq 1 ];
			then /bin/echo "User canceled policy.";
			#/usr/bin/killall Self\ Service
			exit 7
		fi
	done
	PASSWORDCHECK=$(/usr/bin/dscl /Local/Default -authonly $currentuser $PASSWORD)
done
/bin/echo "end function UserPassword"
}
### End Password stuff ###
#

#
### Begin jamfHelper stuff ###
function jamfHelperCurtain () {
/bin/echo "begin function jamfHelperCurtain"
# Display Full screen message to user
/bin/echo "Put up the curtain."
#/usr/bin/sudo -u "$currentuser"
/Library/Application\ Support/JAMF/bin/jamfHelper.app/Contents/MacOS/jamfHelper -windowType fs -title "Convert to Local User" -heading "Restart Warning" -description "Please be patient as $currentuser is converted to a local account. This may take a few minutes. 
Please ignore any additional prompts.
Your system will restart when complete." -icon /System/Library/CoreServices/loginwindow.app/Contents/Resources/Restart.tiff &
/bin/echo "end function jamfHelperCurtain"
}
### End jamfHelper stuff ###
#


#
### Begin Convert To Local Account ###
function ConvertToLocalAccount () {
/bin/echo "begin function ConvertToLocalAccount"

# We use to preserve the account password by backing up password hash. This doesn't work on 10.14.4 anymore.
AuthenticationAuthority=$(/usr/bin/dscl -plist . -read /Users/$currentuser AuthenticationAuthority)
Kerberosv5=$(echo "${AuthenticationAuthority}" | xmllint --xpath 'string(//string[contains(text(),"Kerberosv5")])' -)
LocalCachedUser=$(echo "${AuthenticationAuthority}" | xmllint --xpath 'string(//string[contains(text(),"LocalCachedUser")])' -)

# Remove Kerberosv5 and LocalCachedUser
if [[ ! -z "${Kerberosv5}" ]]; then
	/usr/bin/dscl -plist . -delete /Users/$currentuser AuthenticationAuthority "${Kerberosv5}"
fi

if [[ ! -z "${LocalCachedUser}" ]]; then
	/usr/bin/dscl -plist . -delete /Users/$currentuser AuthenticationAuthority "${LocalCachedUser}"
fi

# Remove the account attributes that identify it as an Active Directory mobile account
/usr/bin/dscl . -delete /users/$currentuser dsAttrTypeNative:preserved_attributes
/usr/bin/dscl . -delete /users/$currentuser cached_groups
/usr/bin/dscl . -delete /users/$currentuser cached_auth_policy
/usr/bin/dscl . -delete /users/$currentuser CopyTimestamp
# removing AltSecurityIdentities will break/un-pair/un-map an existing smart card for the current user.
# /usr/bin/dscl . -delete /users/$currentuser AltSecurityIdentities
/usr/bin/dscl . -delete /users/$currentuser SMBPrimaryGroupSID
/usr/bin/dscl . -delete /users/$currentuser OriginalAuthenticationAuthority
/usr/bin/dscl . -delete /users/$currentuser OriginalNodeName
/usr/bin/dscl . -delete /users/$currentuser SMBSID
/usr/bin/dscl . -delete /users/$currentuser SMBScriptPath
/usr/bin/dscl . -delete /users/$currentuser SMBPasswordLastSet
/usr/bin/dscl . -delete /users/$currentuser SMBGroupRID
/usr/bin/dscl . -delete /users/$currentuser PrimaryNTDomain
/usr/bin/dscl . -delete /users/$currentuser AppleMetaRecordName
/usr/bin/dscl . -delete /users/$currentuser PrimaryNTDomain
/usr/bin/dscl . -delete /users/$currentuser MCXSettings
/usr/bin/dscl . -delete /users/$currentuser MCXFlags
#
# Refresh Directory Services
/usr/bin/killall opendirectoryd
sleep 5
#
accountAuthAuthority=$(/usr/bin/dscl . -read /Users/"$currentuser" AuthenticationAuthority | tr -d '\n')
if [[ "$accountAuthAuthority" =~ "Active Directory" ]]; then
	/bin/echo "Something went wrong with the conversion process. The $currentuser account is still an AD mobile account."
	exit 8
else
	/bin/echo "Conversion process was successful. The $currentuser account is now a local account."
fi
# Add user to the staff group on the Mac
/bin/echo "Adding $currentuser to the staff group on this Mac."
/usr/sbin/dseditgroup -o edit -a "$currentuser" -t user staff
#
/bin/echo "UniqueID is $(/usr/bin/dscl . -read /Users/$currentuser UniqueID | /usr/bin/awk '{print $2}')"
/bin/echo "PrimaryGroupID is $(/usr/bin/dscl . -read /Users/$currentuser PrimaryGroupID | /usr/bin/awk '{print $2}')"
/bin/ls -alnd "$(/usr/bin/dscl . -read /Users/"$currentuser" NFSHomeDirectory  | awk '{print $2}')"
#
/bin/echo "end function ConvertToLocalAccount"
}
### End Convert To Local Account ###
#

#
### Begin Change UID and GID ###
# TCC can interfere with this option. ONLY use this if a Configuration Profile with a Privacy Preferences Policy Control payload for Jamf.
function ChangeUIDandGID () {
/bin/echo "begin function ChangeUIDandGID"
# Get the next available local UID
NEWLOCALUID=$(($(/usr/bin/dscl . list /Users UniqueID | /usr/bin/awk '$2 > 500 && $2 < 1000 { print $2 }' | sort -ug | tail -1)+ 1))
/bin/echo "New Local ID: $NEWLOCALUID"
homedir=$(/usr/bin/dscl . -read /Users/"$currentuser" NFSHomeDirectory  | awk '{print $2}')
/bin/echo "Home directory location: $homedir"
#
# Change UniqueID to a local UniqueID
/usr/bin/dscl . -create /Users/$currentuser UniqueID $NEWLOCALUID
dsclUniqueID=$(/usr/bin/dscl . -read /Users/$currentuser UniqueID | /usr/bin/awk '{print $2}')
/bin/echo "dsclUniqueID is $dsclUniqueID"
#
# Change PrimaryGroupID to a local group staff
/usr/bin/dscl . -create /Users/$currentuser PrimaryGroupID 20
dsclPrimaryGroupID=$(/usr/bin/dscl . -read /Users/$currentuser PrimaryGroupID | /usr/bin/awk '{print $2}')
/bin/echo "dsclPrimaryGroupID is $dsclPrimaryGroupID"
#
# Refresh Directory Services
/usr/bin/killall opendirectoryd
sleep 5
#
if [[ "$homedir" != "" ]]; then
	/bin/echo "Updating home folder permissions for $homedir from dscl"
	/usr/bin/chflags -R nouchg "$homedir"
	sleep 5
	/usr/sbin/chown -R "$currentuser":"staff" "$homedir"
	/bin/ls -alnd "$homedir"
else
	/bin/echo "Updating home folder permissions for /Users/$currentuser hardcoded"
	/usr/bin/chflags -R nouchg /Users/$currentuser/
	sleep 5
	/usr/sbin/chown -R "$currentuser":"staff" /Users/$currentuser/
	/bin/ls -alnd /Users/$currentuser/
fi
#
/bin/echo "end function ChangeUIDandGID"
}
### End Change UID and GID ###
#

#
### Begin Cleanup ###
function CleanupStuff () {
/bin/echo "begin function CleanupStuff"
# Clear the password variables to cleanup.
PASSWORD=""
# Clear the list of deleted user accounts
/bin/rm -f /Library/Preferences/com.apple.preferences.accounts.plist
# Clear apps to relaunch at login - Otherwise Self Service opens when the user logs back in.
## Get the Mac's UUID string
UUID=$(ioreg -rd1 -c IOPlatformExpertDevice | awk -F'"' '/IOPlatformUUID/{print $4}')
## Delete the plist array
/usr/libexec/PlistBuddy -c 'Delete :TALAppsToRelaunchAtLogin' /Users/${currentuser}/Library/Preferences/ByHost/com.apple.loginwindow.${UUID}.plist
/bin/echo "end function CleanupStuff"
}
### End Cleanup ###
#

#
### Begin Reboot Mac using jamf command ###
function JamfReboot () {
/bin/echo "begin function JamfReboot"
jamf manage
jamf recon
jamf fixByHostFiles 
jamf flushCaches -flushSystem -flushUsers
jamf reboot -minutes 1 -background
/bin/echo "end function JamfReboot"
}
### End Mac using jamf command ###
#

####################################################################################################
#
# SCRIPT CONTENTS
#
####################################################################################################
rootcheck
OSXVersioncheck
ADMobileAccountcheck
MessageToUser
#pmsetPowerStatus
if [ "$AskForUserPassword" = "yes" ]; then  
	UserPassword
fi
jamfHelperCurtain
ConvertToLocalAccount
if [ "$ChangeUID" = "yes" ]; then   
	ChangeUIDandGID
fi
CleanupStuff
JamfReboot
#
exit 0
