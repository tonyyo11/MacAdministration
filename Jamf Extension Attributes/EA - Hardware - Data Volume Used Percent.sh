#!/bin/zsh
# EA: EA - Hardware - Data Volume Used Percent
# Description: Data volume disk utilization as integer (no % sign)
# EA Type: Integer
# Possible values: 0–100

result=$(df /System/Volumes/Data | awk 'NR==2{gsub(/%/,"",$5); print $5}')

echo "<result>${result}</result>"