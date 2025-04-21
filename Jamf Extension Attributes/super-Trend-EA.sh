#!/bin/bash
####################################################################################################
# Script Name:  super‑Trend‑EA.sh
# By: 			Tony Young
# 				https://github.com/tonyyo11/MacAdministration
# Date: 		April 18th, 2025
# Version:		1.0
#
# Purpose:
#   Emit a one‑line category timeline from super.log for only the most
#   recent MAX_CYCLES, limiting to MAX_EVENTS_PER_CYCLE per cycle,
#   plus a summary of the date range at the top.
####################################################################################################
# ────────────────────────────────────────────────────────────────────────────────
# USER CONFIGURATION
# ────────────────────────────────────────────────────────────────────────────────
ONLY_UNIQUE_TRANSITIONS=true    # show only when category changes?
MAX_EVENTS_PER_CYCLE=10         # 0 = unlimited per cycle
MAX_CYCLES=3                    # 0 = unlimited cycles (use most recent N)
# ────────────────────────────────────────────────────────────────────────────────

# Path to the super working folder:
SUPER_FOLDER="/Library/Management/super"

# Path to the super log folder:
SUPER_LOG_FOLDER="${SUPER_FOLDER}/logs"

# Path to the super Log File
SUPER_LOG_FILE="${SUPER_LOG_FOLDER}/super.log"

categorize_line() {
  local txt="$1"
  if [[ "$txt" == *"super log was larger than"* ]]; then
    echo "Resetting"; return
  fi
  if [[ "$txt" == *"SUPER STARTUP"* ]]; then
    echo "Start"; return
  fi
  if [[ "$txt" == *"SCHEDULED RESTART"* ]]; then
    echo "Pending"; return
  fi
  if [[ "$txt" == *"CHECK FOR SOFTWARE UPDATES"* ]] || \
     [[ "$txt" == *"CHECK FOR SOFTWARE UPGRADES"* ]]; then
    echo "Running SoftwareUpdate"; return
  fi
  if [[ "$txt" == *"EXIT ERROR"* ]]; then
    echo "Error"; return
  fi
  if [[ "$txt" == *"EXIT AND RESTART WORKFLOW"* ]]; then
    echo "Pending"; return
  fi
  if [[ "$txt" == *"EXIT CLEAN"* ]]; then
    echo "Complete"; return
  fi
  if [[ "$txt" == *"Deleting local preference"* ]] || \
     [[ "$txt" == *"Deleting all local"* ]]; then
    echo "Resetting"; return
  fi

  # Drop all other Status:… as Info → we’ll filter these out later
  if [[ "$txt" == Status:* ]]; then
    echo "Info"; return
  fi

  # fallback to the rest of your Status mapping
  if [[ "$txt" == *"Inactive Error:"* ]]; then
    echo "Error"
  elif [[ "$txt" == *"Inactive:"* ]]; then
    echo "Inactive"
  elif [[ "$txt" == Running* ]]; then
    [[ "$txt" == *"Dialog"* ]] && echo "Dialog Prompts" || echo "Running SoftwareUpdate"
  elif [[ "$txt" == *"Pending:"* ]]; then
    echo "Pending"
  elif [[ "$txt" == *"Full super workflow complete!"* ]]; then
    echo "Complete"
  elif [[ "$txt" == *"Error:"* ]] || [[ "$txt" == *"Warning:"* ]]; then
    echo "Error"
  else
    echo "Unknown"
  fi
}

# ────────────────────────────────────────────────────────────────────────────────
# main
# ────────────────────────────────────────────────────────────────────────────────
if [[ ! -f "$SUPER_LOG_FILE" ]]; then
  echo "<result>No super.log file found</result>"
  exit 0
fi

# 1) Count total Start cycles
total_cycles=0
while IFS= read -r raw; do
  msg="${raw#*]: }"
  [[ "$(categorize_line "$msg")" == "Start" ]] && ((total_cycles++))
done < <(grep -E "SUPER STARTUP" "$SUPER_LOG_FILE")

# 2) Compute first cycle to capture
if (( MAX_CYCLES > 0 )); then
  first_cycle=$(( total_cycles - MAX_CYCLES + 1 ))
  (( first_cycle < 1 )) && first_cycle=1
else
  first_cycle=1
fi

# 3) Build the condensed timeline
cycle_idx=0
cycle_event_count=0
prev_cat=""
timeline_str=""
start_date=""
end_date=""

while IFS= read -r raw; do
  ts=$(echo "$raw" | awk '{print $2" "$3" "$4}')
  msg="${raw#*]: }"
  cat=$(categorize_line "$msg")

  # detect a new cycle
  if [[ "$cat" == "Start" ]]; then
    ((cycle_idx++))
    cycle_event_count=0
  fi

  # skip entire cycles before first_cycle
  if (( cycle_idx < first_cycle )); then
    continue
  fi

  # record the very first timestamp included
  [[ -z "$start_date" ]] && start_date="$ts"

  # drop Info entries entirely
  if [[ "$cat" == "Info" ]]; then
    continue
  fi

  # unique-transition filtering
  if $ONLY_UNIQUE_TRANSITIONS && [[ "$cat" == "$prev_cat" ]]; then
    continue
  fi

  # cap events per cycle (after Start)
  if [[ "$cat" != "Start" && MAX_EVENTS_PER_CYCLE -gt 0 ]]; then
    ((cycle_event_count++))
    if (( cycle_event_count > MAX_EVENTS_PER_CYCLE )); then
      continue
    fi
  fi

  # append with spaced hyphens
  if [[ -z "$timeline_str" ]]; then
    timeline_str="$cat"
  else
    timeline_str+=" - $cat"
  fi

  prev_cat="$cat"
  end_date="$ts"
done < <(grep -E "SUPER STARTUP|SCHEDULED RESTART|EXIT|CHECK FOR SOFTWARE|Status:" "$SUPER_LOG_FILE")

# 4) Output summary + single‑line timeline
if [[ -n "$timeline_str" ]]; then
  echo "<result>Timeline from ${start_date} to ${end_date}
${timeline_str}</result>"
else
  echo "<result>No events found</result>"
fi

exit 0