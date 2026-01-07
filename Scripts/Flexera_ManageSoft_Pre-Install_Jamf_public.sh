#!/bin/bash
#
# -----------------------------------------------------------------------------
# Script Name:   Flexera_ManageSoft_Pre-Install_Jamf.sh
# Version:       1.0
#
# Author:        Tony Young
# Project:       Patch Notes and Progress
# GitHub:        https://github.com/tonyyo11/MacAdministration
# Website:       https://tonyyo11.github.io
#
# Description:
# This script is intended to run as a **Jamf Pro pre-install script** for the
# Flexera ManageSoft (FlexNet Inventory Agent) macOS installer.
#
# Its primary purpose is to ensure that all required bootstrap artifacts are
# staged *before* the Flexera package installer executes its internal
# configuration logic.
#
# Specifically, this script:
#   - Creates the ManageSoft response file (answer file) in /private/var/tmp
#   - Stages the TLS/SSL CA certificate bundle in the locations expected by
#     Flexera's installer:
#       • /private/var/tmp/mgsft_rollout_cert
#       • /private/var/opt/managesoft/etc/ssl/cert.pem
#   - Applies correct ownership and permissions for non-interactive execution
#
# Why this matters:
# The Flexera installer runs its own configure.sh script during installation.
# If the response file and certificate bundle are not present *before* the
# package installs, the installer may:
#   - Fall back to interactive (GUI) configuration
#   - Trigger macOS TCC / Automation prompts
#   - Fail to configure download/upload servers
#   - Leave the agent in a non-functional state
#
# This script is designed to prevent all GUI interaction and ensure a fully
# silent, deterministic installation when deployed via Jamf Pro.
#
# Intended Use:
#   - Jamf Pro policy
#   - Execution priority: **Before** package installation
#   - Non-interactive, root-only execution
#
# Requirements:
#   - macOS
#   - Jamf Pro
#   - Flexera ManageSoft / FlexNet Inventory Agent package
#
# Notes:
#   - All environment-specific values (URLs, domains, certificates) should be
#     customized by the deploying organization.
#   - This script is safe to publish and reuse; no organization-specific data
#     is embedded by default.
#
# Disclaimer:
# This script is provided "as-is" with no warranties or guarantees.
# Always test in a non-production environment before deployment.
#
# -----------------------------------------------------------------------------

set -euo pipefail
PATH="/usr/bin:/bin:/usr/sbin:/sbin"

LOG="/private/var/log/flexera_managesoft_preinstall.log"
RESP="/private/var/tmp/mgsft_rollout_response"
CERT_STAGING="/private/var/tmp/mgsft_rollout_cert"
CERT_PEM="/private/var/opt/managesoft/etc/ssl/cert.pem"

#
# Jamf Script Parameters (optional)
#   $4 = Beacon host (e.g., beacon.example.com)
#   $5 = Beacon port (e.g., 443)
#   $6 = Pre-staged cert bundle path (optional)
#   $7 = Pre-staged cert bundle path (optional)
#   $8 = Reporting domain (optional; e.g., example.com)
#   NOTE: If you do not use Jamf parameters, edit the defaults below.
#

# Where you may optionally pre-stage a CA bundle via Jamf "Files and Processes" or packaging
BEACON_HOST="${4:-beacon.example.com}"
BEACON_PORT="${5:-443}"
PRESTAGED_CERT_1="${6:-/Library/Application Support/YourOrg/Flexera/mgsft_rollout_cert}"
PRESTAGED_CERT_2="${7:-/Library/Application Support/YourOrg/Flexera/cert.pem}"
REPORTING_DOMAIN="${8:-example.com}"
BEACON_FQDN="${BEACON_HOST}:${BEACON_PORT}"

log() {
  /bin/echo "[FlexeraPreInstall] $(/bin/date '+%Y-%m-%d %H:%M:%S') $*" | /usr/bin/tee -a "$LOG" >/dev/null
}

die() {
  log "ERROR: $*"
  exit 1
}

