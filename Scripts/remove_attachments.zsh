#!/bin/zsh
# remove_attachments.zsh — delete computer file attachments from Jamf Pro.
#
# Reads a TSV manifest produced by inventory_attachments.zsh, then issues
# one DELETE per row. Default mode is dry-run; pass --apply to actually delete.
#
# Required env vars:
#   JAMF_URL           e.g. https://jamf.example.com
#   JAMF_CLIENT_ID     OAuth2 API client ID
#   JAMF_CLIENT_SECRET OAuth2 API client secret
#
# Usage:
#   ./remove_attachments.zsh --manifest attachments.tsv             # dry-run
#   ./remove_attachments.zsh --manifest attachments.tsv --apply     # destructive
#
# Requires: curl, jq.

# Strict mode is load-bearing in a destructive script: if ensure_token() or
# any preflight check fails, we want the loop to abort immediately rather
# than continue issuing DELETE calls with bad state.
set -euo pipefail

APPLY=0
MANIFEST=""
LOG="$(date +%Y%m%d-%H%M%S)-removal.log"
SLEEP_BETWEEN=0.05

while [[ $# -gt 0 ]]; do
  case "$1" in
    --manifest) MANIFEST="$2"; shift 2 ;;
    --apply) APPLY=1; shift ;;
    --log) LOG="$2"; shift 2 ;;
    --sleep) SLEEP_BETWEEN="$2"; shift 2 ;;
    -h|--help)
      sed -n '2,18p' "$0" >&2
      exit 0
      ;;
    *) print -u2 "Unknown arg: $1"; exit 64 ;;
  esac
done

: "${MANIFEST:?--manifest is required}"
: "${JAMF_URL:?JAMF_URL is required}"
: "${JAMF_CLIENT_ID:?JAMF_CLIENT_ID is required}"
: "${JAMF_CLIENT_SECRET:?JAMF_CLIENT_SECRET is required}"

[[ -r "${MANIFEST}" ]] || { print -u2 "Cannot read manifest: ${MANIFEST}"; exit 1; }

JAMF_URL="${JAMF_URL%/}"

command -v jq >/dev/null 2>&1 || { print -u2 "jq is required"; exit 1; }

COUNT=$(( $(wc -l < "${MANIFEST}") - 1 ))
TOTAL_BYTES=$(awk -F'\t' 'NR>1 {s+=$6} END {print s+0}' "${MANIFEST}")

print -u2 "Manifest:    ${MANIFEST}"
print -u2 "Target:      ${JAMF_URL}"
if (( APPLY == 1 )); then
  print -u2 "Mode:        APPLY (destructive)"
else
  print -u2 "Mode:        dry-run"
fi
print -u2 "Attachments: ${COUNT}"
print -u2 "Total bytes: ${TOTAL_BYTES}"
print -u2 "Log file:    ${LOG}"

# ----------------------------------------------------------------------------
# confirm_deletion: last line of defense before destructive calls.
#
# Called only when --apply is set, immediately before any DELETEs are issued.
# Return 0 to proceed; non-zero to abort the run.
#
# Inputs (positional):
#   $1 = manifest path
#   $2 = attachment count
#   $3 = total bytes (summed from manifest)
#   $4 = target Jamf URL (effective JAMF_URL after trim)
#
# Design choices to combine as you see fit:
#   - Interactive phrase confirmation:
#       read "?Type DELETE-${count} to confirm: " reply
#       [[ "${reply}" == "DELETE-${count}" ]] || return 1
#   - Echo-the-target — operator retypes the server URL; defeats muscle memory:
#       read "?Type the target URL: " typed
#       [[ "${typed}" == "${jamf_url}" ]] || return 1
#   - Threshold abort — refuse if scope is larger than you expect:
#       (( count > 250 )) && { print -u2 "Refusing: count > 250"; return 1; }
#   - Env gate — require explicit override for prod:
#       [[ "${jamf_url}" == *dev* ]] || [[ -n "${OVERRIDE_PROD:-}" ]] || return 1
#
# Make this strong enough that you would not trip it by accident at 11pm
# on a Friday.
# ----------------------------------------------------------------------------
confirm_deletion() {
  local manifest="$1"
  local count="$2"
  local total_bytes="$3"
  local jamf_url="$4"

  # Gate 1: env check. Refuse prod unless OVERRIDE_PROD=1.
  local dev_pattern="${JAMF_DEV_PATTERN:-dev}"
  if [[ "${jamf_url}" != *"${dev_pattern}"* ]] && [[ -z "${OVERRIDE_PROD:-}" ]]; then
    print -u2 "Refusing: target '${jamf_url}' does not match dev pattern '*${dev_pattern}*'."
    print -u2 "Set OVERRIDE_PROD=1 to bypass (planned prod runs only)."
    return 1
  fi

  print -u2 ""
  print -u2 "About to delete ${count} attachment(s) (${total_bytes} bytes)"
  print -u2 "from manifest: ${manifest}"
  print -u2 "against:       ${jamf_url}"
  print -u2 ""

  # Gate 2: operator must retype the target URL exactly.
  local typed_url
  read -r "typed_url?Confirm target URL by retyping it: "
  if [[ "${typed_url}" != "${jamf_url}" ]]; then
    print -u2 "URL mismatch. Aborting."
    return 1
  fi

  # Gate 3: operator must type a specific phrase including the count.
  local expected="DELETE ${count} ATTACHMENTS"
  local typed_phrase
  read -r "typed_phrase?Type exactly '${expected}' to proceed: "
  if [[ "${typed_phrase}" != "${expected}" ]]; then
    print -u2 "Phrase mismatch. Aborting."
    return 1
  fi

  print -u2 "All gates passed. Proceeding."
  return 0
}

