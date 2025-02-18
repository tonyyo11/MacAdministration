#!/bin/sh

PRIMLOCALE=$( defaults read /Library/Preferences/.GlobalPreferences AppleLanguages | tr -d [:space:] | cut -c3-7 )
echo "<result>$PRIMLOCALE</result>"

exit 0
