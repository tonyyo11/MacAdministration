#!/bin/bash

#Created by Tony Young | Akima / Cloud Lake Technology
#v.2.0 -- 1/23/2025

# Check if RemoteUpdateManager exists
if ! command -v RemoteUpdateManager &> /dev/null; then
    echo "Error: RemoteUpdateManager is not installed or not in PATH." >> /var/log/jamf.log
    exit 1
fi

echo "Starting Adobe Update Script" >> /var/log/jamf.log

#initialize JAMF parameters
DeferinSeconds1="$4"
DeferinSeconds2="$5"
MessageDescription="$6"

# Check if Adobe Creative Cloud applications (excluding Creative Cloud Desktop App) are running
if ! pgrep -f "Adobe Photoshop|Adobe Illustrator|Adobe Premiere Pro|Adobe After Effects|Adobe InDesign|Adobe Acrobat|Adobe Lightroom|Adobe Dreamweaver|Adobe Audition|Adobe Animate|Adobe Bridge|Adobe Media Encoder|Adobe XD|Adobe Prelude|Adobe Substance"; then
    echo "Adobe Creative Cloud applications are currently running. Proceeding to notify the user..." >> /var/log/jamf.log
else
    echo "No Adobe Creative Cloud apps running. Running RUM silently..." >> /var/log/jamf.log
    sudo /usr/local/bin/RemoteUpdateManager > /tmp/rum_output.log 2>&1
    cat /tmp/rum_output.log >> /var/log/jamf.log
    exit 0
fi

#Run RUM until user selects to start now and closes all Adobe CC processes running on mac. Or User defers and closes applications themselves, where loop will run depending on deferment selected
while true; do 
	ButtonSELECT=$(/Library/Application\ Support/JAMF/bin/jamfHelper.app/Contents/MacOS/jamfHelper \
    -title "Adobe Creative Cloud Updates" \
    -alignHeading center \
    -description "$MessageDescription" \
    -defaultButton 1 \
    -showDelayOptions "now, $DeferinSeconds1, $DeferinSeconds2" \
    -timeout 600 \
    -windowType hud \
    -countdown \
    -heading "Adobe Creative Cloud Updates" \
    -button1 "Ok")

    echo "User selection: $ButtonSELECT" >> /var/log/jamf.log

    if [[ "$ButtonSELECT" = "1" ]]; then
        jamf displayMessage -message "Updates in Progress, please wait until you're notified updates are complete!"
        echo "Killing Adobe processes" >> /var/log/jamf.log
        pkill -i "^Adobe"
        pkill -f "Creative Cloud|Adobe Desktop Service|AdobeIPCBroker|CoreSync|CCXProcess"
        RUM=""
        start_time=$(date +%s)
        max_wait_time=300  # Set timeout limit in seconds (5 minutes)

        while [[ "$RUM" != "(0)" && "$RUM" != "(2)" && "$RUM" != "(1)" ]]; do
            echo "Running RemoteUpdateManager..." >> /var/log/jamf.log
            sudo /usr/local/bin/RemoteUpdateManager > /tmp/rum_output.log 2>&1
            cat /tmp/rum_output.log >> /var/log/jamf.log
            RUM=$(awk '/Return Code/{print $NF}' /tmp/rum_output.log)
            echo "RemoteUpdateManager output: $RUM" >> /var/log/jamf.log

            current_time=$(date +%s)
            elapsed_time=$((current_time - start_time))
            if [[ $elapsed_time -ge $max_wait_time ]]; then
                echo "Error: RemoteUpdateManager timed out after $max_wait_time seconds." >> /var/log/jamf.log
                jamf displayMessage -message "Adobe update timed out. Please contact your administrator."
                exit 1
            fi

            sleep 5  # Avoid overwhelming CPU usage
        done

        if [[ "$RUM" = "(0)" || "$RUM" = "(2)" ]]; then
            echo "All Adobe Updates Complete!" >> /var/log/jamf.log
            jamf displayMessage -message "All Adobe Updates Complete! You can resume and open your Adobe applications"
            exit 0  # Exit after successful update
        elif [[ "$RUM" = "(1)" ]]; then
            echo "Adobe updates failed, retrying once more..." >> /var/log/jamf.log
            sudo /usr/local/bin/RemoteUpdateManager > /tmp/rum_output.log 2>&1
            cat /tmp/rum_output.log >> /var/log/jamf.log
            RUM=$(awk '/Return Code/{print $NF}' /tmp/rum_output.log)
            echo "RemoteUpdateManager retry output: $RUM" >> /var/log/jamf.log
            if [[ "$RUM" = "(1)" ]]; then
                echo "Adobe updates have failed again. Please contact your administrator." >> /var/log/jamf.log
                jamf displayMessage -message "Adobe updates have failed. Please contact your administrator."
                exit 1  # Exit after second failure
            fi
        fi
    elif [[ "$ButtonSELECT" = "${DeferinSeconds1}1" ]]; then
        echo "User deferred for $DeferinSeconds1 seconds" >> /var/log/jamf.log
        sleep "$DeferinSeconds1"
    else
        echo "User deferred for $DeferinSeconds2 seconds" >> /var/log/jamf.log
        sleep "$DeferinSeconds2"
    fi
done

echo "Script completed successfully" >> /var/log/jamf.log
exit 0
