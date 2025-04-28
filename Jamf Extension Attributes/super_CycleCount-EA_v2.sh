#!/bin/bash
####################################################################################################
# Script Name:  super-CycleCount-EA.sh (v4)
# By:             Tony Young
#                 https://github.com/tonyyo11/MacAdministration
# Date:           April 28th, 2025
# Version:        2.1
#
# Purpose:
#   Count full Start→Exit (EXIT CLEAN or EXIT ERROR) cycles in super.log,
#   detect cycles with specific user dialogs or deferral choices,
#   detect OS updates between cycles (major.minor.patch only) and count cycles since last OS update,
#   optionally limit to the last X days of log entries,
#   and report results including cycles since last update.
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
  cutoff_epoch=$(date -v-"${DAYS}"d +%s 2>/dev/null) || \
  cutoff_epoch=$(date --date="${DAYS} days ago" +%s 2>/dev/null)
fi

# Initialize counters and state
cycle_count=0
dialog_cycle_count=0
cycles_since_update=0
in_cycle=false
start_date=""
end_date=""
had_dialog=false
last_version=""
last_update_date=""

# Grep pattern for relevant lines including OS version, startup, exit, and dialogs
GREP_PATTERN='SUPER STARTUP|EXIT CLEAN|EXIT ERROR|Dialog user scheduled installation\.|Dialog soft deadline\.|Dialog user authentication\.|Dialog insufficient storage\.|Dialog power required\.|Dialog user choice\.|User chose|Status: Mac computer with'

# Process relevant log lines
while IFS= read -r raw; do
  # extract timestamp (e.g. "Apr 12 06:45:25")
  ts=$(echo "$raw" | awk '{print $2" "$3" "$4}')

  # Skip entries older than cutoff
  if [[ $DAYS -gt 0 ]]; then
    log_epoch=$(date -j -f "%b %d %T" "$ts" +%s 2>/dev/null) || \
    log_epoch=$(date --date="$ts" +%s 2>/dev/null)
    [[ -n "$log_epoch" && "$log_epoch" -lt "$cutoff_epoch" ]] && continue
  fi

  # Detect OS version lines and track updates (only major.minor.patch)
  if [[ "$raw" == *"Status: Mac computer with"* ]]; then
    # Extract semantic version before build suffix (strip after dash)
    semver=$(echo "$raw" | sed -E 's/.*running: [^0-9]*([0-9]+\.[0-9]+(\.[0-9]+)?)-.*/\1/')
    version="$semver"
    # On first version line, set last_version
    if [[ -z "$last_version" ]]; then
      last_version="$version"
    elif [[ "$version" != "$last_version" ]]; then
      last_update_date="$ts"
      cycles_since_update=0
      last_version="$version"
    fi
    continue
  fi

  # Detect cycle start
  if [[ "$raw" == *"SUPER STARTUP"* ]]; then
    in_cycle=true
    had_dialog=false
    [[ -z "$start_date" ]] && start_date="$ts"
    continue
  fi

  # Detect dialogs within cycle
  if $in_cycle && ([[ "$raw" == *"Dialog user scheduled installation."* ]] ||
                    [[ "$raw" == *"Dialog soft deadline."* ]] ||
                    [[ "$raw" == *"Dialog user authentication."* ]] ||
                    [[ "$raw" == *"Dialog insufficient storage."* ]] ||
                    [[ "$raw" == *"Dialog power required."* ]] ||
                    [[ "$raw" == *"Dialog user choice."* ]] ||
                    [[ "$raw" == *"User chose"* ]]); then
    had_dialog=true
    continue
  fi

  # Detect cycle end
  if $in_cycle && ([[ "$raw" == *"EXIT CLEAN"* ]] || [[ "$raw" == *"EXIT ERROR"* ]]); then
    ((cycle_count++))
    end_date="$ts"
    [[ "$had_dialog" == true ]] && ((dialog_cycle_count++))
    # Count this cycle for since-update metric if update detected
    [[ -n "$last_update_date" ]] && ((cycles_since_update++))
    in_cycle=false
  fi

done < <(grep -E "$GREP_PATTERN" "$SUPER_LOG_FILE")

# Build result string
if (( cycle_count == 0 )); then
  echo "<result>0 cycles</result>"
else
  result="${cycle_count} cycles (${dialog_cycle_count} with dialogs)"
  if [[ -n "$last_update_date" ]]; then
    result+="; ${cycles_since_update} since last OS update on ${last_update_date}"
  fi
  result+=" from ${start_date} to ${end_date}"
  echo "<result>$result</result>"
fi
exit 0
