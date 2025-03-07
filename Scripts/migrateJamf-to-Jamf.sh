#!/bin/bash

###################################################################################################
# Script Name:    migrateJamf-to-Jamf.sh
# By:            Tony Young
# Organization:   Cloud Lake Technology, an Akima company
# Date:          March 7th, 2025
#
###################################################################################################
#
#                                                                                                       
#                                  Jamf-to-Jamf Migration Script                                        
#                                                                                                       
# This script facilitates migration from one Jamf Pro Server to another. It unenrolls the device from   
# the current Jamf Pro instance and re-enrolls it in the new Jamf Pro instance using an enrollment URL. 
#                                                                                                       
###################################################################################################
#
# CHANGELOG
#
#   2025-03-07 - Tony Young
#       - Initial script creation
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


# Define old and new Jamf Pro URLs
OLD_JAMF_PRO_URL="https://old-jamf-instance.com"
NEW_JAMF_PRO_URL="https://new-jamf-instance.com"
NEW_ENROLLMENT_URL="https://new-jamf-instance.com/enroll"

LOG="/Library/Logs/JamfMigration.log"
USERNAME="migration_account"
PASSWORD="migration_account_password"
JAMF_API_VERSION="new"

echo "Starting Jamf Pro migration process..." | tee -a "$LOG"

# Function to check if the device is managed by Jamf
check_if_managed() {
  if profiles -P | grep -q "com.jamfsoftware"; then
    echo "Device is managed by Jamf." | tee -a "$LOG"
  else
    echo "Device is not managed by Jamf. Exiting script." | tee -a "$LOG"
    exit 0
  fi
}

# Function to get authentication token from Jamf Pro
get_auth_token() {
  auth_token=$(curl -su "$USERNAME:$PASSWORD" -X POST "$OLD_JAMF_PRO_URL/api/v1/auth/token" | jq -r '.token')
  echo "$auth_token"
}

# Function to get the computer ID from Jamf Pro based on serial number
get_computer_id() {
  local serial_number="$1"
  local auth_token="$2"
  
  computer_id=$(curl -s -X GET \
    -H "Authorization: Bearer $auth_token" \
    "$OLD_JAMF_PRO_URL/api/v1/computers-inventory?filter=hardware.serialNumber==$serial_number" | jq -r '.results[0].id')
  echo "$computer_id"
}

# Function to unmanage a device from Jamf Pro using the new API
unmanage_device_jamf_new() {
  local computer_id="$1"
  local auth_token="$2"

  response=$(curl -s -X POST \
    -H "Authorization: Bearer $auth_token" \
    "$OLD_JAMF_PRO_URL/api/v1/computer-inventory/$computer_id/remove-mdm-profile")

  if echo "$response" | jq -e '.commandUuid' >/dev/null; then
    echo "Device successfully unmanaged. Command UUID: $(echo "$response" | jq -r '.commandUuid')" | tee -a "$LOG"
  else
    echo "Failed to unmanage device: $response" | tee -a "$LOG"
    exit 1
  fi
}

# Function to unmanage a device from Jamf Pro using the classic API
unmanage_device_jamf_classic() {
  local computer_id="$1"
  local auth_token="$2"

  response=$(curl -s -X POST \
    -H "Authorization: Bearer $auth_token" \
    "$OLD_JAMF_PRO_URL/JSSResource/computercommands/command/UnmanageDevice/id/$computer_id")

  command_uuid=$(echo "$response" | xmllint --xpath 'string(//command_uuid)' - 2>/dev/null)

  if [[ -n "$command_uuid" ]]; then
    echo "Device successfully unmanaged. Command UUID: $command_uuid" | tee -a "$LOG"
  else
    echo "Failed to unmanage device: $response" | tee -a "$LOG"
    exit 1
  fi
}

# Function to re-enroll into the new Jamf Pro server
reenroll_to_new_jamf() {
  echo "Re-enrolling into new Jamf Pro server..." | tee -a "$LOG"
  sudo profiles renew -type enrollment -url "$NEW_ENROLLMENT_URL"
}

# Execute the migration steps
check_if_managed

# Retrieve the serial number of the Mac
serial_number=$(system_profiler SPHardwareDataType | awk '/Serial Number/ {print $4}')
echo "Serial Number: $serial_number" | tee -a "$LOG"

# Authenticate with the old Jamf Pro server
auth_token=$(get_auth_token)

# Get the computer ID for the device from Jamf Pro
computer_id=$(get_computer_id "$serial_number" "$auth_token")
echo "Computer ID: $computer_id" | tee -a "$LOG"

# If computer ID is found, proceed with unmanagement
if [ -n "$computer_id" ]; then
  case $JAMF_API_VERSION in
    classic)
      unmanage_device_jamf_classic "$computer_id" "$auth_token"
      ;;
    new)
      unmanage_device_jamf_new "$computer_id" "$auth_token"
      ;;
    *)
      echo "Error: Invalid JAMF_API_VERSION specified. Must be 'classic' or 'new'" | tee -a "$LOG"
      exit 1
      ;;
  esac
else
  echo "Computer ID not found for Serial Number: $serial_number" | tee -a "$LOG"
  exit 1
fi

# Re-enroll the device in the new Jamf Pro server
reenroll_to_new_jamf

# Verify that the re-enrollment was successful
if profiles -P | grep -q "com.jamfsoftware"; then
  echo "Device successfully re-enrolled in new Jamf Pro server." | tee -a "$LOG"
else
  echo "Re-enrollment failed. Please check logs and retry manually." | tee -a "$LOG"
  exit 1
fi

exit 0