TOKEN=""
TOKEN_OBTAINED=0

get_token() {
  curl --silent --fail --show-error \
    --request POST \
    --url "${JAMF_URL}/api/v1/oauth/token" \
    --header "Content-Type: application/x-www-form-urlencoded" \
    --data-urlencode "client_id=${JAMF_CLIENT_ID}" \
    --data-urlencode "client_secret=${JAMF_CLIENT_SECRET}" \
    --data-urlencode "grant_type=client_credentials" \
  | jq -r '.access_token'
}

ensure_token() {
  local now age
  now="$(date +%s)"
  age=$(( now - TOKEN_OBTAINED ))
  if [[ -z "${TOKEN}" ]] || (( age > 900 )); then
    TOKEN="$(get_token)"
    TOKEN_OBTAINED="${now}"
    if [[ -z "${TOKEN}" || "${TOKEN}" == "null" ]]; then
      print -u2 "Failed to obtain bearer token"
      exit 1
    fi
  fi
}

delete_one() {
  local computer_id="$1"
  local attachment_id="$2"
  curl --silent --output /dev/null --write-out '%{http_code}' \
    --request DELETE \
    --header "Authorization: Bearer ${TOKEN}" \
    "${JAMF_URL}/api/v3/computers-inventory/${computer_id}/attachments/${attachment_id}"
}

process_manifest() {
  local dry="$1"
  local ok=0 fail=0 skipped=0
  local cid cname aid aname ftype size http_status

  # shellcheck disable=SC2034  # ftype/size read to consume the column; unused below
  while IFS=$'\t' read -r cid cname aid aname ftype size; do
    if [[ -z "${cid}" || -z "${aid}" ]]; then
      print -- "[SKIP] malformed row: cid='${cid}' aid='${aid}'" | tee -a "${LOG}" >&2
      skipped=$((skipped + 1))
      continue
    fi

    if (( dry )); then
      print -- "[DRY ] computer=${cid} (${cname}) attachment=${aid} name=${aname}" | tee -a "${LOG}"
      ok=$((ok + 1))
    else
      ensure_token
      http_status="$(delete_one "${cid}" "${aid}")"
      if [[ "${http_status}" =~ ^2 ]]; then
        print -- "[OK  ${http_status}] computer=${cid} (${cname}) attachment=${aid}" | tee -a "${LOG}"
        ok=$((ok + 1))
      else
        print -- "[FAIL ${http_status}] computer=${cid} (${cname}) attachment=${aid} name=${aname}" | tee -a "${LOG}" >&2
        fail=$((fail + 1))
      fi
      sleep "${SLEEP_BETWEEN}"
    fi
  done < <(tail -n +2 "${MANIFEST}")

  print -u2 "Done. ok=${ok} fail=${fail} skipped=${skipped} (log: ${LOG})"
}

if (( APPLY == 0 )); then
  print -u2 "DRY-RUN mode. No DELETEs will be issued. Pass --apply to execute."
  process_manifest 1
  exit 0
fi

if ! confirm_deletion "${MANIFEST}" "${COUNT}" "${TOTAL_BYTES}" "${JAMF_URL}"; then
  print -u2 "Aborted by confirm_deletion guard."
  exit 2
fi

process_manifest 0
