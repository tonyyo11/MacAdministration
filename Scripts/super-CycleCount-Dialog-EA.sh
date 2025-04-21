#!/bin/bash
####################################################################################################
# Script Name:  super‑CycleCount‑EA.sh
# By:             Tony Young
#                 https://github.com/tonyyo11/MacAdministration
# Date:           April 18th, 2025
# Version:        1.2
#
# Purpose:
#   Count full Start→Exit (EXIT CLEAN or EXIT ERROR) cycles in super.log,
#   detect cycles that presented specific user dialogs or deferral choices,
#   and report the number of total cycles along with how many included dialogs, plus the date range.
####################################################################################################

# Path to the super working folder:
SUPER_FOLDER="/Library/Management/super"

# Path to the super log folder:
SUPER_LOG_FOLDER="${SUPER_FOLDER}/logs"

# Path to the super Log File
SUPER_LOG_FILE="${SUPER_LOG_FOLDER}/super.log"

# Exit if no log file present:
if [[ ! -f "$SUPER_LOG_FILE" ]]; then
  echo "<result>0 cycles</result>"
  exit 0
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
done < <(grep -E "$GREP_PATTERN" "$SUPER_LOG_FILE")

# Output results
if [[ $cycle_count -eq 0 ]]; then
  echo "<result>0 cycles</result>"
else
  echo "<result>${cycle_count} cycles (${dialog_cycle_count} with dialogs) from ${start_date} to ${end_date}</result>"
fi

exit 0
