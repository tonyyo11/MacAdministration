#!/bin/bash
################################################################################
# Script: upload_super_log_to_jamf.sh
# Purpose: Compress super log directories and upload the ZIP file to the
#          computer record in Jamf Pro using OAuth client credentials flow.
#          Optionally sends a Microsoft Teams webhook notification.
#
# Process Flow:
#   1. Compress super log directories
#   2. Authenticate to Jamf Pro API using OAuth
#   3. Retrieve computer ID from Jamf Pro by serial number
#   4. Upload compressed logs to computer record
#   5. Clean up temporary files and invalidate token
#   6. Send Teams notification (if webhook URL is configured)
################################################################################


# --- CONFIGURATION SECTION ---
# Directory paths for super logs
LOG_DIR="/Library/Management/super/logs"
ARCHIVE_DIR="/Library/Management/super/logs-archive"

# Jamf Pro API configuration (OAuth client credentials)
JAMF_URL=""
JAMF_CLIENT_ID=""
JAMF_CLIENT_SECRET=""

# Microsoft Teams Webhook URL (optional - leave empty to skip notification)
webhookURL=""


# --- FILE NAMING & SYSTEM INFO ---
# Get the computer name as set in System Preferences
COMP_NAME=$(scutil --get ComputerName)

# Create timestamp for unique file naming (format: YYYYMMDD_HHMMSS)
DATE_TIME=$(date "+%Y%m%d_%H%M%S")

# Define temporary ZIP file location with computer name and timestamp
ZIP_FILE="/tmp/${COMP_NAME}_${DATE_TIME}.zip"

# Get the hardware serial number from IORegistry
SERIAL_NUMBER=$(/usr/sbin/ioreg -l | /usr/bin/awk -F'"' '/IOPlatformSerialNumber/ {print $4}')

# Create human-readable date for webhook notification (format: "January 15, 2025 3:45 PM")
HUMAN_READABLE_DATE=$(date -j -f "%Y%m%d_%H%M%S" "$DATE_TIME" "+%B %d, %Y %-I:%M %p")

# --- COMPRESS THE FOLDERS ---
# Verify at least one log directory exists before attempting compression
if [ -d "$LOG_DIR" ] || [ -d "$ARCHIVE_DIR" ]; then
    echo "Compressing the following directories into $ZIP_FILE:"

    # Display which directories will be included in the archive
    [ -d "$LOG_DIR" ] && echo "  - $LOG_DIR" || echo "Warning: Directory $LOG_DIR does not exist."
    [ -d "$ARCHIVE_DIR" ] && echo "  - $ARCHIVE_DIR" || echo "Warning: Directory $ARCHIVE_DIR does not exist."

    # Create ZIP archive recursively including both directories
    /usr/bin/zip -r "$ZIP_FILE" "$LOG_DIR" "$ARCHIVE_DIR"
    if [ $? -ne 0 ]; then
        echo "Error: Compression failed."
        exit 1
    fi
else
    # Exit if neither directory exists - nothing to upload
    echo "Error: Neither $LOG_DIR nor $ARCHIVE_DIR exist."
    exit 1
fi

# --- TOKEN FUNCTIONS PER JAMF'S EXAMPLE ---

# Function: getAccessToken
# Purpose: Request a new OAuth access token from Jamf Pro API
# Sets: access_token, token_expires_in, token_expiration_epoch
getAccessToken() {
    # Capture current time as epoch for calculating token expiration
    current_epoch=$(date +%s)

    # Make OAuth token request using client credentials grant type
    response=$(curl --silent --location --request POST "${JAMF_URL}/api/oauth/token" \
        --header "Content-Type: application/x-www-form-urlencoded" \
        --data-urlencode "client_id=${JAMF_CLIENT_ID}" \
        --data-urlencode "grant_type=client_credentials" \
        --data-urlencode "client_secret=${JAMF_CLIENT_SECRET}")

    # Extract access token and expiration time from JSON response using plutil
    access_token=$(echo "$response" | plutil -extract access_token raw -)
    token_expires_in=$(echo "$response" | plutil -extract expires_in raw -)

    # Calculate absolute expiration time (subtract 1 second for safety margin)
    token_expiration_epoch=$(($current_epoch + $token_expires_in - 1))
}

# Function: checkTokenExpiration
# Purpose: Verify if current token is still valid, request new one if expired
checkTokenExpiration() {
    current_epoch=$(date +%s)

    # Compare token expiration time with current time
    if [[ $token_expiration_epoch -ge $current_epoch ]]; then
        echo "Token valid until epoch time: $token_expiration_epoch"
    else
        echo "No valid token available, getting new token"
        getAccessToken
    fi
}

# Function: invalidateToken
# Purpose: Explicitly invalidate the OAuth token after use (security best practice)
invalidateToken() {
    # Send token invalidation request to Jamf Pro API
    responseCode=$(curl -w "%{http_code}" -H "Authorization: Bearer ${access_token}" \
        "${JAMF_URL}/api/v1/auth/invalidate-token" -X POST -s -o /dev/null)

    # Process response codes
    if [[ ${responseCode} == 204 ]]; then
        echo "Token successfully invalidated"
        access_token=""
        token_expiration_epoch="0"
    elif [[ ${responseCode} == 401 ]]; then
        echo "Token already invalid"
    else
        echo "An unknown error occurred invalidating the token"
    fi
}

