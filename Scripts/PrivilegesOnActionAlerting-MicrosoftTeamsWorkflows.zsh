#!/bin/zsh

###################################################################################################
# Script Name:   PrivilegesOnActionAlerting-MicrosoftTeamsWorkflows.zsh
# By:            Tony Young
# Organization:  Cloud Lake Technology, an Akima company
# Date:          December 1st, 2025
# 
# Purpose:       Sends a web hook alert to Microsoft Teams upon privileged escalation on macOS
#
###################################################################################################
#
# DESCRIPTION
#
#   This script has been source from Andrew Doering --- https://andrewdoering.org/blog/2025/macos-privileges/
#   Additional inspiration has been taken from Dan Snelson's Setup Your Mac v.1.16 for deploying to Teams Workflows Webhook --- https://github.com/setup-your-mac/Setup-Your-Mac/tree/1.16.0
#   Both have been combined and edited by Tony Young to allow for alerting to be sent to Microsoft Teams via the Teams Workflow Webhooks feature powered by Power Automate.
#
###################################################################################################
#
# CHANGELOG
#
#   2025-12-01 - Tony Young
#       - v1.1 Fixed Demotion Scripting for Unified Logging. Minor enhancements elsewhere
#   2025-02-12 - Tony Young
#       - v1.0 Initial script creation
#
###################################################################################################
#
# DISCLAIMER
#
#   This script is provided "AS IS" and without warranty of any kind. The author and organization 
#   make no warranties, express or implied, that this script is free of error, or is consistent 
#   with any particular standard of merchantability, or that it will meet your requirements for 
#   any particular application. It should not be relied on for solving a problem whose incorrect 
#   solution could result in injury to person or property. If you do use it in such a manner, 
#   it is at your own risk. The author and organization disclaim all liability for direct, indirect, 
#   or consequential damages resulting from your use of this script.
#
###################################################################################################

# Teams Webhook URL
# You'll need to set up a Teams webhook to receive the information being sent by the script. 
# Once a Teams webhook is available, the teams_webhook variable should look similar
# to this:
# teams_webhook="https://companyname.webhook.office.com/webhookb2/7ce853bd-a9e1-462f-ae32-d3d35ed5295d@7c155bae-5207-4bb5-8b58-c43228bc1bb7/IncomingWebhook/8155d8581864479287b68b93f89556ae/651e63f8-2d96-42ab-bb51-65cb05fc62aa&quot;

webhookURL=" "
  if [[ -z "$webhookURL" || "$webhookURL" == " " ]]; then
      /bin/echo "ERROR: webhookURL not configured. Exiting."
      exit 1
  fi

# Get system information
currentUser=$(/usr/sbin/scutil <<< "show State:/Users/ConsoleUser" | /usr/bin/awk '/Name :/ { print $3 }')
loggedInUserFullname=$( id -F "${currentUser}" )
hostname=$(/bin/hostname)
timestamp=$(/bin/date +"%Y-%m-%d %H:%M:%S")
# Update futureTime based upon your ExpirationInterval key
futureTime=$(/bin/date -v+10M -v+56S +"%Y-%m-%d %H:%M:%S")
serialNumber=$(/usr/sbin/ioreg -l | /usr/bin/awk -F'"' '/IOPlatformSerialNumber/ {print $4}')
logfile="/private/tmp/user-initiated-privileges-change.tmp"
passedPromotionReason="$3"

# Check if the user is currently an admin
adminUsers=$(/usr/bin/dscl . -read /Groups/admin GroupMembership 2>/dev/null | /usr/bin/awk '{$1=""; print $0}' | /usr/bin/tr -s ' ')
if echo "$adminUsers" | /usr/bin/grep -qw "$currentUser"; then
    previousStatus="Administrator"
    userWasAdmin=true
else
    previousStatus="Standard User"
    userWasAdmin=false
fi

# Wait for user promotion (up to 5 seconds)
wait_time=0
while ! $userWasAdmin && (( wait_time < 5 )); do
    /bin/echo "Waiting for admin privileges... ($wait_time sec)"
    /bin/sleep 1
    ((wait_time++))
    
# Recheck admin status
adminUsers=$(/usr/bin/dscl . -read /Groups/admin GroupMembership 2>/dev/null | /usr/bin/awk '{$1=""; print $0}' |
  /usr/bin/tr -s ' ')
      if echo "$adminUsers" | /usr/bin/grep -qw "$currentUser"; then
          userWasAdmin=true
      fi
done

# Determine new status
privilegeStatus=$([[ $userWasAdmin == true ]] && /bin/echo "Administrator" || /bin/echo "Standard User")
/bin/echo "$privilegeStatus"

