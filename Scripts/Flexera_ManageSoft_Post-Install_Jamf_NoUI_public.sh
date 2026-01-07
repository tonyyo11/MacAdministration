#!/bin/bash
#
# -----------------------------------------------------------------------------
# Script Name:   Flexera_ManageSoft_Post-Install_Jamf_NoUI.sh
# Version:       1.0
#
# Author:        Tony Young
# Project:       Patch Notes and Progress
# GitHub:        https://github.com/tonyyo11/MacAdministration
# Website:       https://tonyyo11.github.io
#
# Description:
# This script is intended to run as a **Jamf Pro post-install script** following
# installation of the Flexera ManageSoft (FlexNet Inventory Agent) package on
# macOS.
#
# This script performs non-interactive, Jamf-safe post-install configuration
# tasks that cannot be reliably handled by the Flexera installer alone.
#
# Specifically, this script:
#   - Verifies the ManageSoft installation is present
#   - Ensures the SSL/TLS CA certificate bundle is available and referenced
#   - Applies required configuration settings using supported Flexera tools
#   - Enables optional agent components (such as usage tracking)
#   - Reloads Flexera LaunchDaemons in a root-only context
#   - Optionally triggers initial configuration and inventory activity
#
# Design Goals:
#   - **Zero GUI interaction**
#   - **No AppleScript or System Events usage**
#   - **No TCC / Privacy prompts**
#   - Safe for execution under Jamf Pro without a logged-in user
#
# Why this script exists:
# While Flexera provides a response-file-based installer, certain settings and
# behaviors (for example, usage agent enablement or post-install validation)
# are more reliably applied after installation using supported command-line
# tooling.
#
# This script complements the pre-install staging process and finalizes agent
# readiness in a controlled, auditable way.
#
# Intended Use:
#   - Jamf Pro policy
#   - Execution priority: **After** package installation
#   - Non-interactive, root-only execution
#
# Requirements:
#   - macOS
#   - Jamf Pro
#   - Flexera ManageSoft / FlexNet Inventory Agent installed
#
# Notes:
#   - This script assumes the response file and certificates were staged
#     correctly during the pre-install phase.
#   - Environment-specific values should be customized as needed.
#   - Designed for public sharing and community reuse.
#
# Disclaimer:
# This script is provided "as-is" with no warranties or guarantees.
# Always test in a non-production environment before deployment.
#
# -----------------------------------------------------------------------------

set -euo pipefail
PATH="/usr/bin:/bin:/usr/sbin:/sbin:/opt/managesoft/bin"

LOG="/private/var/log/flexera_managesoft_postinstall.log"
LOCK="/private/var/run/flexera_managesoft_postinstall.lock"

MS_OPT="/opt/managesoft"
MS_BIN="/opt/managesoft/bin"
MS_LIBEXEC="/opt/managesoft/libexec"

#
# Jamf Script Parameters (optional)
#   $4 = CERT_PEM override (default: /private/var/opt/managesoft/etc/ssl/cert.pem)
#   $5 = CERT_STAGING override (default: /private/var/tmp/mgsft_rollout_cert)
#   NOTE: If you do not use Jamf parameters, defaults are used.
#

CFG="/private/var/opt/managesoft/etc/config.ini"
SSL_DIR="/private/var/opt/managesoft/etc/ssl"
CERT_PEM="${4:-$SSL_DIR/cert.pem}"
CERT_STAGING="${5:-/private/var/tmp/mgsft_rollout_cert}"
AGENT_CONFIG_JSON="/private/var/opt/managesoft/config/agent_config.json"

CONFIG_RETRY_COUNT=6
CONFIG_RETRY_SLEEP=10
KICKSTART_RETRY_SLEEP=10

log() {
  /bin/echo "[FlexeraPostInstall] $(/bin/date '+%Y-%m-%d %H:%M:%S') $*" | /usr/bin/tee -a "$LOG" >/dev/null
}

log_file_stat() {
  local path="$1" label="$2"
  if [ -e "$path" ]; then
    log "$label present."
  else
    log "$label missing."
  fi
}

die() {
  log "ERROR: $*"
  exit 1
}

cleanup() {
  rm -f "$LOCK" >/dev/null 2>&1 || true
}
trap cleanup EXIT

# --- Guardrails ---
[ "$(id -u)" -eq 0 ] || die "Must run as root (Jamf runs scripts as root)."

# Lock prevents two Jamf policies (or a user + Jamf) from running this at the same time.
# If you ever need to override for troubleshooting: `sudo FLEXERA_NOLOCK=1 <script>`
if [ "${FLEXERA_NOLOCK:-0}" != "1" ]; then
  if [ -e "$LOCK" ]; then
    die "Lock file exists ($LOCK). Another run may still be in progress. Set FLEXERA_NOLOCK=1 to override."
  fi
  /usr/bin/touch "$LOCK"
  /bin/chmod 644 "$LOCK" || true
