#!/bin/sh
# Adobe Reader
/usr/libexec/PlistBuddy -c "Add :DC dict" /Library/Preferences/com.adobe.Reader.plist
/usr/libexec/PlistBuddy -c "Add :DC:FeatureLockdown dict" /Library/Preferences/com.adobe.Reader.plist
/usr/libexec/PlistBuddy -c "Add :DC:FeatureLockdown:bEnableGentech bool false" /Library/Preferences/com.adobe.Reader.plist
# Adobe Acrobat Pro
/usr/libexec/PlistBuddy -c "Add :DC dict" /Library/Preferences/com.adobe.Acrobat.Pro.plist
/usr/libexec/PlistBuddy -c "Add :DC:FeatureLockdown dict" /Library/Preferences/com.adobe.Acrobat.Pro.plist
/usr/libexec/PlistBuddy -c "Add :DC:FeatureLockdown:bEnableGentech bool false" /Library/Preferences/com.adobe.Acrobat.Pro.plist
