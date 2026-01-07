#!/bin/bash
###############################################################################
# Script Name:    Flexera_Jamf_EA_InventoryFreshness.sh
#
# Jamf Pro Type:  Extension Attribute
#
# Purpose:
#   Determines the freshness of the most recent Flexera (ManageSoft)
#   inventory run on a macOS system by evaluating the timestamp of the
#   latest generated inventory (.ndi or .ndi.gz) file.
#
#   This Extension Attribute provides Jamf Pro administrators with
#   visibility into whether the Flexera Inventory Agent is:
#     - Actively collecting inventory
#     - Stalled or failing to run
#     - Installed but not operational
#
# Methodology:
#   - Inspects the Flexera inventory upload directory:
#       /private/var/opt/managesoft/uploads/Inventories
#   - Identifies the most recently modified inventory file
#   - Calculates the age (in days) since last inventory generation
#
# Output:
#   Returns a single <result> value suitable for Jamf Pro inventory,
#   typically one of the following formats:
#
#     - Never
#     - <N> days
#     - <N> hours (optional implementation detail)
#
#   Example:
#     <result>2 days</result>
#
# Use Cases:
#   - Compliance reporting (inventory currency)
#   - Troubleshooting missing or stale Flexera data in FNMS
#   - Validating post-install and post-upgrade agent health
#   - Identifying systems requiring forced inventory runs
#
# Execution Context:
#   - Runs as root when evaluated by Jamf Pro
#   - Non-interactive
#   - No user interface elements
#   - Read-only inspection of local filesystem
#
# Dependencies:
#   - Flexera ManageSoft agent installed
#   - Inventory uploads directory present
#
# Related Components:
#   - Inventory binaries:
#       /opt/managesoft/libexec/ndtrack
#       /opt/managesoft/libexec/ndupload
#   - Logs:
#       /private/var/opt/managesoft/log/tracker.log
#       /private/var/opt/managesoft/log/uploader.log
#
# Author:         Tony Young
# Organization:   Cloud Lake Technology, an Akima Company
# Blog / Repo:    https://github.com/tonyyo11/MacAdministration
# Project:        Patch Notes & Progress
#
# Created:        2026-01-07
# Last Updated:   2026-01-07
#
# Notes:
#   - This script evaluates inventory generation time, not upload success.
#     A recent inventory file does not guarantee successful upload to
#     Flexera beacons or FNMS.
#   - Network failures, TLS issues, or server-side errors may still
#     prevent inventory ingestion despite fresh local files.
#
# Disclaimer:
#   Provided as-is with no warranty. Validate logic and thresholds in
#   test environments before using for compliance enforcement.
###############################################################################

LOG1="/private/var/opt/managesoft/log/mgs1-tracker.log"
LOG2="/private/var/opt/managesoft/log/tracker.log"
AGENT_DIR="/opt/managesoft"
THRESHOLD_DAYS=7

if [ ! -d "$AGENT_DIR" ]; then
  echo "<result>NOT_INSTALLED</result>"
  exit 0
fi

LOG=""
[ -f "$LOG1" ] && LOG="$LOG1"
[ -z "$LOG" ] && [ -f "$LOG2" ] && LOG="$LOG2"

if [ -z "$LOG" ]; then
  echo "<result>ERROR: no tracker log</result>"
  exit 0
fi

last_line=$(/usr/bin/grep -h "Finished uploading inventory" "$LOG" | /usr/bin/tail -n 1)
if [ -z "$last_line" ]; then
  echo "<result>ERROR: no successful upload</result>"
  exit 0
fi

ts=$(echo "$last_line" | /usr/bin/awk -F'[][]' '{print $2}' | /usr/bin/awk '{print $2, $3, $4, $5}')
last_epoch=$(/bin/date -j -f "%b %e %H:%M:%S %Y" "$ts" +"%s" 2>/dev/null)
now_epoch=$(/bin/date +"%s")

if [ -z "$last_epoch" ]; then
  echo "<result>ERROR: could not parse last upload</result>"
  exit 0
fi

age_days=$(( (now_epoch - last_epoch) / 86400 ))
if [ "$age_days" -le "$THRESHOLD_DAYS" ]; then
  echo "<result>OK - last upload ${age_days}d ago</result>"
else
  echo "<result>WARN - last upload ${age_days}d ago</result>"
fi
