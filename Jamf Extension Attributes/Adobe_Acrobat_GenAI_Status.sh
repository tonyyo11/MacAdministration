#!/bin/bash
# This script returns the Adobe Reader and Acrobat Pro Generative AI PLIST Settings
# Make sure to set the Extension Attribute Data Type to "String".
# by Tony Young | Akima / Cloud Lake Technology
# 2024/09/10
# Updated to include Acrobat Pro check, remove extra spaces, and output in a single echo

# Path to the local property list files:
READER_LOCAL_PLIST="/Library/Preferences/com.adobe.Reader" # No trailing ".plist"
ACROBAT_LOCAL_PLIST="/Library/Preferences/com.adobe.Acrobat.Pro" # No trailing ".plist"

# Initialize variables
reader_Gentech=""
acrobat_Gentech=""

# Function to clean up the output
clean_output() {
    echo "$1" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' -e 's/[[:space:]]*=[[:space:]]*/=/'
}

# Check for Adobe Reader preferences and read Generative AI settings
if [[ -f "$READER_LOCAL_PLIST.plist" ]]; then
    reader_raw=$(defaults read "${READER_LOCAL_PLIST}" | grep bEnableGentech 2> /dev/null)
    if [[ -n "$reader_raw" ]]; then
        reader_Gentech=$(clean_output "$reader_raw")
    fi
fi

# Check for Adobe Acrobat Pro preferences and read Generative AI settings
if [[ -f "$ACROBAT_LOCAL_PLIST.plist" ]]; then
    acrobat_raw=$(defaults read "${ACROBAT_LOCAL_PLIST}" | grep bEnableGentech 2> /dev/null)
    if [[ -n "$acrobat_raw" ]]; then
        acrobat_Gentech=$(clean_output "$acrobat_raw")
    fi
fi

# Prepare the result
if [[ -n "${reader_Gentech}" ]] || [[ -n "${acrobat_Gentech}" ]]; then
    result=""
    [[ -n "${reader_Gentech}" ]] && result+="Adobe Reader: ${reader_Gentech}"$'\n'
    [[ -n "${acrobat_Gentech}" ]] && result+="Adobe Acrobat Pro: ${acrobat_Gentech}"$'\n'
    result=${result%$'\n'} # Remove trailing newline
    echo "<result>${result}</result>"
else
    echo "<result>No Generative AI settings found in preference files.</result>"
fi

exit 0
