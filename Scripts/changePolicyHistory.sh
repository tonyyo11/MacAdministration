#!/bin/bash
###################################################################################################
# Script Name:   changePolicyHistory.sh
# By:            Tony Young
# Organization:  Cloud Lake Technology, an Akima company
# Date:          April 7th, 2025
# 
# Purpose:       Write a Change Management Policy ID/Code to a specified log file for recording into 
#				         a Jamf Pro Extension Attribute.
#
###################################################################################################
# Define the directory and log file path
CHANGE_POLICY="$4"                        # Change Policy ID such as ITCH-1234
ORG_NAME="$5"                             # Organizational name or abbreviation such as ACME
DIR="/Library/Management/$ORG_NAME"
FILE="$DIR/CPHistory.log"

# Create the directory if it doesn't exist
if [ ! -d "$DIR" ]; then
    mkdir -p "$DIR"
fi

# Check if the log file exists; if not, create it, otherwise append the Change Policy ID as a new line
if [ ! -f "$FILE" ]; then
    echo "$CHANGE_POLICY" > "$FILE"
else
    echo "$CHANGE_POLICY" >> "$FILE"
fi
