#!/bin/bash

# Script to update the local administrator password on macOS devices managed by Jamf Pro.
# This Script is meant to be run on non-LAPS enabled accounts.
# Tony Young - North Edge Technology - An Akima Company

# Set variables
ADMIN_USERNAME="administrator"
OLD_PASSWORD="$4" # Use Jamf Script Parameter 4 for the old password
NEW_PASSWORD="$5" # Use Jamf Script Parameter 5 for the new password

# Log file path
LOG_FILE="/var/log/password_update.log"

# Function to log messages
log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

# Function to change password
change_password() {
    local output
    output=$(dscl . -passwd /Users/$ADMIN_USERNAME "$OLD_PASSWORD" "$NEW_PASSWORD" 2>&1)
    local exit_code=$?
    echo "$output"
    return $exit_code
}

# Start logging
log_message "Starting password update script"

# Check if the script is running with root privileges
if [ "$(id -u)" != "0" ]; then
    log_message "Error: This script must be run as root"
    exit 1
fi
log_message "Root privilege check passed"

# Check if both password parameters are provided
if [ -z "$OLD_PASSWORD" ]; then
    log_message "Error: Old password not provided (Parameter 4 is empty)"
    exit 1
fi
if [ -z "$NEW_PASSWORD" ]; then
    log_message "Error: New password not provided (Parameter 5 is empty)"
    exit 1
fi
log_message "Password parameters check passed"

# Check if the administrator account exists
if ! dscl . -read /Users/$ADMIN_USERNAME &>/dev/null; then
    log_message "Error: The account $ADMIN_USERNAME does not exist"
    exit 1
fi
log_message "Administrator account existence check passed"

# Attempt to update the password
log_message "Attempting to update password"
password_change_output=$(change_password)
password_change_exit_code=$?

if [ $password_change_exit_code -eq 0 ]; then
    log_message "Password updated successfully for $ADMIN_USERNAME"
else
    log_message "Error: Failed to update password for $ADMIN_USERNAME"
    log_message "dscl output: $password_change_output"
    log_message "dscl exit code: $password_change_exit_code"
    exit 1
fi

# Verify the password change
log_message "Attempting to verify password change"
if dscl . -authonly $ADMIN_USERNAME "$NEW_PASSWORD"; then
    log_message "Password verification successful"
else
    log_message "Error: Password verification failed"
    log_message "dscl authonly exit code: $?"
    exit 1
fi

# End logging
log_message "Password update script completed successfully"

exit 0