fi

log "Starting Flexera ManageSoft post-install (no-UI)."

[ -d "$MS_OPT" ] || die "ManageSoft not installed at $MS_OPT"
[ -x "$MS_BIN/flxconfig" ] || die "Missing $MS_BIN/flxconfig"
[ -f "$CFG" ] || die "Missing config.ini at $CFG"

if [ "$CERT_PEM" = "CHANGE_ME" ] || [ "$CERT_STAGING" = "CHANGE_ME" ]; then
  die "Placeholder values detected. Set Jamf parameters ($4/$5) or edit CERT_PEM/CERT_STAGING in the script."
fi

# --- Helper: set or add a key inside a specific INI section (backslash section names supported) ---
set_ini_kv() {
  local section="$1" key="$2" value="$3" file="$4"

  # If section doesn't exist, append it.
  if ! /usr/bin/grep -q "^\[$section\]$" "$file"; then
    log "Section [$section] not found; appending."
    /usr/bin/printf "\n[%s]\n%s=%s\n" "$section" "$key" "$value" >> "$file"
    return 0
  fi

  # If key exists inside section, replace it; else insert it right after the section header.
  /usr/bin/perl -0777 -i -pe '
    my ($sec,$k,$v)=@ARGV;
    my $re = qr/^\[\Q$sec\E\]\s*$(.*?)(?=^\[|\z)/ms;
    if ($ARGV[0] =~ $re) {
      my $block = $&;
      my $body  = $1;
      if ($body =~ m/^\Q$k\E\s*=/m) {
        $body =~ s/^\Q$k\E\s*=.*$/$k=$v/m;
      } else {
        $body = "$k=$v\n" . $body;
      }
      $ARGV[0] =~ s/$re/"[$sec]\n".$body/ems;
    }
  ' "$section" "$key" "$value" "$file"
}

validate_pem_bundle() {
  local pem="$1"

  [ -s "$pem" ] || return 1

  # Must contain at least one PEM cert block
  local c
  c=$(/usr/bin/awk 'BEGIN{n=0}/BEGIN CERTIFICATE/{n++}END{print n}' "$pem" 2>/dev/null || /bin/echo 0)
  [ "$c" -ge 1 ] || return 1

  # Must be parseable (at least first cert)
  /usr/bin/awk 'BEGIN{p=0}
    /BEGIN CERTIFICATE/{p=1}
    p{print}
    /END CERTIFICATE/{exit}
  ' "$pem" | /usr/bin/openssl x509 -noout >/dev/null 2>&1 || return 1

  return 0
}

has_settings_sections() {
  local prefix="$1" file="$2"

  /usr/bin/grep -Fq "[$prefix" "$file"
}

json_has_settings() {
  local key="$1" file="$2"
  /usr/bin/grep -q "\"$key\"" "$file" && /usr/bin/grep -q "\"ServerID\"" "$file"
}

# --- 1) Ensure UserInteractionLevel is Quiet (avoid prompts even if something runs interactively) ---
log "Ensuring UserInteractionLevel=Quiet in [ManageSoft\Common]"
set_ini_kv "ManageSoft\\Common" "UserInteractionLevel" "Quiet" "$CFG"

# --- 2) Verify the pre-staged CA bundle exists (no creation here) ---
log "Verifying pre-staged CA bundle at $CERT_PEM"
mkdir -p "$SSL_DIR"
log_file_stat "$CERT_PEM" "cert.pem"
log_file_stat "$CERT_STAGING" "staged_cert"

if ! validate_pem_bundle "$CERT_PEM"; then
  if [ -f "$CERT_STAGING" ]; then
    die "CA bundle at $CERT_PEM is missing/invalid. Pre-staged file exists at $CERT_STAGING but post-install does not modify certs."
  fi
  die "CA bundle missing/invalid at $CERT_PEM. Ensure pre-install staged /private/var/tmp/mgsft_rollout_cert and copied it before pkg install."
fi

CERT_COUNT=$(/usr/bin/awk 'BEGIN{c=0}/BEGIN CERTIFICATE/{c++}END{print c}' "$CERT_PEM")
log "CA bundle present (cert_count=$CERT_COUNT, bytes=$(/usr/bin/wc -c < "$CERT_PEM"))."

# --- 3) Point ManageSoft to the CA bundle ---
log "Setting SSLCACertificateFile=$CERT_PEM in [ManageSoft\Common]"
set_ini_kv "ManageSoft\\Common" "SSLCACertificateFile" "$CERT_PEM" "$CFG"

# --- 4) Enable Usage Agent (per Flexera docs: Disabled=False) ---
log "Enabling Usage Agent (Disabled=False) in [ManageSoft\\Usage Agent\\CurrentVersion]"
set_ini_kv "ManageSoft\\Usage Agent\\CurrentVersion" "Disabled" "False" "$CFG"

# Tighten config.ini perms (vendor often uses 600). Keeping root-only is fine.
chown root:wheel "$CFG"
chmod 600 "$CFG"
log_file_stat "$CFG" "config.ini"

# --- 5) Kickstart daemons (root, non-GUI) ---
log "Kickstarting LaunchDaemons..."
/bin/launchctl kickstart -k system/com.flexerasoftware.ndtask >/dev/null 2>&1 || true
/bin/launchctl kickstart -k system/com.flexerasoftware.mgsusageag >/dev/null 2>&1 || true

# --- 6) Force config pull + immediate inventory + upload ---
log "Forcing configuration download: flxconfig --disable-upgrade"
log_file_stat "$AGENT_CONFIG_JSON" "agent_config.json (pre)"
if "$MS_BIN/flxconfig" --disable-upgrade >/dev/null 2>&1; then
  log "flxconfig completed successfully."
else
  log "flxconfig exited with code $?."
fi
log_file_stat "$AGENT_CONFIG_JSON" "agent_config.json (post)"

log "Validating configured download/upload servers in config.ini"
attempt=1
while [ "$attempt" -le "$CONFIG_RETRY_COUNT" ]; do
  if [ -r "$CFG" ] \
    && has_settings_sections "ManageSoft\\\\Common\\\\DownloadSettings" "$CFG" \
    && has_settings_sections "ManageSoft\\\\Common\\\\UploadSettings" "$CFG"; then
    log "Download/upload servers are configured (attempt $attempt)."
    log "DownloadSettings and UploadSettings detected in config.ini."
    break
  fi

  log "Download/upload servers not configured yet (attempt $attempt/$CONFIG_RETRY_COUNT); retrying in ${CONFIG_RETRY_SLEEP}s..."
  /bin/sleep "$CONFIG_RETRY_SLEEP"
  if "$MS_BIN/flxconfig" --disable-upgrade >/dev/null 2>&1; then
    log "flxconfig completed successfully."
  else
    log "flxconfig exited with code $?."
  fi
  attempt=$((attempt + 1))
done

if [ ! -r "$CFG" ]; then
  log "WARNING: config.ini is not readable; checking $AGENT_CONFIG_JSON instead."
fi

if [ -r "$CFG" ] && has_settings_sections "ManageSoft\\\\Common\\\\DownloadSettings" "$CFG"; then
  log "DownloadSettings found in config.ini."
elif [ -r "$AGENT_CONFIG_JSON" ]; then
  if json_has_settings "DownloadSettings" "$AGENT_CONFIG_JSON"; then
    log "DownloadSettings found in agent_config.json."
  else
    die "No download servers configured after retries (config.ini and agent_config.json). Agent cannot pull policy."
  fi
else
  die "No download servers configured after retries (config.ini unreadable and agent_config.json missing)."
fi

if [ -r "$CFG" ] && has_settings_sections "ManageSoft\\\\Common\\\\UploadSettings" "$CFG"; then
  log "UploadSettings found in config.ini."
elif [ -r "$AGENT_CONFIG_JSON" ]; then
  if json_has_settings "UploadSettings" "$AGENT_CONFIG_JSON"; then
    log "UploadSettings found in agent_config.json."
  else
    die "No upload servers configured after retries (config.ini and agent_config.json). Agent cannot upload inventory."
  fi
else
  die "No upload servers configured after retries (config.ini unreadable and agent_config.json missing)."
fi

log "Waiting ${KICKSTART_RETRY_SLEEP}s before second daemon kickstart..."
/bin/sleep "$KICKSTART_RETRY_SLEEP"
log "Kickstarting LaunchDaemons again after config pull..."
/bin/launchctl kickstart -k system/com.flexerasoftware.ndtask >/dev/null 2>&1 || true
/bin/launchctl kickstart -k system/com.flexerasoftware.mgsusageag >/dev/null 2>&1 || true

log "Running inventory now: ndtrack"
if "$MS_BIN/ndtrack" >/dev/null 2>&1; then
  log "ndtrack completed successfully."
else
  log "ndtrack exited with code $?."
fi

log "Uploading inventory now: ndupload"
if "$MS_BIN/ndupload" >/dev/null 2>&1; then
  log "ndupload completed successfully."
else
  log "ndupload exited with code $?."
fi

log "Post-install complete."
log "Next checks:"
log "  - tail -n 120 /private/var/opt/managesoft/log/agent_configuration.log"
log "  - tail -n 120 /private/var/opt/managesoft/log/mgs1-tracker.log (or tracker.log)"
log "  - tail -n 120 /private/var/opt/managesoft/log/uploader.log"
exit 0
