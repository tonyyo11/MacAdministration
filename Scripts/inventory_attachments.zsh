#!/bin/zsh
# inventory_attachments.zsh — enumerate all computer file attachments in Jamf Pro.
#
# Outputs a TSV manifest with columns:
#   computer_id  computer_name  attachment_id  attachment_name  file_type  size_bytes
#
# Required env vars:
#   JAMF_URL           e.g. https://jamf.example.com   (no trailing /api)
#   JAMF_CLIENT_ID     OAuth2 API client ID
#   JAMF_CLIENT_SECRET OAuth2 API client secret
#
# Usage:
#   JAMF_URL=... JAMF_CLIENT_ID=... JAMF_CLIENT_SECRET=... \
#     ./inventory_attachments.zsh --output attachments.tsv
#
# Requires: curl, jq.

# Strict mode: pipefail is load-bearing here — curl|jq pipelines must not
# silently report success when curl fails. -e/-u catch token-fetch failures
# and variable typos before they cascade into a malformed manifest.
set -euo pipefail

PAGE_SIZE=200
OUTPUT="-"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --output) OUTPUT="$2"; shift 2 ;;
    --page-size) PAGE_SIZE="$2"; shift 2 ;;
    -h|--help)
      sed -n '2,18p' "$0" >&2
      exit 0
      ;;
    *) print -u2 "Unknown arg: $1"; exit 64 ;;
  esac
done

: "${JAMF_URL:?JAMF_URL is required}"
: "${JAMF_CLIENT_ID:?JAMF_CLIENT_ID is required}"
: "${JAMF_CLIENT_SECRET:?JAMF_CLIENT_SECRET is required}"

JAMF_URL="${JAMF_URL%/}"

command -v jq >/dev/null 2>&1 || { print -u2 "jq is required"; exit 1; }

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

TOKEN="$(get_token)"
if [[ -z "${TOKEN}" || "${TOKEN}" == "null" ]]; then
  print -u2 "Failed to obtain bearer token from ${JAMF_URL}"
  exit 1
fi

fetch_inventory_page() {
  local page="$1"
  curl --silent --fail --show-error \
    --header "Authorization: Bearer ${TOKEN}" \
    --header "Accept: application/json" \
    "${JAMF_URL}/api/v3/computers-inventory?section=GENERAL&section=ATTACHMENTS&page=${page}&page-size=${PAGE_SIZE}"
}

total_count() {
  fetch_inventory_page 0 | jq -r '.totalCount'
}

emit_rows() {
  local page="$1"
  fetch_inventory_page "$page" \
    | jq -r '
        .results[]
        | . as $c
        | ($c.attachments // [])[]
        | [
            $c.id,
            ($c.general.name // ""),
            .id,
            (.name // ""),
            (.fileType // ""),
            (.sizeBytes // 0)
          ]
        | @tsv
      '
}

main() {
  local total pages tmp rows
  total="$(total_count)"
  if [[ -z "${total}" || "${total}" == "null" ]]; then
    print -u2 "Could not read totalCount from API response"
    exit 1
  fi
  pages=$(( (total + PAGE_SIZE - 1) / PAGE_SIZE ))
  print -u2 "Fleet size: ${total} computers, ${pages} page(s) at ${PAGE_SIZE}/page"

  tmp="$(mktemp)"
  trap 'rm -f "${tmp}"' EXIT

  {
    printf 'computer_id\tcomputer_name\tattachment_id\tattachment_name\tfile_type\tsize_bytes\n'
    local p
    for (( p = 0; p < pages; p++ )); do
      print -u2 "Fetching page $((p + 1))/${pages}..."
      emit_rows "$p"
    done
  } > "${tmp}"

  rows=$(( $(wc -l < "${tmp}") - 1 ))

  if [[ "${OUTPUT}" == "-" ]]; then
    cat "${tmp}"
  else
    mv "${tmp}" "${OUTPUT}"
    trap - EXIT
    print -u2 "Wrote ${OUTPUT}"
  fi

  print -u2 "Found ${rows} attachment(s) across ${total} computer(s)."
}

main "$@"
