#!/bin/bash
###############################################################################
# Script Name:    Flexera_Jamf_EA_DaemonState.sh
#
# Jamf Pro Type:  Extension Attribute
#
# Purpose:
#   Reports the operational state of key Flexera ManageSoft LaunchDaemons
#   on macOS systems enrolled in Jamf Pro. This Extension Attribute is
#   intended to provide quick visibility into whether the Flexera Inventory
#   Agent services are loaded and available for execution.
#
#   Specifically checks:
#     - com.flexerasoftware.ndtask     (Core inventory scheduler/daemon)
#     - com.flexerasoftware.mgsusageag (Application usage tracking agent)
#
# Output:
#   Returns a single <result> string suitable for Jamf Pro inventory,
#   formatted as:
#
#     ndtask: LOADED|NOT_LOADED; mgsusageag: LOADED|NOT_LOADED
#
#   Example:
#     <result>ndtask: LOADED; mgsusageag: NOT_LOADED</result>
#
# Use Cases:
#   - Validate successful Flexera agent deployment
#   - Confirm daemon load state after installation or upgrades
#   - Support compliance reporting and troubleshooting
#   - Correlate agent health with inventory / usage upload failures
#
# Execution Context:
#   - Runs as root when evaluated by Jamf Pro
#   - Non-interactive
#   - No user interface elements
#   - Safe to run repeatedly (read-only checks)
#
# Dependencies:
#   - macOS launchd
#   - Flexera ManageSoft agent installed
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
#   - This script intentionally checks LaunchDaemon load state only.
#     It does NOT verify successful inventory runs, uploads, or server
#     communication.
#   - A daemon reporting as LOADED does not guarantee functional uploads;
#     refer to Flexera logs under:
#       /private/var/opt/managesoft/log/
#
# Disclaimer:
#   Provided as-is with no warranty. Test thoroughly in non-production
#   environments before relying on for compliance or enforcement decisions.
###############################################################################

if /bin/launchctl print system/com.flexerasoftware.ndtask >/dev/null 2>&1; then
  n="LOADED"
else
  n="NOT_LOADED"
fi

if /bin/launchctl print system/com.flexerasoftware.mgsusageag >/dev/null 2>&1; then
  u="LOADED"
else
  u="NOT_LOADED"
fi

echo "<result>ndtask: $n; mgsusageag: $u</result>"
