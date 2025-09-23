#!/bin/bash
################################################################################
# Script Name:       demobilizeADMobileAccounts_v5.sh
# Author:            Tony Young
# Organization:      Cloud Lake Technology (an Akima company)
# Date:              2025-08-05
# Version:           5.0
#
# Purpose:
#   Automate conversion of AD mobile accounts to local accounts without prompts,
#   preserve AD binding, never grant admin rights, log out users,
#   sanitize SecureToken and account policies, and reset passwords via Jamf Pro.
#   Used in environments that take advantage of smartcards and PINs where users 
#   don't remember their keychain/cached passwords for mobile accounts. 
################################################################################

set -euo pipefail
# Uncomment for debug:
# set -x

# Jamf Pro script parameters
ADMIN_USER="administrator" # Or update for your local admin
ADMIN_PASS="$4"   # Jamf parameter 4: admin password
NEW_PASS="$5"     # Jamf parameter 5: new user password

# Build user list ending with FINISHED
listUsers="$(/usr/bin/dscl . list /Users UniqueID | awk '$2 > 1000 {print $1}') FINISHED"
Version="5.0"
FullScriptName=$(basename "$0")
ShowVersion="$FullScriptName $Version"
check4AD=$(/usr/bin/dscl localhost -list . | grep "Active Directory")

# Save IFS and parse OS version
OLDIFS=$IFS
IFS='.' read osvers_major osvers_minor osvers_dot_version <<< "$(/usr/bin/sw_vers -productVersion)"
IFS=$OLDIFS

/bin/echo "********* Running $ShowVersion *********"

RunAsRoot(){
    if [[ "$EUID" -ne 0 ]]; then
        echo
        echo "*** Please run as root. Authenticating... ***"
        echo
        sudo "$1" && exit 0
    fi
}

PasswordMigration(){
    AuthenticationAuthority=$(/usr/bin/dscl -plist . -read /Users/$netname AuthenticationAuthority)
    Kerberosv5=$(echo "${AuthenticationAuthority}" | xmllint --xpath 'string(//string[contains(text(),"Kerberosv5")])' -)
    LocalCachedUser=$(echo "${AuthenticationAuthority}" | xmllint --xpath 'string(//string[contains(text(),"LocalCachedUser")])' -)
    if [[ -n "${Kerberosv5}" ]]; then
        /usr/bin/dscl -plist . -delete /Users/$netname AuthenticationAuthority "${Kerberosv5}"
    fi
    if [[ -n "${LocalCachedUser}" ]]; then
        /usr/bin/dscl -plist . -delete /Users/$netname AuthenticationAuthority "${LocalCachedUser}"
    fi
}

RunAsRoot "$0"

# Report AD binding status (do not unbind)
if [[ "${check4AD}" = "Active Directory" ]]; then
    /bin/echo "Active Directory binding is still active."
fi