# --- OBTAIN AND VALIDATE THE API TOKEN ---
# Initial token check - will request a new token if none exists
checkTokenExpiration

# Verify the token works by calling a test endpoint
echo "Testing API token with Jamf Pro version endpoint..."
curl -X GET -H "accept: application/json" -H "Authorization: Bearer $access_token" "${JAMF_URL}/api/v1/jamf-pro-version"
echo ""

# Re-check token expiration in case significant time has passed
checkTokenExpiration

# --- RETRIEVE COMPUTER RECORD ID FROM JAMF PRO ---
# Query system_profiler to get the hardware serial number
SERIAL=$(system_profiler SPHardwareDataType | awk '/Serial Number/ {print $4}')
if [ -z "$SERIAL" ]; then
    echo "Error: Could not determine the computer serial number."
    exit 1
fi
echo "Computer Serial: $SERIAL"

# Query Jamf Pro Classic API to get computer record by serial number
# Returns XML containing computer information including the internal Jamf ID
COMPUTER_XML=$(curl -X GET -H "accept: application/xml" -H "Authorization: Bearer $access_token" \
    "${JAMF_URL}/JSSResource/computers/serialnumber/${SERIAL}")

# Extract the computer ID from XML response using xmllint XPath query
COMPUTER_ID=$(echo "$COMPUTER_XML" | xmllint --xpath '//computer/general/id/text()' - 2>/dev/null)

# Brief pause to ensure API processes the request
sleep 2

# Verify we successfully retrieved a computer ID
if [ -z "$COMPUTER_ID" ]; then
    echo "Error: Could not retrieve computer ID from Jamf Pro."
    exit 1
fi
echo "Computer ID: $COMPUTER_ID"

# --- UPLOAD THE FILE TO THE COMPUTER RECORD ---
# Extract just the filename from the full path for logging
FILE_NAME=$(basename "$ZIP_FILE")
echo "Uploading $ZIP_FILE (filename: $FILE_NAME) to Jamf Pro computer record (ID: $COMPUTER_ID)..."

# Upload the ZIP file as an attachment to the computer record
# Using Classic API endpoint for file uploads with multipart/form-data
UPLOAD_RESPONSE=$(curl -k -X POST \
    -F "name=@${ZIP_FILE}" \
    -H "accept: application/xml" \
    -H "Authorization: Bearer $access_token" \
    "${JAMF_URL}/JSSResource/fileuploads/computers/id/${COMPUTER_ID}")

# Check if upload was successful by looking for "success" in response or exit code
if [[ "$UPLOAD_RESPONSE" == *"success"* ]] || [ $? -eq 0 ]; then
    echo "File uploaded successfully."
else
    echo "File upload failed. Response: $UPLOAD_RESPONSE"
fi

# Clean up: remove the temporary ZIP file from /tmp
rm "$ZIP_FILE"

# --- INVALIDATE THE API TOKEN ---
# Security best practice: invalidate the token immediately after use
invalidateToken

# Verify token is no longer valid (this call should fail with 401)
echo "Testing API token after invalidation (should fail)..."
curl -X GET -H "Authorization: Bearer $access_token" "${JAMF_URL}/api/v1/jamf-pro-version" -X GET
echo ""

# --- SEND TEAMS WEBHOOK ALERT ---
# If webhook URL is not configured, exit cleanly after successful upload
if [ -z "$webhookURL" ]; then
    echo "No Teams webhook URL configured. Skipping notification."
    exit 0
fi

# Webhook URL is configured, proceed with Teams notification
# Build the Microsoft Teams Adaptive Card JSON payload
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
                                "text": "Super Log Upload Activity"
                            },
                            {
                                "type": "ColumnSet",
                                "columns": [
                                    {
                                        "type": "Column",
                                        "items": [
                                            {
                                                "type": "Image",
                                                "url": "https://cdn-icons-png.flaticon.com/128/8422/8422186.png",
                                                "altText": "Log Upload",
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
                                                "text": "${COMP_NAME}",
                                                "wrap": true
                                            },
                                            {
                                                "type": "TextBlock",
                                                "spacing": "None",
                                                "text": "${SERIAL_NUMBER}",
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
                                        "value": "${HUMAN_READABLE_DATE}"
                                    },
                                    {
                                        "title": "File Name",
                                        "value": "${ZIP_FILE}"
                                    },
                                    {
                                        "title": "Activity",
                                        "value": "This system has uploaded archival logging to Jamf Pro. Please retrieve the logs and download them locally prior to deleting the attachment from the computer record."
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

# Send the adaptive card notification to Microsoft Teams
echo "Sending message to Microsoft Teams..."
echo "${webHookdata}"

# POST the JSON payload to the Teams webhook endpoint
curl --request POST --url "${webhookURL}" --header 'Content-Type: application/json' --data "${webHookdata}"

# Script completed successfully
exit 0
