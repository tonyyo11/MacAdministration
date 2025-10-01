#!/usr/bin/env python3
"""
get_all_titles_template.py

Companion utility that logs into Jamf Pro and exports *all* Patch Titles to a
minimal CSV template you can hand-edit for reporting filters.

Default CSV columns:
    title,min_version

Optional flags can include `title_id` and `current_version` as extra columns.

Requirements:
  python3 -m pip install requests
"""

import argparse
import csv
from dataclasses import dataclass
from typing import Any, Dict, List, Optional, Tuple
from pathlib import Path

import requests


# ---------------- Jamf Client ----------------

@dataclass
class JamfProClient:
    base_url: str
    client_id: Optional[str] = None
    client_secret: Optional[str] = None
    username: Optional[str] = None
    password: Optional[str] = None
    verify_tls: bool = True

    def __post_init__(self) -> None:
        self.session = requests.Session()
        self.session.verify = self.verify_tls
        self.token: Optional[str] = None

    def _headers(self) -> Dict[str, str]:
        if not self.token:
            self._ensure_token()
        return {"Authorization": f"Bearer {self.token}", "accept": "application/json"}

    def _ensure_token(self) -> None:
        # Try OAuth client credentials first
        if self.client_id and self.client_secret:
            url = f"{self.base_url}/api/oauth/token"
            data = {
                "grant_type": "client_credentials",
                "client_id": self.client_id,
                "client_secret": self.client_secret,
            }
            headers = {"Content-Type": "application/x-www-form-urlencoded", "accept": "application/json"}
            resp = self.session.post(url, data=data, headers=headers, timeout=45)
            if resp.status_code == 200:
                self.token = resp.json().get("access_token")
                if self.token:
                    return
        # Fallback to basic
        if self.username and self.password:
            for endpoint in ("/api/v1/auth/token", "/uapi/auth/tokens"):
                url = f"{self.base_url}{endpoint}"
                resp = self.session.post(url, auth=(self.username, self.password), timeout=45)
                if resp.status_code == 200:
                    try:
                        j = resp.json()
                    except Exception:
                        j = {}
                    self.token = j.get("token") or j.get("bearerToken")
                    if self.token:
                        return
        raise RuntimeError("Failed to obtain Jamf Pro bearer token (check credentials & permissions).")

    @staticmethod
    def _coerce_results(data: Any) -> Tuple[List[Dict[str, Any]], int]:
        """Return (results_list, total_count) for list vs {results, totalCount} shapes."""
        if isinstance(data, dict):
            results = data.get("results")
            if isinstance(results, list):
                return results, int(data.get("totalCount", len(results)))
            for key in ("titles", "items", "data"):
                if isinstance(data.get(key), list):
                    arr = data[key]
                    return arr, len(arr)
            return [], 0
        elif isinstance(data, list):
            return data, len(data)
        return [], 0

    def list_patch_titles(self, page_size: int = 200) -> List[Dict[str, Any]]:
        titles: List[Dict[str, Any]] = []
        page = 0
        while True:
            url = f"{self.base_url}/api/v2/patch-software-title-configurations"
            params = {"page": page, "page-size": page_size}
            resp = self.session.get(url, headers=self._headers(), params=params, timeout=45)
            if resp.status_code != 200:
                raise RuntimeError(f"Failed to list patch titles: {resp.status_code} {resp.text}")
            data = resp.json()
            items, total_est = self._coerce_results(data)
            for it in items:
                titles.append({
                    "id": it.get("id"),
                    "title": it.get("displayName") or it.get("softwareTitleName") or it.get("name") or f"Title {it.get('id')}",
                })
            total = data.get("totalCount", len(titles)) if isinstance(data, dict) else total_est
            if len(titles) >= total or not items:
                break
            page += 1
        titles = [t for t in titles if t.get("id")]
        titles.sort(key=lambda x: (x["title"] or "").lower())
        return titles

    def patch_summary(self, title_id: str) -> Dict[str, Any]:
        url = f"{self.base_url}/api/v2/patch-software-title-configurations/{title_id}/patch-summary"
        resp = self.session.get(url, headers=self._headers(), timeout=60)
        if resp.status_code != 200:
            return {}
        data = resp.json()
        return data[0] if isinstance(data, list) and data else data


# ---------------- Main ----------------

def main() -> int:
    ap = argparse.ArgumentParser(description="Export all Jamf Pro Patch Titles to a CSV template.")
    ap.add_argument("--url", required=True, help="Jamf Pro base URL (e.g., https://tenant.jamfcloud.com)")
    ap.add_argument("--client-id", dest="client_id", default=None, help="Jamf Pro API client ID (OAuth)")
    ap.add_argument("--client-secret", dest="client_secret", default=None, help="Jamf Pro API client secret (OAuth)")
    ap.add_argument("--username", default=None, help="Jamf Pro API username (if not using OAuth)")
    ap.add_argument("--password", default=None, help="Jamf Pro API password (if not using OAuth)")
    ap.add_argument("--output", default="all_titles_template.csv", help="Output CSV path (default: all_titles_template.csv)")
    ap.add_argument("--include-ids", action="store_true", help="Include title_id column in the CSV (for reference)")
    ap.add_argument("--include-current-version", action="store_true", help="Include current_version column (slower)")
    ap.add_argument("--insecure", action="store_true", help="Disable TLS verification for self-signed certs (on-prem)")
    ap.add_argument("--quiet-insecure", action="store_true", help="Suppress urllib3 InsecureRequestWarning when using --insecure")

    args = ap.parse_args()

    verify_tls = not args.insecure
    client = JamfProClient(
        base_url=args.url.rstrip("/"),
        client_id=args.client_id,
        client_secret=args.client_secret,
        username=args.username,
        password=args.password,
        verify_tls=verify_tls,
    )

    if args.insecure and args.quiet_insecure:
        try:
            import urllib3
            urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)
        except Exception:
            pass

    titles = client.list_patch_titles()

    # Decide columns
    fieldnames = ["title", "min_version"]
    if args.include_ids:
        fieldnames.insert(1, "title_id")
    if args.include_current_version:
        fieldnames.append("current_version")

    # Write CSV
    out_path = Path(args.output).expanduser()
    out_path.parent.mkdir(parents=True, exist_ok=True)
    with out_path.open("w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader()
        for t in titles:
            row = {"title": t["title"], "min_version": ""}
            if args.include_ids:
                row["title_id"] = t["id"]
            if args.include_current_version:
                try:
                    s = client.patch_summary(str(t["id"]))
                    row["current_version"] = s.get("latestVersion", "")
                except Exception:
                    row["current_version"] = ""
            writer.writerow(row)

    print(f"Wrote {out_path} with {len(titles)} titles.")
    if args.include_current_version:
        print("Note: current_version required extra API calls; consider omitting for faster export.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())