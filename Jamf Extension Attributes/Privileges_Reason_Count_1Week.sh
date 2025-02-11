#!/bin/bash

# Get the timestamp for 7 days ago
start_date=$(date -v-7d +"%Y-%m-%d")

# Get today's date
end_date=$(date +"%Y-%m-%d")

# Fetch logs from the last 7 days containing admin privilege escalation reasons
log_count=$(sudo /usr/bin/log show --style syslog --predicate 'process == "PrivilegesDaemon" && eventMessage CONTAINS "SAPCorp"' --info --start "$start_date" | grep -ci "privileges for the following reason")

# Jamf EA output with additional text
echo "<result>Elevated $log_count times from $start_date to $end_date</result>"
