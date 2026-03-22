#!/bin/zsh
# ============================================================
# Script Name:   EA - Hardware - Data Volume Disk Risk
# Description:   Capacity-aware disk pressure label with a hard 45 GB free
#                space floor across all drive sizes. Designed for Smart Group
#                targeting and fleet health dashboard reporting.
# Author:        Tony Young / Akima
# Version:       2.0
# Last Updated:  2026-03-21
#
# EA Type:       String
# Possible values:
#   Low        - Healthy; no action needed
#   Moderate   - Worth monitoring; approaching thresholds
#   High       - User notification warranted; begin cleanup
#   Critical   - Immediate action required; macOS update/upgrade at risk
#   Unknown    - diskutil returned no usable data
#
# Threshold logic (all conditions use OR — either trigger escalates):
#
#   Hard floor (all drive sizes):
#     Critical  < 45 GB free
#     High      < 60 GB free
#     Moderate  < 80 GB free
#
#   Percentage tiers by drive capacity:
#     < 300 GB   Critical ≥ 88%  High ≥ 80%  Moderate ≥ 70%
#     300–999 GB Critical ≥ 92%  High ≥ 85%  Moderate ≥ 75%
#     1–1.99 TB  Critical ≥ 94%  High ≥ 88%  Moderate ≥ 80%
#     ≥ 2 TB     Critical ≥ 96%  High ≥ 90%  Moderate ≥ 85%
#
# Jamf Parameters: None
# ============================================================

# --- Constants ---
readonly FLOOR_CRITICAL_GB=45
readonly FLOOR_HIGH_GB=60
readonly FLOOR_MODERATE_GB=80

# --- Gather disk data via diskutil ---
totalBytes=$( diskutil info / \
    | grep -E 'Container Total Space|Total Space' \
    | sed -E 's/.*\(([0-9]+) Bytes\).*/\1/' \
    | head -1 )

freeBytes=$( diskutil info / \
    | grep -E 'Container Free Space|Free Space|Available Space' \
    | sed -E 's/.*\(([0-9]+) Bytes\).*/\1/' \
    | head -1 )

# --- Validate we got usable numbers ---
if [[ -z "$totalBytes" || "$totalBytes" == "0" || -z "$freeBytes" ]]; then
    echo "<r>Unknown</r>"
    exit 0
fi

# --- Derive working values ---
totalGB=$(( totalBytes / 1000000000 ))
freeGB=$(( freeBytes / 1000000000 ))
usedPct=$(( (totalBytes - freeBytes) * 100 / totalBytes ))

# --- Determine percentage thresholds based on drive capacity ---
# Each tier: [critical_pct, high_pct, moderate_pct]
if (( totalGB < 300 )); then
    pctCritical=88
    pctHigh=80
    pctModerate=70
elif (( totalGB < 1000 )); then
    pctCritical=92
    pctHigh=85
    pctModerate=75
elif (( totalGB < 2000 )); then
    pctCritical=94
    pctHigh=88
    pctModerate=80
else
    pctCritical=96
    pctHigh=90
    pctModerate=85
fi

# --- Evaluate risk label ---
# Hard floor (freeGB) is checked alongside percentage for every tier.
# Either condition is sufficient to escalate — whichever fires first wins.
result="Low"

if (( freeGB < FLOOR_CRITICAL_GB )) || (( usedPct >= pctCritical )); then
    result="Critical"
elif (( freeGB < FLOOR_HIGH_GB )) || (( usedPct >= pctHigh )); then
    result="High"
elif (( freeGB < FLOOR_MODERATE_GB )) || (( usedPct >= pctModerate )); then
    result="Moderate"
fi

echo "<r>${result}</r>"