require_root() {
  [ "$(id -u)" -eq 0 ] || die "Must run as root (Jamf runs scripts as root)."
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

fetch_ca_chain_from_beacon() {
  # Build a CA bundle (typically intermediate + root) from the server-presented chain.
  # We prefer cert #2 and #3 (intermediate + root) based on prior troubleshooting.
  local out_pem="$1"
  local tmpdir
  tmpdir=$(/usr/bin/mktemp -d "/tmp/flexera-preinstall.XXXXXX")

  log "Attempting to fetch cert chain from $BEACON_FQDN via openssl s_client..."

  # Retry a few times in case DNS/network is not ready
  local attempt
  for attempt in 1 2 3 4 5; do
    rm -f "$tmpdir"/beacon-cert-*.pem

    # Use a short timeout by wrapping with /usr/bin/timeout if available; otherwise rely on openssl defaults.
    if /usr/bin/command -v timeout >/dev/null 2>&1; then
      /bin/echo | /usr/bin/timeout 15 /usr/bin/openssl s_client -showcerts \
        -connect "$BEACON_FQDN" \
        -servername "$BEACON_HOST" 2>/dev/null \
        | /usr/bin/awk '/BEGIN CERTIFICATE/{i++; fn=sprintf("%s/beacon-cert-%d.pem","'$tmpdir'",i)} { if (fn!="") print > fn }'
    else
      /bin/echo | /usr/bin/openssl s_client -showcerts \
        -connect "$BEACON_FQDN" \
        -servername "$BEACON_HOST" 2>/dev/null \
        | /usr/bin/awk '/BEGIN CERTIFICATE/{i++; fn=sprintf("%s/beacon-cert-%d.pem","'$tmpdir'",i)} { if (fn!="") print > fn }'
    fi

    if [ -s "$tmpdir/beacon-cert-2.pem" ] && [ -s "$tmpdir/beacon-cert-3.pem" ]; then
      /bin/cat "$tmpdir/beacon-cert-2.pem" "$tmpdir/beacon-cert-3.pem" > "$out_pem"
      if validate_pem_bundle "$out_pem"; then
        log "Fetched CA bundle from beacon successfully (attempt $attempt)."
        rm -rf "$tmpdir"
        return 0
      fi
    fi

    log "Fetch attempt $attempt did not produce a valid CA bundle yet; retrying in 2s..."
    /bin/sleep 2
  done

  rm -rf "$tmpdir"
  return 1
}

stage_ca_bundle() {
  log "Staging certificate chain (required pre-install)..."

  # Ensure directories exist
  /bin/mkdir -p /private/var/tmp
  /bin/mkdir -p "$(/usr/bin/dirname "$CERT_PEM")"

  # 1) If Flexera cert was pre-staged by packaging/Jamf, prefer it
  if [ -f "$PRESTAGED_CERT_1" ] && validate_pem_bundle "$PRESTAGED_CERT_1"; then
    log "Using pre-staged cert bundle: $PRESTAGED_CERT_1"
    log "Pre-staged cert bundle selected."
    /bin/cp -f "$PRESTAGED_CERT_1" "$CERT_STAGING"
  elif [ -f "$PRESTAGED_CERT_2" ] && validate_pem_bundle "$PRESTAGED_CERT_2"; then
    log "Using pre-staged cert bundle: $PRESTAGED_CERT_2"
    log "Pre-staged cert bundle selected."
    /bin/cp -f "$PRESTAGED_CERT_2" "$CERT_STAGING"
  # 2) If already staged on disk from a prior run, keep it
  elif [ -f "$CERT_STAGING" ] && validate_pem_bundle "$CERT_STAGING"; then
    log "Existing staged cert bundle looks valid; reusing: $CERT_STAGING"
    log "Existing staged cert bundle reused."
  # 3) Otherwise fetch from the beacon's presented chain
  else
    if ! fetch_ca_chain_from_beacon "$CERT_STAGING"; then
      die "Could not obtain a valid CA bundle. Provide a pre-staged PEM at '$PRESTAGED_CERT_1' or '$PRESTAGED_CERT_2', or ensure $BEACON_FQDN is reachable."
    fi
  fi

  # Permissions for staging file
  /usr/sbin/chown root:wheel "$CERT_STAGING"
  /bin/chmod 644 "$CERT_STAGING"

  # Copy to the live expected location *before install*
  /bin/cp -f "$CERT_STAGING" "$CERT_PEM"
  /usr/sbin/chown root:wheel "$CERT_PEM"
  /bin/chmod 644 "$CERT_PEM"

  local count
  count=$(/usr/bin/awk 'BEGIN{n=0}/BEGIN CERTIFICATE/{n++}END{print n}' "$CERT_PEM")
  log "CA bundle staged: $CERT_STAGING and $CERT_PEM (cert_count=$count, size=$(/usr/bin/wc -c < "$CERT_PEM") bytes)."
  log "Staged certs in place with standard permissions."

  # Optional audit: log subject/issuer for each cert in the bundle
  local tmpdir idx pemfile
  tmpdir=$(/usr/bin/mktemp -d "/tmp/flexera-ca-audit.XXXXXX")
  /usr/bin/awk '
    /BEGIN CERTIFICATE/ {i++; out=sprintf("%s/cert-%d.pem","'"$tmpdir"'",i)}
    out {print > out}
    /END CERTIFICATE/ {out=""; print "" > sprintf("%s/cert-%d.pem","'"$tmpdir"'",i)}
  ' "$CERT_PEM"

  idx=1
  for pemfile in "$tmpdir"/cert-*.pem; do
    [ -s "$pemfile" ] || continue
    log "CA bundle cert #$idx: $(/usr/bin/openssl x509 -noout -subject -issuer -in "$pemfile" 2>/dev/null | /usr/bin/tr '\n' ' ')"
    idx=$((idx + 1))
  done
  /bin/rm -rf "$tmpdir"
}

stage_response_file() {
  log "Staging response file at: $RESP"
  /bin/mkdir -p /private/var/tmp

  # Write the *entire* response file (including comments) exactly as provided.
  /bin/cat > "$RESP" <<EOF
# The initial download location(s) for the installation.
# For example, http://myhost.mydomain.com/ManageSoftDL/
# Refer to the documentation for further details.
MGSFT_BOOTSTRAP_DOWNLOAD=https://${BEACON_HOST}/ManageSoftDL/

# The initial reporting location(s) for the installation.
# For example, http://myhost.mydomain.com/ManageSoftRL/
# Refer to the documentation for further details.
MGSFT_BOOTSTRAP_UPLOAD=https://${BEACON_HOST}/ManageSoftRL/

# For subnets using IPv6, uncomment to cause the inventory agent
# to prefer IPv6 addresses when both formats are returned. 
# Fails over to IPv4 addresses when IPv6 is not available.
# The default behavior when this setting is not specified
# uses the IP version of the first address returned by the DNS and OS.
PREFERIPVERSION=ipv4

# The initial proxy configuration.  Uncomment these to enable proxy configuration.
# Note that setting values of NONE disables this feature.
# MGSFT_HTTP_PROXY=http://webproxy.local:3128
# MGSFT_HTTPS_PROXY=https://webproxy.local:3129
# MGSFT_NO_PROXY=internal1.local,internal2.local

# Check the HTTPS server certificate's existence, name, validity period,
# and issuance by a trusted certificate authority (CA).  This is enabled
# by default and can be disabled with false.
# MGSFT_HTTPS_CHECKSERVERCERTIFICATE=false

# Provide the client side certificate and private key for mutual TLS 
# authentication support.
# This is disabled by default and can be enabled with true.
# MGSFT_HTTPS_ADDCLIENTCERTIFICATEANDKEY=false

# Check that the HTTPS server certificate has not been revoked. This is
# enabled by default and can be disabled with false.
MGSFT_HTTPS_CHECKCERTIFICATEREVOCATION=false

# Prioritize the method of checking for revocation of the HTTPS server 
# certificate. (OCSPSTAPLING can be added if supported by your HTTP server.)
# MGSFT_HTTPS_PRIORITIZEREVOCATIONCHECKS=CRL

# The setting below controls the caching of HTTPS server certificate checking.
# The default value is shown (it takes effect when no setting is specified). 
# Lifetime is in seconds. See documentation for more information.
# MGSFT_HTTPS_SSLCRLCACHELIFETIME=64800

# The run policy flag determines if policy will run after installation.
#    "1" or "Yes" will run policy after install
#    "0" or "No" will not run policy
MGSFT_RUNPOLICY=1

# Dummy domain name for reporting by UNIX-like devices
MGSFT_DOMAIN_NAME=${REPORTING_DOMAIN}

# Configure the agent to run as least privileged, default is to install full privilege.
# Enabling this configuration requires that the local sudoers be configured to allow the agent
# service account (flxrasvc) be allowed to launch specific tools as root to operate
# correctly.
# FLEXERA_LEAST_PRIVILEGE_AGENT=1
EOF

  /usr/sbin/chown root:wheel "$RESP"
  /bin/chmod 644 "$RESP"

  # Basic sanity check
  if ! /usr/bin/grep -q "^\s*MGSFT_BOOTSTRAP_DOWNLOAD=" "$RESP"; then
    die "Response file does not contain MGSFT_BOOTSTRAP_DOWNLOAD. Verify the payload content."
  fi

  log "Response file staged successfully (size=$(/usr/bin/wc -c < "$RESP") bytes)."
  log "NOTE: The Flexera installer may consume and delete this file during install; that is expected."
}

main() {
  require_root
  log "Starting pre-install staging..."

  if [ "$BEACON_HOST" = "beacon.example.com" ] || [ "$REPORTING_DOMAIN" = "example.com" ]; then
    die "Placeholder values detected. Set Jamf parameters ($4/$5/$8) or edit BEACON_HOST/REPORTING_DOMAIN in the script."
  fi

  stage_response_file
  stage_ca_bundle

  log "Pre-install staging complete. Proceed with Flexera ManageSoft pkg installation."
}

main "$@"