# Capture the reason for promotion
if [[ "$privilegeStatus" == "Administrator" ]]; then
    promotionReason="$passedPromotionReason"
    if [[ -z "$promotionReason" ]]; then
        /bin/sleep 5
        logOutput=$(/usr/bin/log show --style syslog --predicate 'process == "PrivilegesDaemon" && eventMessage CONTAINS "SAPCorp"' --info --last 5m 2>/dev/null)
        promotionReason=$(echo "$logOutput" | /usr/bin/grep -oE 'User .* now has administrator privileges for the following reason: ".*"' | /usr/bin/tail -n1 | /usr/bin/sed -E 's/.*for the following reason: "(.*)"/\1/' | /usr/bin/tr -d '\n')
        if [[ -z "$promotionReason" ]]; then
            promotionReason="Failed to obtain reason."
        fi
    fi
else
    promotionReason="User was demoted to standard user automatically."
fi

# Capture installation logs for demotion
installLogEntries="N/A"
  if [[ "$privilegeStatus" == "Standard User" ]]; then
      # Use unified logging system instead of deprecated install.log
      installLogEntries=$(/usr/bin/log show --predicate 'process == "installd" OR process CONTAINS "install"' \
          --style syslog --last 20m --info 2>/dev/null | \
          /usr/bin/grep -E '(Install|Package|installd):' | \
          /usr/bin/tail -n 50)

      # Fallback to install.log if it exists 
       if [[ -z "$installLogEntries" && -f /var/log/install.log ]]; then
          # Use grep first to filter text lines, then process with awk to avoid binary data
          installLogEntries=$(/usr/bin/grep -aE 'Installer\[|installd\[' /var/log/install.log 2>/dev/null | \
              /usr/bin/tail -n 1000 | \
              /usr/bin/awk -v d="$(/bin/date -v-20M +"%Y-%m-%d %H:%M:%S")" '$0 > d' 2>/dev/null | \
              /usr/bin/tail -n 50)
      fi
  fi

# Sanitize LogMessage
sanitizedReason="${promotionReason//[^[:print:]]/}"
sanitizedInstallLog="${installLogEntries//[^[:print:]]/}"

# Construct log message
logMessage="User $currentUser changed privilege status at $timestamp on $hostname. Expected removal at $futureTime. Status: $privilegeStatus. Reason: $sanitizedReason"
[[ "$privilegeStatus" == "Standard User" ]] && logMessage+="\n\nInstall Log:\n\n$sanitizedInstallLog"

/bin/echo "$logMessage" | /usr/bin/tee "$logfile"
teamsMessage=$(printf '%s' "$logMessage" | /usr/bin/sed 's/\\/\\\\/g; s/"/\\"/g; s/$/\\n/' | /usr/bin/tr -d '\n')

# Prepare Teams Webhook
 webHookdata=$(cat <<EOF
        {
            "type": "message",
            "attachments": [
                {
                    "contentType": "application/vnd.microsoft.card.adaptive",
                    "contentUrl": null,
                    "content": {
                        "type": "AdaptiveCard",
                        "body": [
                            {
                                "type": "TextBlock",
                                "size": "Large",
                                "weight": "Bolder",
                                "text": "Privileges Activity Log"
                            },
                            {
                                "type": "ColumnSet",
                                "columns": [
                                    {
                                        "type": "Column",
                                        "items": [
                                            {
                                                "type": "Image",
                                                "url": "https://ics.services.jamfcloud.com/icon/hash_d75d2250498be4cdfc75956d88dc7204dabf886a51396d0e99dbd75759e151ed",
                                                "altText": "SYM",
                                                "size": "Small"
                                            }
                                        ],
                                        "width": "auto"
                                    },
                                    {
                                        "type": "Column",
                                        "items": [
                                            {
                                                "type": "TextBlock",
                                                "weight": "Bolder",
                                                "text": "$( scutil --get ComputerName )",
                                                "wrap": true
                                            },
                                            {
                                                "type": "TextBlock",
                                                "spacing": "None",
                                                "text": "${serialNumber}",
                                                "isSubtle": true,
                                                "wrap": true
                                            }
                                        ],
                                        "width": "stretch"
                                    }
                                ]
                            },
                            {
                                "type": "FactSet",
                                "facts": [
                                    {
                                        "title": "Timestamp",
                                        "value": "${timestamp}"
                                    },
                                    {
                                        "title": "Logged In User",
                                        "value": "${loggedInUserFullname}"
                                    },
                                    {
                                        "title": "Account Username",
                                        "value": "${currentUser}"
                                    },
                                    {
                                        "title": "Message",
                                        "value": "${teamsMessage}"
                                    }
                                ]
                            }
                        ],
                        "$schema": "http://adaptivecards.io/schemas/adaptive-card.json",
                        "version": "1.2"
                    }
                }
            ]
        }
EOF
)

    # Send the message to Microsoft Teams
    /bin/echo "Sending message to Microsoft Teams..."

  webhookResult=$(/usr/bin/curl --request POST \
      --url "${webhookURL}" \
      --header 'Content-Type: application/json' \
      --data "${webHookdata}" \
      --write-out "%{http_code}" \
      --silent \
      --output /dev/null)

  /bin/echo "Microsoft Teams Webhook HTTP Response: ${webhookResult}"

  exit 0


