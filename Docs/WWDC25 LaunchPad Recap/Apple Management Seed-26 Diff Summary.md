Github Branch online. https://github.com/apple/device-management/tree/seed-26

– NEW: declarative/declarations/configurations/audio-accessory.settings.yaml
–– supportedOS: iOS
–– description: The declaration to configure audio accessory settings.
– NEW: declarative/declarations/configurations/packages.yaml
–– supportedOS: macOS
–– description: The declaration to install a package.
– NEW: declarative/declarations/configurations/safari.bookmarks.yaml
–– supportedOS: iOS, macOS, visionOS
–– description: The declaration to configure managed bookmarks in Safari.
– NEW: declarative/declarations/configurations/safari.settings.yaml
–– supportedOS: iOS, macOS, visionOS
–– description: The declaration to configure Safari settings.
– UPDATED: declarative/declarations/configurations/softwareupdate.enforcement.specific.yaml
–– added supportedOS: visionOS
– UPDATED: declarative/declarations/configurations/softwareupdate.settings.yaml
–– added supportedOS: macOS
– UPDATED: declarative/status/app.managed.list.yaml
–– added supportedOS: visionOS
– NEW: declarative/status/package.list.yaml
–– supportedOS: macOS
–– description: The client's declarative packages.
– UPDATED: declarative/status/softwareupdate.device-id.yaml
–– added supportedOS: visionOS
– UPDATED: declarative/status/softwareupdate.failure-reason.yaml
–– added supportedOS: visionOS
– UPDATED: declarative/status/softwareupdate.install-reason.yaml
–– added supportedOS: visionOS
– UPDATED: declarative/status/softwareupdate.install-state.yaml
–– added supportedOS: visionOS
– UPDATED: declarative/status/softwareupdate.pending-version.yaml
–– added supportedOS: visionOS
– NEW: mdm/checkin/returntoservice.yaml
–– supportedOS: iOS, visionOS
–– description: Gets the return-to-service configuration from the server.
– UPDATED: /mdm/commands/device.erase.yaml
–– added ReturnToService supportedOS: visionOS
–– NEW Bootstraptoken supportedOS: iOS, visionOS
– UPDATED: /mdm/commands/information.device.yaml
–– lots of removals for deprecated iOS based keys
–– UPDATED OSUpdateSettings | deprecated | macOS 
– UPDATED: /mdm/commands/system.update.available.yaml
–– deprecated AvailableOSUpdates for supportedOS: iOS, macOS, tvOS
– UPDATED: /mdm/commands/system.update.scan.yaml
–– deprecated ScheduleOSUpdateScan for supportedOS: macOS
– UPDATED: /mdm/commands/system.update.schedule.yaml
–– deprecated ScheduleOSUpdate for supportedOS: iOS, macOS, tvOS
– UPDATED: /mdm/commands/system.update.status.yaml
–– deprecated OSUpdateStatus for supportedOS: iOS, macOS, tvOS
– NEW: /mdm/errors/psso.required.yaml
–– supportedOS: macOS
–– description: An error response that indicates Platform SSO is required.
– UPDATED: /mdm/profiles/com.apple.SoftwareUpdate.yaml
– deprecated for macOS 26
– UPDATED: /mdm/profiles/com.apple.applicationaccess.yaml
–– allowSafariHistoryClearing | iOS, macOS, visionOS
–– allowSafariPrivateBrowsing | iOS, macOS, VisionOS
–– deniedICCIDsForiMessageFaceTime | iOS
–– enforcedSoftwareUpdateDelay | deprecated
–– enforcedSoftwareUpdateMajorOSDeferredInstallDelay | deprecated
–– enforcedSoftwareUpdateMinorOSDeferredInstallDelay | deprecated
–– enforcedSoftwareUpdateNonOSDeferredInstallDelay | deprecated
–– forceDelayedMajorSoftwareUpdates | deprecated
–– forceDelayedSoftwareUpdates | deprecated
– UPDATES /mdm/profiles/com.apple.dnsSettings.managed.yaml
–– NEW AllowFailover for supportedOS: iOS, macOS, tvOS, visionOS
– UPDATED: mdm/profiles/com.apple.extensiblesso.yaml
–– EnableCreateFirstUserDuringSetup | macOS
–– NewUserAuthenticationMethods | macOS
–– AccessKeyReaderGroupIdentifier | macOS
–– AccessKeyTerminalIdentityUUID | macOS 
–– AllowAccessKeyExpressMode | macOS
–– SynchronizeProfilePicture | macOS
– UPDATED: mdm/profiles/com.apple.familycontrols.contentfilter.yaml
–– Whitelist/Blacklist based keys are deprecated and replaced with updated  allowlist/denylist
– UPDATED: mdm/profiles/com.apple.relay.managed.yaml
–– NEW UIToggleEnabled for supportedOS: iOS, macOS, tvOS, visionOS
–– NEW AllowDNSFailover for supportedOS: iOS, macOS, tvOS, visionOS
– UPDATED mdm/profiles/com.apple.vpn.managed.yaml
–– NEW AllowPostQuantumKeyExchangeFallback for supportedOS: iOS, macOS, tvOS, visionOS, watchOS
–– NEW EnforceStrictAlgorithmSelection for supportedOS: iOS, macOS, tvOS, visionOS, watchOS
–– NEW PostQuantumKeyExchangeMethods for supportedOS: iOS, macOS, tvOS, visionOS, watchOS
– UPDATED mdm/profiles/com.apple.vpn.managed.yaml
–– NEW FilterURLS for supportedOS: iOS, macOS
–– NEW URLFilterParameters for supportedOS: iOS, macOS
 
– UPDATED: mdm/profiles/com.apple.wifi.managed.yaml
–– NEW AllowJoinBeforeFirstUnlock for supportedOS: visionOS
– UPDATED: other/skipkeys.yaml
–– NEW AdditionalPrivacySettings for supportedOS: macOS
–– NEW Multitasking for supportedOS: iOS
–– NEW OSShowcase for supportedOS: iOS
–– NEW Tips for supportedOS: visionOS
–– NEW UnlockWithWatch for supportedOS: macOS
–– General added support for visionOS
