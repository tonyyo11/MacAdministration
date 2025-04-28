#!/bin/bash
####################################################################################################
# Script Name:  super‑CycleCount‑EA.sh (v2)
# By:             Tony Young
#                 https://github.com/tonyyo11/MacAdministration
# Date:           April 28th, 2025
# Version:        2.0
#
# Purpose:
#   Count full Start→Exit (EXIT CLEAN or EXIT ERROR) cycles in super.log,
#   detect cycles that presented specific user dialogs or deferral choices,
#   optionally limit to the last X days of log entries,
#   and report the number of total cycles along with how many included dialogs, plus the date range.
####################################################################################################

# Path to the super working folder:
SUPER_FOLDER="/Library/Management/super"

# Path to the super log folder:
SUPER_LOG_FOLDER="${SUPER_FOLDER}/logs"

# Path to the super Log File
SUPER_LOG_FILE="${SUPER_LOG_FOLDER}/super.log"

# Configurable: number of days of logs to include; set to 0 to include all logs
DAYS=30

# Exit if no log file present:
if [[ ! -f "$SUPER_LOG_FILE" ]]; then
  echo "<result>0 cycles</result>"
  exit 0
fi

# Calculate cutoff epoch if DAYS > 0
if [[ $DAYS -gt 0 ]]; then
  # BSD/macOS date
  cutoff_epoch=$(date -v-"${DAYS}"d +%s 2>/dev/null) || \
  # GNU date fallback
  cutoff_epoch=$(date --date="${DAYS} days ago" +%s 2>/dev/null)
fi

cycle_count=0
dialog_cycle_count=0
in_cycle=false
start_date=""
end_date=""
had_dialog=false

# Grep pattern for startup, exit, and dialog/choice messages (without 'Running:' or 'Pending:' prefixes)
GREP_PATTERN='SUPER STARTUP|EXIT CLEAN|EXIT ERROR|Dialog user scheduled installation\.|Dialog soft deadline\.|Dialog user authentication\.|Dialog insufficient storage\.|Dialog power required\.|Dialog user choice\.|User chose'

# Process relevant log lines
while IFS= read -r raw; do
  # extract timestamp (e.g. "Apr 12 06:45:25")
  ts=$(echo "$raw" | awk '{print $2" "$3" "$4}')

  # If limiting by DAYS, skip entries older than cutoff
  if [[ $DAYS -gt 0 ]]; then
    # Convert timestamp to epoch (BSD/macOS date first, then GNU date)
    log_epoch=$(date -j -f "%b %d %T" "$ts" +%s 2>/dev/null) || \
    log_epoch=$(date --date="$ts" +%s 2>/dev/null)
    if [[ -n "$log_epoch" && "$log_epoch" -lt "$cutoff_epoch" ]]; then
      continue
    fi
  fi

  if [[ "$raw" == *"SUPER STARTUP"* ]]; then
    in_cycle=true
    had_dialog=false
    # record the very first startup timestamp
    if [[ -z "$start_date" ]]; then
      start_date="$ts"
    fi

  elif $in_cycle && (
         [[ "$raw" == *"Dialog user scheduled installation."* ]] ||
         [[ "$raw" == *"Dialog soft deadline."* ]] ||
         [[ "$raw" == *"Dialog user authentication."* ]] ||
         [[ "$raw" == *"Dialog insufficient storage."* ]] ||
         [[ "$raw" == *"Dialog power required."* ]] ||
         [[ "$raw" == *"Dialog user choice."* ]] ||
         [[ "$raw" == *"User chose"* ]]
       ); then
    had_dialog=true

  elif $in_cycle && ([[ "$raw" == *"EXIT CLEAN"* ]] || [[ "$raw" == *"EXIT ERROR"* ]]); then
    ((cycle_count++))
    # update end_date to the timestamp of each exit; ends up as the last one
    end_date="$ts"
    if [[ "$had_dialog" == true ]]; then
      ((dialog_cycle_count++))
    fi
    in_cycle=false
  fi
# Only feed relevant lines to reduce processing overhead
# Use process substitution to feed grep output
done < <(grep -E "$GREP_PATTERN" "$SUPER_LOG_FILE")

# Output results
if [[ $cycle_count -eq 0 ]]; then
  echo "<result>0 cycles</result>"
else
  echo "<result>${cycle_count} cycles (${dialog_cycle_count} with dialogs) from ${start_date} to ${end_date}</result>"
fi

exit 0
