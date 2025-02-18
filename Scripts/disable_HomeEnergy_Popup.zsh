#!/bin/zsh

# Get the currently logged in user
currentUser=$( echo "show State:/Users/ConsoleUser" | scutil | awk '/Name :/ { print $3 }' )

# Get uid logged in user
uid=$(id -u "${currentUser}")

runAsUser() {  
	if [[ "${currentUser}" != "loginwindow" ]]; then
		launchctl asuser "$uid" sudo -u "${currentUser}" "$@"
	else
		echo "no user logged in"
		exit 1
	fi
}

runAsUser defaults write com.apple.Home showHomeEnergy -bool false