for netname in $listUsers; do
    if [[ "$netname" = "FINISHED" ]]; then
        break
    fi

    # If user is logged in, log them out
    if /usr/bin/pgrep -u "$netname" &>/dev/null; then
        /bin/echo "Logging out $netname"
        /bin/launchctl bootout gui/"$(id -u "$netname")" || /usr/bin/pkill -KILL -u "$netname"
    fi

    # Detect any mobile-cached account
    authInfo=$(/usr/bin/dscl . -read /Users/"$netname" AuthenticationAuthority 2>/dev/null)
    if [[ "$authInfo" == *LocalCachedUser* ]]; then
        printf "%s is a mobile-cached account; converting to local account.\n" "$netname"
    else
        printf "%s is not a mobile-cached account; skipping.\n" "$netname"
        continue
    fi

    # Remove AD mobile attributes
    /usr/bin/dscl . -delete /Users/$netname cached_groups
    /usr/bin/dscl . -delete /Users/$netname cached_auth_policy
    /usr/bin/dscl . -delete /Users/$netname CopyTimestamp
    /usr/bin/dscl . -delete /Users/$netname AltSecurityIdentities
    /usr/bin/dscl . -delete /Users/$netname SMBPrimaryGroupSID
    /usr/bin/dscl . -delete /Users/$netname OriginalAuthenticationAuthority
    /usr/bin/dscl . -delete /Users/$netname OriginalNodeName
    /usr/bin/dscl . -delete /Users/$netname SMBSID
    /usr/bin/dscl . -delete /Users/$netname SMBScriptPath
    /usr/bin/dscl . -delete /Users/$netname SMBPasswordLastSet
    /usr/bin/dscl . -delete /Users/$netname SMBGroupRID
    /usr/bin/dscl . -delete /Users/$netname PrimaryNTDomain
    /usr/bin/dscl . -delete /Users/$netname AppleMetaRecordName
    /usr/bin/dscl . -delete /Users/$netname MCXSettings
    /usr/bin/dscl . -delete /Users/$netname MCXFlags

    # Migrate password attributes
    PasswordMigration

    # Restart Directory Services
    if [[ $osvers_major -eq 10 && $osvers_minor -lt 7 ]]; then
        /usr/bin/killall DirectoryService
    else
        /usr/bin/killall opendirectoryd
    fi

    sleep 20

    # Verify conversion
    accounttype=$(/usr/bin/dscl . -read /Users/"$netname" AuthenticationAuthority | head -2 | awk -F'/' '{print $2}' | tr -d '\n')
    if [[ "$accounttype" = "Active Directory" ]]; then
        printf "Conversion failed. %s remains an AD mobile account.\n" "$netname"
        continue
    else
        printf "Conversion successful. %s is now local.\n" "$netname"
    fi

    # Update home directory permissions
    homedir=$(/usr/bin/dscl . -read /Users/"$netname" NFSHomeDirectory | awk '{print $2}')
    if [[ -d "$homedir" ]]; then
        /bin/echo "Updating ownership on $homedir"
        /usr/sbin/chown -R "$netname" "$homedir"

        ############################################################################
        # Sanitize SecureToken + accountPolicyData / clear pw policies / secure token reissue / force new pw
        ############################################################################

        # 1) Remove SecureToken entitlement (if present)
        /usr/bin/fdesetup remove -user "$netname" \
          && /bin/echo "Removed SecureToken from $netname" \
          || /bin/echo "No SecureToken for $netname or removal failed"

        # 2) Strip lingering SecureToken marker from AuthenticationAuthority
        /usr/bin/dscl . -delete "/Users/$netname" AuthenticationAuthority ";SecureToken;" 2>/dev/null || true

        # 3) Delete existing accountPolicyData
        /usr/bin/dscl . -delete "/Users/$netname" dsAttrTypeNative:accountPolicyData 2>/dev/null || true

        # 4) Clear all account policies
        /usr/bin/pwpolicy -clearaccountpolicies

        # 5) Clear the user’s password
        /usr/bin/dscl . -passwd "/Users/$netname" "" \
          && /bin/echo "Cleared password for $netname" \
          || /bin/echo "Failed to clear password for $netname"

        # 6) (Optional) Re-enable SecureToken using admin credentials
        /usr/sbin/sysadminctl -secureTokenOn "$netname" -password "" -adminUser "$ADMIN_USER" -adminPassword "$ADMIN_PASS" \
          && /bin/echo "Granted SecureToken to $netname" \
          || /bin/echo "Failed to grant SecureToken to $netname"

        # 7) Require new password at next login
        /usr/bin/pwpolicy -u "$netname" -setpolicy "newPasswordRequired=1" \
          && /bin/echo "Set newPasswordRequired for $netname" \
          || /bin/echo "Failed to set newPasswordRequired for $netname"
    fi

    # Add to staff group
    /usr/sbin/dseditgroup -o edit -a "$netname" -t user staff

    # Display account info
    /usr/bin/id "$netname"

    # Reset password using sysadminctl
    /bin/echo "Resetting password for $netname"
    /usr/sbin/sysadminctl \
        -adminUser "$ADMIN_USER" \
        -adminPassword "$ADMIN_PASS" \
        -resetPasswordFor "$netname" \
        -newPassword "$NEW_PASS" || /bin/echo "WARNING: Failed to reset password for $netname"

    /bin/echo "--------------------------------------------------------"
done

/bin/echo "Finished converting users to local accounts"
