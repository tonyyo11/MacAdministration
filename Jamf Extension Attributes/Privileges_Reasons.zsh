#!/bin/zsh

# Fetch the last 10 logs containing the admin privilege escalation reasons
log_output=$(/usr/bin/log show --style syslog --predicate 'process == "PrivilegesDaemon" && eventMessage CONTAINS "SAPCorp"' --info | grep -i "privileges for the following reason")

# Extract the reasons using awk
reasons=$(echo "$log_output" | awk -F'for the following reason: ' '{print $2}' | tail -n 5)

# Jamf EA output
echo "<result>"
echo "$reasons"
echo "</result>"
