#!/bin/zsh

############################## ORGANIZATION HEADER ##############################
# Organization: Cloud Lake Technology, an Akima company
# Maintainer: Tony Young (IT Operations Engineer)
# Purpose: Enforce Adobe Creative Cloud updates via Adobe RUM with SwiftDialog
# Notes: Non-interactive 2-minute warning only when apps are open & updates exist.
#        Silent when apps are closed or when no updates exist. Exits 0 by default.
#################################################################################


# ---- Behavior Flags ----
FAIL_ON_MISSING_RUM=false
SHOW_NOTIFICATIONS=false
# Track state for logging
UPDATES_AVAILABLE=false
ADOBE_APPS_RUNNING=false

# Don't abort on non-zero exits; we handle statuses manually
set +e


############################## NOTES ###################################
# Script Name: adobe_rum_swiftdialog.sh
#
# Author: Owain Iorwerth (MacAdmins: Poppy)
#
# Date: 12 May 2025
#
# Logic: Adapted from two other scripts
# - "ACBJ Adobe RUM swiftDialog Self Service.sh" (MacAdmins: A-bomb)
# - "Adobe_RemoteUpdateManager_via_JamfHelper.sh" (MacAdmins: Tony Young)
#
# Summary: Lightweight Adobe updater for macOS using Adobe RUM and SwiftDialog.
# - Uses Adobe RUM to check for updates.
# - If updates are available:
#     - If Adobe apps are running:
#         - Shows a SwiftDialog popup with update details.
#         - User must click "Quit and Update".
#     - If no Adobe apps are running:
#         - Skips the popup and runs update silently.
#     - In both cases:
#         - Adobe processes are killed before update.
#         - Shows macOS-style notifications:
#             1. "Adobe Updates in Progress..."
#             2. "Success: Adobe apps have been updated."
# - If no updates are found:
#     - No dialog or notifications are shown.
#
# Log Path: /Library/Application Support/CustomAdobeUpdater/
########################################################################

# Dialog appearance and process detection [AMEND COMPANY NAME + ICON PATH BELOW]
notification_message="**Updates available for Adobe!**"
adobe_icon="/Library/Application Support/Adobe/Creative Cloud Libraries/CCLibrary.app/Contents/Resources/cc_app.icns"
adobeBackgroundProcesses="Creative Cloud|Adobe Desktop Service|AdobeIPCBroker|CoreSync|CCXProcess"

# Paths, tools, and logging
dialogPath="/usr/local/bin/dialog"
logPath="/Library/Application Support/CustomAdobeUpdater"
rumlog="$logPath/AdobeRUMUpdatesLog.log"
rum="/usr/local/bin/RemoteUpdateManager"
jamf_bin="/usr/local/bin/jamf"
installRUM="${4}" # Jamf custom trigger to install RUM if missing
rumupdate="/usr/local/bin/RemoteUpdateManager --action=install"

# Function to log messages to both Terminal and log file
log() {
    echo "$1"
    echo "$1" >>"$rumlog"
}

# Create (or append to) the Adobe RUM log file
configureLog() {
    # Ensure the log directory exists
    if [[ ! -d "$logPath" ]]; then
        mkdir -p "$logPath"
    fi

    # Ensure the log file exists before using `log`
    touch "$rumlog"
}

# Ensure SwiftDialog is installed, or install it from GitHub if missing
dialogCheck() {
    if ! command -v dialog >/dev/null 2>&1; then
        echo "Dialog is not installed. Installing..."
        dialogURL=$(curl --silent --fail "https://api.github.com/repos/bartreardon/swiftDialog/releases/latest" | awk -F '"' "/browser_download_url/ && /pkg\"/ { print \$4; exit }")
        curl -L "$dialogURL" -o /tmp/dialog.pkg
        sudo installer -pkg /tmp/dialog.pkg -target /
        rm /tmp/dialog.pkg
    fi
}

# Ensure Adobe RemoteUpdateManager (RUM) is present, or trigger its install via another Jamf policy
rumCheck() {
    if [[ ! -f $rum ]]; then
        log "Installing RUM from JSS"
        $jamf_bin policy -event "$installRUM"
        if [[ ! -f $rum ]]; then
            log "Couldn't install RUM! Exiting."
            if [[ "$FAIL_ON_MISSING_RUM" = true ]]; then
                exit 1
            else
                log "RUM missing and could not be installed. Exiting gracefully with success to avoid Jamf policy failure."
                exit 0
            fi
        fi
        log "RUM installation successful."
    else
        log "RUM is already installed."
    fi
}

# macOS syle notification via SwiftDialog
displaynotification() {
    local message="${1:-Message}"
    local title="${2:-Notification}"

    if [[ -x "$dialogPath" ]] && [[ "$($dialogPath --version | cut -d "." -f1)" -ge 2 ]]; then
        "$dialogPath" --notification --title "$title" --message "$message"
    fi
}

# Check for Updates to Adobe apps
checkForUpdates() {
    # Check if any visible Adobe Creative Cloud apps are currently running
    adobeAppsRunning=false
    ADOBE_APPS_RUNNING=false
    if pgrep -f "Adobe Photoshop|Adobe Illustrator|Adobe Premiere Pro|Adobe After Effects|Adobe InDesign|Adobe Acrobat|Adobe Lightroom|Adobe Dreamweaver|Adobe Audition|Adobe Animate|Adobe Bridge|Adobe Media Encoder|Adobe XD|Adobe Prelude|Adobe Substance" >/dev/null; then
        adobeAppsRunning=true
        ADOBE_APPS_RUNNING=true
    fi

    # Use Adobe RUM to list applicable updates and save output to log
    $rum --action=list >"$rumlog"

    # Extract and reformat the list of applicable updates from the RUM output
    raw_updates=$(awk '/Following Updates are applicable on the system/{flag=1; next} /\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*/{flag=0} flag' "$rumlog")

    # Mark updates available if we have any parsed records
    if [[ -n "$raw_updates" ]]; then
        UPDATES_AVAILABLE=true
        secho=$(echo "$raw_updates" | sed -E '
            s/^[[:space:]]*\(//;
            s/ACR/Camera Raw/g;
            s/AEFT/After Effects/g;
            s/AME/Media Encoder/g;
            s/AUDT/Audition/g;
            s/COMP/Comp/g;
            s/FLPR/Animate/g;
            s/ILST/Illustrator/g;
            s/MUSE/Muse/g;
            s/PHSP/Photoshop/g;
            s/PRLD/Prelude/g;
            s/SPRK/XD/g;
            s/KBRG/Bridge/g;
            s/AICY/InCopy/g;
            s/ANMLBETA/Character Animator Beta/g;
            s/DRWV/Dreamweaver/g;
            s/IDSN/InDesign/g;
            s/PPRO/Premiere Pro/g;
            s/LTRM/Lightroom Classic/g;
            s/LRCC/Lightroom/g;
            s/CHAR/Character Animator/g;
            s/SBSTA/Substance Alchemist/g;
            s/SBSTD/Substance Designer/g;
            s/SBSTP/Substance Painter/g;
            s/ESHR/Dimension/g;
            s/RUSH/Premiere Rush/g;
            s/SEPS/Substance 3D Viewer/g;
            s/\\/\\\\/g;
            s/[\(\)\.\*\[\]]/\\&/g;
            s/\)//g;
            s#/macuniversal##g;
            s#/macarm64##g;
            s#/# (v#;
            s#$#)#;
        ')
    else
        secho=""
    fi

    # Log and display processed update list if available
    if [[ -n "$secho" ]]; then
        log "=== Processed List Output ==="
        echo "$secho" >>"$rumlog"
        printf "%b\n" "$secho"
    fi

    # Prepare secho for swiftDialog's markdown-like rendering (adds two spaces to the end of each line in $secho)
    secho_for_dialog=$(echo "$secho" | sed 's/$/  /')

    updatesComplete() {
        displaynotification "Adobe apps have been updated." 'Success!'
    }

    # Exit early if no updates are found
    if ! grep -iq "updates are applicable on the system" "$rumlog" || [[ -z "$raw_updates" ]]; then
        log "No Updates available. Exiting silently."
        summarizeResults
        exit 0
    fi

    # If no Adobe apps are running, perform a silent update with NO user notifications
    if [[ "$adobeAppsRunning" = false ]]; then
        SHOW_NOTIFICATIONS=false
# Track state for logging
UPDATES_AVAILABLE=false
ADOBE_APPS_RUNNING=false
        installUpdates
        updatesComplete
        summarizeResults
        exit 0
    else
        SHOW_NOTIFICATIONS=true
        # Non-interactive warning with 2-minute delay, then force-quit and update
        warning_message="**Adobe updates will begin in 2 minutes.**

Any open Adobe applications will be **force-quit** to apply updates.
Please save your work now.

This is automatic and does not require your input."

        # Launch SwiftDialog window (no buttons) to warn the user
        "$dialogPath" \
            --title none \
            --moveable \
            --width "520" \
            --height "200" \
            --position "Left" \
            --messagealignment "Left" \
            --messagefont "size=13" \
            --message "$warning_message\n\n$secho_for_dialog" \
            --icon "$adobe_icon" \
            --iconsize 80 &

        dialogpid=$!
        log "Displayed enforced warning. Waiting 120 seconds before proceeding..."
        sleep 120

        # Close the warning dialog if still present
        if kill -0 "$dialogpid" 2>/dev/null; then
            kill "$dialogpid" 2>/dev/null || true
            pkill -x "swiftDialog" 2>/dev/null || true
        fi

        # Proceed with update: force-quit Adobe apps and run RUM
        log "Proceeding with enforced quit and update after countdown."
        installUpdates
        updatesComplete
    fi
}

# Install Updates

# Emit a concise Jamf-friendly "Script Result" summary to stdout
summarizeResults() {
    echo "----- Jamf Script Result -----"
    echo "Updates available: ${UPDATES_AVAILABLE}"
    echo "Adobe apps running at start: ${ADOBE_APPS_RUNNING}"

    # Parse successes/failures from $rumlog (best-effort; patterns vary across RUM versions)
    # Capture install session delimiters to narrow scope (optional; works even if missing)
    # Grep common success/failure markers and extract app names heuristically.
    if [[ -f "$rumlog" ]]; then
        # Success lines (case-insensitive)
        success_lines=()
		while IFS= read -r line; do
    		success_lines+=("$line")
		done < <(grep -Ei "install(ed)? (success|succeeded)|successfully installed|status:\s*success" "$rumlog" || true)

        # Failure lines (case-insensitive)
        fail_lines=()
		while IFS= read -r line; do
    		fail_lines+=("$line")
		done < <(grep -Ei "install(ed)? (fail|failed)|status:\s*fail|error" "$rumlog" || true)

        # Helper to extract an app name-ish token from a line (heuristic)
        extract_name() {
            # Try bracketed or quoted names first, then fallback to words after 'Installing'/'Install of'
            local line="$1"
            local name=""
            name=$(echo "$line" | sed -nE "s/.*[\"'»>]]([A-Za-z0-9 .+-]+)[\"'«<[]].*/\1/p" | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')
            if [[ -z "$name" ]]; then
                name=$(echo "$line" | sed -nE "s/.*(Installing|Install of)[[:space:]]+([A-Za-z0-9 .+-]+).*/\2/p" | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')
            fi
            if [[ -z "$name" ]]; then
                # Fallback: strip generic words and keep capitalized tokens
                name=$(echo "$line" | sed -E 's/(Installing|Install|status|success|failed|error|:|=)//ig' | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')
            fi
            echo "$name"
        }

        declare -a success_apps=()
        for l in "${success_lines[@]}"; do
            n=$(extract_name "$l")
            [[ -n "$n" ]] && success_apps+=("$n")
        done

        declare -a fail_apps=()
        for l in "${fail_lines[@]}"; do
            n=$(extract_name "$l")
            [[ -n "$n" ]] && fail_apps+=("$n")
        done

        # De-duplicate
        dedup() {
            awk '!seen[$0]++'
        }
        success_apps_unique=$(printf "%s\n" "${success_apps[@]}" | sed '/^$/d' | dedup | paste -sd ", " -)
        fail_apps_unique=$(printf "%s\n" "${fail_apps[@]}" | sed '/^$/d' | dedup | paste -sd ", " -)

        success_count=$(printf "%s" "$success_apps_unique" | awk -F',' '{print NF}' 2>/dev/null)
        [[ -z "$success_apps_unique" ]] && success_count=0
        fail_count=$(printf "%s" "$fail_apps_unique" | awk -F',' '{print NF}' 2>/dev/null)
        [[ -z "$fail_apps_unique" ]] && fail_count=0

        echo "Succeeded: ${success_count}"
        [[ -n "$success_apps_unique" ]] && echo "  - ${success_apps_unique}"
        echo "Failed: ${fail_count}"
        [[ -n "$fail_apps_unique" ]] && echo "  - ${fail_apps_unique}"

        # Path to detailed log
        echo "Log: ${rumlog}"
    else
        echo "No RUM log found for summary."
    fi
}

installUpdates() {
    # Prevent the Mac from sleeping during update process
    caffeinate -dimsu &
    caffeinatepid=$!
    if [[ "$SHOW_NOTIFICATIONS" = true ]]; then
        displaynotification "Wait for success message before opening" "Adobe Updates in Progress..."
    fi

    # Log currently running Adobe-related processes
    log "Checking for active Adobe processes before quitting..."
    pgrep -af "$adobeBackgroundProcesses" >>"$rumlog"

    # Kill all visible Adobe processes and background services before update
    log "Closing active Adobe processes before update..."
    pkill -i "^Adobe"
    pkill -f "$adobeBackgroundProcesses"

    # Wait until all Adobe processes have exited or timeout is reached (max 5 minutes)
    start_time=$(date +%s)
    max_wait_time=300

    while pgrep -f "Adobe|$adobeBackgroundProcesses" >/dev/null; do
        current_time=$(date +%s)
        elapsed_time=$((current_time - start_time))
        if [[ $elapsed_time -ge $max_wait_time ]]; then
            log "Timeout waiting for Adobe apps to quit."
            break
        fi
        sleep 5
    done

    # Run Adobe RUM to install updates
    log "Starting Update Process..."
    # Capture RUM install output and append to log for later parsing
    { $rum --action=install | tee -a "$rumlog"; } ; rum_result=${pipestatus[1]}

    # Capture and log RUM's exit status as success or failure
    result=$([[ "$rum_result" -eq 0 ]] && echo "success" || echo "failure")
    log "RUM installation result: $result"

    # Stop caffeinate process after update is complete
    [[ -n "$caffeinatepid" ]] && kill "$caffeinatepid"
}

# Script Order
configureLog
dialogCheck
rumCheck
checkForUpdates

summarizeResults

# Always exit successfully to prevent Jamf policy failure due to partial app update errors
exit 0
