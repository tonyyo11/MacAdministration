#!/usr/bin/env python3
"""
jamfPro_CustomPatchReport_MinVersSupport.py

Jamf Pro Patch Report (interactive, v3-compatible)

Created by: Tony Young (IT Operations Engineer)
Organization: Cloud Lake Technology, an Akima Company
Repository: https://github.com/tonyyo11/MacAdministration/tree/main
Last Updated: 2025-10-01

Description
    Generates an Excel report from Jamf Pro patch data. Supports an interactive
    or CSV-driven "baseline" mode (you set a minimum version; devices >= baseline
    count as "latest") and a classic mode (vendor-reported "latest", with
    optional active-device scaling).

Requirements
    python3 -m pip install requests pandas xlsxwriter packaging

Usage (Baseline mode with CSV)
    python3 jamfPro_CustomPatchReport_MinVersSupport.py \
        --url https://yourjamf.jamfcloud.com \
        --client-id "<id>" --client-secret "<secret>" \
        --titles-file ./all_titles_template.csv \
        --days 30 --org "YourOrg" \
        --output ./patch_report.xlsx

Usage (Baseline mode, interactive picker + per-title baseline prompts)
    python3 jamfPro_CustomPatchReport_MinVersSupport.py \
        --url https://yourjamf.jamfcloud.com  \
        --client-id "<id>" --client-secret "<secret>" \
        --interactive --days 30 --org "YourOrg" \
        --output ./patch_report.xlsx

Usage (Classic v2-style: vendor "latest" + active ratio scaling)
    python3 jamfPro_CustomPatchReport_MinVersSupport.py \
        --url https://yourjamf.jamfcloud.com  \
        --client-id "<id>" --client-secret "<secret>" \
        --days 30 --org "YourOrg" \
        --active-mode ratio \
        --output ./patch_report.xlsx

Export all titles list (optional reference)
    python3 jamfPro_CustomPatchReport_MinVersSupport.py \
        --url https://yourjamf.jamfcloud.com  \
        --client-id "<id>" --client-secret "<secret>" \
        --export-titles ./all_titles_with_ids.csv

CSV format for --titles-file (min_version optional)
    title,min_version
    Google Chrome,129.0
    Mozilla Firefox,128.0
    Adobe Acrobat Reader,23.008.20458

Notes
    • Baseline mode activates automatically when you pass --interactive, --titles-file,
        or --global-min-version. Devices are filtered by lastContactTime within --days.
    • If a CSV row’s min_version is blank, all devices for that title are compliant.
    • v2-style mode (no baseline flags) uses vendor "latest" counts and an active ratio
        from inventory; use --active-mode per_record to filter each device by --days.
    • On-prem/self-signed TLS: add --insecure (and optionally --quiet-insecure).
    • Auth: OAuth client credentials recommended; basic auth supported via --username/--password.
    • Companion generator (optional): get_all_titles_template.py creates all_titles_template.csv.

Output Sheets
    Report_Info, Baseline_Summary (baseline mode), per-title Detail tabs,
    and/or Overall_Summary.
"""

from __future__ import annotations

import argparse
import datetime as dt
import os
import re
from dataclasses import dataclass
from typing import Any, Dict, Iterable, List, Optional, Tuple
from pathlib import Path

import pandas as pd
import requests


# ---------- Version utilities ----------

def _try_import_packaging():
    try:
        from packaging import version as _pkg_version  # type: ignore
        return _pkg_version
    except Exception:
        return None

_PKG_VERSION = _try_import_packaging()

def normalize_version(s: str) -> str:
    s = (s or "").strip()
    # Drop parenthetical/build metadata like ' (18619.1.26.111.1)'
    s = re.sub(r"\(.*?\)", "", s)
    return s.strip()

def version_gte(a: str, b: str) -> bool:
    a_norm = normalize_version(a)
    b_norm = normalize_version(b)
    if not b_norm:
        return True
    if not a_norm:
        return False
    if _PKG_VERSION:
        try:
            return _PKG_VERSION.parse(a_norm) >= _PKG_VERSION.parse(b_norm)
        except Exception:
            pass  # fall back

    # Fallback: tokenize into comparable pairs (kind, value)
    # kind: 0 for numeric, 1 for alpha; ensures no int-vs-str comparisons
    def _tokens(v: str):
        parts = re.findall(r"\d+|[A-Za-z]+", v)
        toks = []
        for p in parts:
            if p.isdigit():
                toks.append((0, int(p)))
            else:
                toks.append((1, p.lower()))
        return tuple(toks)

    return _tokens(a_norm) >= _tokens(b_norm)


# ---------- Jamf API Client ----------

@dataclass
class JamfProClient:
    base_url: str
    username: Optional[str] = None
    password: Optional[str] = None
    client_id: Optional[str] = None
    client_secret: Optional[str] = None

    def __post_init__(self) -> None:
        self.session = requests.Session()
        self.token: Optional[str] = None

    @staticmethod
    def _coerce_results(data):
        """Return (results_list, total_count) from Jamf endpoints that may
        return either {results:[...], totalCount:N} or a bare list.
        """
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

    def _get_headers(self) -> Dict[str, str]:
        if not self.token:
            self._ensure_token()
        return {"Authorization": f"Bearer {self.token}", "accept": "application/json"}

    def _fetch_oauth_token(self) -> Optional[str]:
        if not (self.client_id and self.client_secret):
            return None
        url = f"{self.base_url}/api/oauth/token"
        data = {
            "grant_type": "client_credentials",
            "client_id": self.client_id,
            "client_secret": self.client_secret,
        }
        headers = {"Content-Type": "application/x-www-form-urlencoded", "accept": "application/json"}
        resp = self.session.post(url, data=data, headers=headers, timeout=45)
        if resp.status_code == 200:
            j = resp.json()
            return j.get("access_token")
        return None

    def _fetch_basic_token(self) -> Optional[str]:
        if not (self.username and self.password):
            return None
        for endpoint in ["/api/v1/auth/token", "/uapi/auth/tokens"]:
            url = f"{self.base_url}{endpoint}"
            resp = self.session.post(url, auth=(self.username, self.password), timeout=45)
            if resp.status_code == 200:
                try:
                    j = resp.json()
                except Exception:
                    j = {}
                return j.get("token") or j.get("bearerToken")
        return None

    def _ensure_token(self) -> None:
        if self.token:
            return
        token = self._fetch_oauth_token() or self._fetch_basic_token()
        if not token:
            raise RuntimeError("Failed to obtain Jamf Pro bearer token.")
        self.token = token

    def list_patch_titles(self, page_size: int = 200) -> List[Dict[str, Any]]:
        results: List[Dict[str, Any]] = []
        page = 0
        while True:
            url = f"{self.base_url}/api/v2/patch-software-title-configurations"
            params = {"page": page, "page-size": page_size}
            resp = self.session.get(url, headers=self._get_headers(), params=params, timeout=45)
            if resp.status_code != 200:
                raise RuntimeError(f"Failed to list patch titles: {resp.status_code} {resp.text}")
            data = resp.json()
            items, total_est = self._coerce_results(data)
            for it in items:
                title = (it.get("displayName") if isinstance(it, dict) else None) \
                        or (it.get("softwareTitleName") if isinstance(it, dict) else None) \
                        or (it.get("name") if isinstance(it, dict) else None) \
                        or (f"Title {it.get('id')}" if isinstance(it, dict) else str(it))
                results.append({"id": it.get("id") if isinstance(it, dict) else None, "title": title})
            total = data.get("totalCount", len(results)) if isinstance(data, dict) else total_est
            if len(results) >= total or not items:
                break
            page += 1
        results = [r for r in results if r.get("id")]
        results.sort(key=lambda x: (x["title"] or "").lower())
        return results

    def patch_summary(self, title_id: str) -> Dict[str, Any]:
        url = f"{self.base_url}/api/v2/patch-software-title-configurations/{title_id}/patch-summary"
        resp = self.session.get(url, headers=self._get_headers(), timeout=45)
        if resp.status_code != 200:
            raise RuntimeError(f"Failed to get patch summary for {title_id}: {resp.status_code} {resp.text}")
        data = resp.json()
        if isinstance(data, list):
            return data[0] if data else {}
        return data

    def patch_report(self, title_id: str, page_size: int = 200) -> List[Dict[str, Any]]:
        all_rows: List[Dict[str, Any]] = []
        page = 0
        while True:
            url = f"{self.base_url}/api/v2/patch-software-title-configurations/{title_id}/patch-report"
            params = {"page": page, "page-size": page_size}
            resp = self.session.get(url, headers=self._get_headers(), params=params, timeout=60)
            if resp.status_code != 200:
                raise RuntimeError(f"Failed to get patch report for {title_id}: {resp.status_code} {resp.text}")
            data = resp.json()
            rows, total_est = self._coerce_results(data)
            if not rows:
                break
            all_rows.extend(rows)
            total = data.get("totalCount", len(all_rows)) if isinstance(data, dict) else total_est
            if len(all_rows) >= total:
                break
            page += 1
        return all_rows

    def list_inventory(self, sections: Iterable[str]) -> Iterable[Dict[str, Any]]:
        def fetch_pages():
            page = 0
            page_size = 100
            while True:
                params = {"page": page, "page-size": page_size, "section": list(sections)}
                url = f"{self.base_url}/api/v1/computers-inventory"
                resp = self.session.get(url, headers=self._get_headers(), params=params, timeout=60)
                if resp.status_code != 200:
                    raise RuntimeError(f"Failed inventory fetch: {resp.status_code} {resp.text}")
                data = resp.json()
                results = data.get("results", []) if isinstance(data, dict) else (data if isinstance(data, list) else [])
                for item in results:
                    yield item
                total = data.get("totalCount", 0) if isinstance(data, dict) else len(results)
                if (page + 1) * page_size >= total or not results:
                    break
                page += 1
        return fetch_pages()


# ---------- Helpers ----------

def calculate_active_ratio(inventory: Iterable[Dict[str, Any]], days: int) -> Tuple[int, int, float]:
    total = 0
    active = 0
    now = dt.datetime.now(dt.timezone.utc)
    for item in inventory:
        total += 1
        try:
            last_contact = item.get("general", {}).get("lastContactTime", "")
            if not last_contact:
                continue
            last_dt = dt.datetime.fromisoformat(last_contact.replace("Z", "+00:00"))
            if last_dt.tzinfo is None:
                last_dt = last_dt.replace(tzinfo=dt.timezone.utc)
            if (now - last_dt).days <= days:
                active += 1
        except Exception:
            pass
    ratio = (active / total) if total else 0.0
    return total, active, ratio

def parse_last_contact(s: str) -> Optional[dt.datetime]:
    if not s:
        return None
    try:
        return dt.datetime.fromisoformat(s.replace("Z", "+00:00"))
    except Exception:
        for fmt in ("%Y-%m-%dT%H:%M:%S%z", "%Y-%m-%dT%H:%M:%S"):
            try:
                return dt.datetime.strptime(s, fmt)
            except Exception:
                continue
    return None

def filter_active_rows(rows: List[Dict[str, Any]], days: int) -> List[Dict[str, Any]]:
    if days <= 0:
        return rows
    now = dt.datetime.now(dt.timezone.utc)
    out: List[Dict[str, Any]] = []
    for r in rows:
        lct = parse_last_contact(r.get("lastContactTime", ""))
        if not lct:
            continue
        if lct.tzinfo is None:
            lct = lct.replace(tzinfo=dt.timezone.utc)
        if (now - lct).days <= days:
            out.append(r)
    return out


# ---------- Title selection & baselines ----------

@dataclass
class TitleSelection:
    id: str
    title: str
    min_version: str = ""

def read_titles_file(path: str) -> List[TitleSelection]:
    p = Path(path)
    if not p.exists():
        raise FileNotFoundError(f"Titles file not found: {path}")
    if p.suffix.lower() == ".csv":
        df = pd.read_csv(p)
        if "title" not in df.columns:
            raise ValueError("CSV must include 'title' column; optional 'min_version' column.")
        sels: List[TitleSelection] = []
        for _, row in df.iterrows():
            sels.append(TitleSelection(id="", title=str(row["title"]).strip(), min_version=str(row.get("min_version", "") or "").strip()))
        return sels
    else:
        lines = [ln.strip() for ln in p.read_text(encoding="utf-8").splitlines() if ln.strip()]
        return [TitleSelection(id="", title=ln, min_version="") for ln in lines]

def interactive_select_titles(all_titles: List[Dict[str, Any]]) -> List[TitleSelection]:
    print("\nInteractive Title Picker")
    print("------------------------")
    print("Type search text to filter, or type: all | done | ?")
    print("Select by numbers/ranges (e.g., 1,2,5-8).")
    filtered = all_titles
    selected: List[TitleSelection] = []

    def show(items: List[Dict[str, Any]]):
        for i, t in enumerate(items[:50], 1):
            print(f"{i:3}. {t['title']}")
        if len(items) > 50:
            print(f"... ({len(items)-50} more; refine search)")

    while True:
        print(f"\n--- {len(filtered)} titles ---")
        show(filtered)
        cmd = input("Search / numbers / command: ").strip()
        if not cmd:
            continue
        if cmd.lower() in {"?", "help"}:
            print("Enter search text, or 'all', or 'done', or numbers like '1,3-6'.")
            continue
        if cmd.lower() == "done":
            break
        if cmd.lower() == "all":
            for t in filtered:
                selected.append(TitleSelection(id=t["id"], title=t["title"], min_version=""))
            break
        if re.fullmatch(r"[0-9,\-\s]+", cmd):
            picks: List[int] = []
            for part in cmd.split(","):
                part = part.strip()
                if "-" in part:
                    a, b = part.split("-", 1)
                    try:
                        a_i = int(a); b_i = int(b)
                    except ValueError:
                        continue
                    picks.extend(list(range(min(a_i, b_i), max(a_i, b_i) + 1)))
                else:
                    try:
                        picks.append(int(part))
                    except ValueError:
                        continue
            for idx in picks:
                if 1 <= idx <= len(filtered):
                    t = filtered[idx - 1]
                    selected.append(TitleSelection(id=t["id"], title=t["title"]))
            print(f"Added {len(picks)} selections.")
        else:
            q = cmd.lower()
            filtered = [t for t in all_titles if q in t["title"].lower()]

    # Dedup and prompt for baselines
    seen = set(); deduped: List[TitleSelection] = []
    for s in selected:
        if s.id not in seen:
            seen.add(s.id); deduped.append(s)
    print("\nEnter minimum version for each (press Enter to skip).")
    for s in deduped:
        mv = input(f"Baseline for '{s.title}': ").strip()
        s.min_version = mv
    return deduped

def resolve_selections_from_file(client: JamfProClient, path: str) -> List[TitleSelection]:
    file_sels = read_titles_file(path)
    if not file_sels:
        return []
    all_titles = client.list_patch_titles()
    name_to_id = {t["title"].lower(): t["id"] for t in all_titles}
    resolved: List[TitleSelection] = []
    for s in file_sels:
        tid = name_to_id.get(s.title.lower())
        if not tid:
            print(f"WARNING: Title not found in Jamf Pro: '{s.title}' (skipping)")
            continue
        resolved.append(TitleSelection(id=tid, title=s.title, min_version=s.min_version))
    return resolved


# ---------- Reporting ----------

def build_v2_overall_dataframe(patch_summaries: List[Dict[str, Any]], active_ratio: float) -> pd.DataFrame:
    rows = []
    for s in patch_summaries:
        title = s.get("title") or s.get("name")
        title_id = str(s.get("softwareTitleId") or s.get("id"))
        latest = s.get("latestVersion")
        release_date = s.get("releaseDate") or s.get("releaseDateTime") or ""
        try:
            if release_date:
                release_date = str(release_date)[:10]
        except Exception:
            pass
        hosts_patched = int(s.get("hostsOnLatestVersion", 0))
        hosts_out = int(s.get("hostsOutOfDate", 0))
        total = hosts_patched + hosts_out
        completion = round((hosts_patched / total) * 100.0, 2) if total else 0.0

        adj_patched = int(round(hosts_patched * active_ratio))
        adj_out = int(round(hosts_out * active_ratio))
        adj_total = adj_patched + adj_out
        adj_completion = round((adj_patched / adj_total) * 100.0, 2) if adj_total else 0.0

        rows.append({
            "Title": title,
            "Title ID": title_id,
            "Latest Version": latest,
            "Release Date": release_date,
            "Hosts (All)": total,
            "Patched (All)": hosts_patched,
            "Out-of-date (All)": hosts_out,
            "Completion % (All)": completion,
            "Patched (Active-scaled)": adj_patched,
            "Out-of-date (Active-scaled)": adj_out,
            "Completion % (Active-scaled)": adj_completion,
        })
    return pd.DataFrame(rows)

def build_baseline_summary(title: TitleSelection, rows_all: List[Dict[str, Any]], days: int) -> Tuple[Dict[str, Any], pd.DataFrame]:
    rows_active = filter_active_rows(rows_all, days) if days > 0 else rows_all
    compliant = 0
    detail_rows: List[Dict[str, Any]] = []
    for r in rows_active:
        v = (r.get("version") or "").strip()
        is_ok = version_gte(v, title.min_version)
        if is_ok:
            compliant += 1
        detail_rows.append({
            "Computer Name": r.get("computerName"),
            "Username": r.get("username"),
            "Device ID": r.get("deviceId"),
            "OS Version": r.get("operatingSystemVersion"),
            "Last Contact Time": r.get("lastContactTime"),
            "Installed Version": v,
            "Compliant (>= baseline)": "Yes" if is_ok else "No",
        })
    active = len(rows_active)
    summary = {
        "Title": title.title,
        "Baseline (>=)": title.min_version or "(none)",
        "Active Devices": active,
        "Compliant (>= baseline)": compliant,
        "Non-Compliant": max(active - compliant, 0),
        "Compliance %": round((compliant / active * 100.0), 2) if active else 0.0,
    }
    df_detail = pd.DataFrame(detail_rows)
    return summary, df_detail


# ---------- Excel writer ----------

def write_excel(
    output_path: str,
    org_name: Optional[str],
    report_date: str,
    active_days: int,
    overall_df: Optional[pd.DataFrame] = None,
    top_df: Optional[pd.DataFrame] = None,
    per_title_detail: Optional[Dict[str, pd.DataFrame]] = None,
    baseline_summary_rows: Optional[List[Dict[str, Any]]] = None,
) -> None:
    with pd.ExcelWriter(output_path, engine="xlsxwriter") as xw:
        header_df = pd.DataFrame([
            {"Organization": org_name or "", "Report Date": report_date, "Active Window (days)": active_days}
        ])
        header_df.to_excel(xw, index=False, sheet_name="Report_Info")

        if overall_df is not None and not overall_df.empty:
            overall_df.to_excel(xw, index=False, sheet_name="Overall_Summary")

        if top_df is not None and not top_df.empty:
            top_df.to_excel(xw, index=False, sheet_name="Top_Titles")

        if baseline_summary_rows:
            baseline_df = pd.DataFrame(baseline_summary_rows)
            baseline_df.to_excel(xw, index=False, sheet_name="Baseline_Summary")

        if per_title_detail:
            for sheet_name, df in per_title_detail.items():
                safe = re.sub(r"[^A-Za-z0-9 _-]", "_", sheet_name)[:31]
                df.to_excel(xw, index=False, sheet_name=safe or "Detail")


# ---------- Main ----------

def main(argv: Optional[List[str]] = None) -> int:
    ap = argparse.ArgumentParser(description="Jamf Pro Patch Report (v2-compatible + interactive baselines)")
    # v2 flags
    ap.add_argument("--url", required=True, help="Base URL of Jamf Pro instance")
    ap.add_argument("--username", default=None, help="Jamf Pro API username (if not using client credentials)")
    ap.add_argument("--password", default=None, help="Jamf Pro API password (if not using client credentials)")
    ap.add_argument("--client-id", dest="client_id", default=None, help="Jamf Pro API client ID (OAuth)")
    ap.add_argument("--client-secret", dest="client_secret", default=None, help="Jamf Pro API client secret (OAuth)")
    ap.add_argument("--output", required=True, help="Path to output Excel file")
    ap.add_argument("--days", type=int, default=30, help="Days threshold for 'active' devices")
    ap.add_argument("--top-list", dest="top_list", default=None, help="File of patch title names/IDs to highlight")
    ap.add_argument("--export-titles", dest="export_titles", default=None, help="Path to save full list of patch titles & IDs (CSV)")
    ap.add_argument("--org", dest="org", default=None, help="Organization name for headers")
    # new flags
    ap.add_argument("--interactive", action="store_true", help="Pick titles interactively and set per-title baselines")
    ap.add_argument("--titles-file", dest="titles_file", default=None, help="TXT/CSV list of titles; CSV may include min_version")
    ap.add_argument("--global-min-version", dest="global_min_version", default="", help="Baseline applied to all titles unless overridden")
    ap.add_argument("--active-mode", choices=["ratio", "per_record"], default="ratio",
                    help="How to compute 'active' devices. v2 default: ratio. per_record uses each device's lastContactTime.")
    ap.add_argument("--insecure", action="store_true", help="Disable TLS verification (self-signed Jamf certs)")
    ap.add_argument("--quiet-insecure", action="store_true", help="Suppress urllib3 InsecureRequestWarning when using --insecure")

    args = ap.parse_args(argv)

    client = JamfProClient(
        base_url=args.url.rstrip("/"),
        username=args.username,
        password=args.password,
        client_id=args.client_id,
        client_secret=args.client_secret,
    )
    if args.insecure:
        client.session.verify = False
        if args.quiet_insecure:
            try:
                import urllib3
                urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)
            except Exception:
                pass

    # Export titles list if requested
    all_titles = client.list_patch_titles()
    if args.export_titles:
        pd.DataFrame(all_titles).to_csv(args.export_titles, index=False)
        print(f"Wrote patch titles list: {args.export_titles}")

    # Decide mode
    use_baseline_mode = bool(args.interactive or args.titles_file or args.global_min_version)

    # Build selections (baseline mode only)
    selections: List[TitleSelection] = []
    if use_baseline_mode:
        if args.titles_file:
            selections = resolve_selections_from_file(client, args.titles_file)
            if not selections:
                print("No valid titles resolved from --titles-file.")
                return 1
        elif args.interactive:
            selections = interactive_select_titles(all_titles)
            if not selections:
                print("No titles selected in interactive mode.")
                return 2
        else:
            selections = [TitleSelection(id=t["id"], title=t["title"], min_version="") for t in all_titles]

        if args.global_min_version:
            for s in selections:
                if not (s.min_version and s.min_version.strip()):
                    s.min_version = args.global_min_version.strip()

    report_date = dt.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    per_title_detail: Dict[str, pd.DataFrame] = {}
    baseline_summary_rows: List[Dict[str, Any]] = []
    overall_df = None
    top_df = None

    if use_baseline_mode:
        # Baseline path
        for s in selections:
            print(f"Fetching patch report for: {s.title}")
            rows = client.patch_report(s.id)
            summary, detail_df = build_baseline_summary(s, rows, args.days)
            baseline_summary_rows.append(summary)
            per_title_detail[s.title] = detail_df
    else:
        # v2-style path
        print("Fetching inventory to compute active ratio...")
        inv = client.list_inventory(sections=["GENERAL"])
        total, active, ratio = calculate_active_ratio(inv, args.days)
        print(f"Inventory totals: total={total} active={active} ratio={ratio:.4f}")

        # patch summaries for all titles
        summaries: List[Dict[str, Any]] = []
        for t in all_titles:
            try:
                s = client.patch_summary(t["id"])
                s["title"] = t["title"]
                s["id"] = t["id"]
                summaries.append(s)
            except Exception as e:
                print(f"WARNING: summary failed for {t['title']}: {e}")

        overall_df = build_v2_overall_dataframe(summaries, ratio)

        if args.top_list:
            names = []
            with open(args.top_list, "r", encoding="utf-8") as f:
                for ln in f:
                    ln = ln.strip()
                    if ln:
                        names.append(ln.lower())
            def is_pick(row: pd.Series) -> bool:
                return (str(row["Title"]).lower() in names) or (str(row["Title ID"]).lower() in names)
            top_df = overall_df[overall_df.apply(is_pick, axis=1)].copy()

        # Per-title detail tabs (limit default to first 50)
        for t in all_titles[:50]:
            try:
                rows = client.patch_report(t["id"])
                if args.active_mode == "per_record":
                    rows = filter_active_rows(rows, args.days)
                detail_rows = []
                for r in rows:
                    detail_rows.append({
                        "Computer Name": r.get("computerName"),
                        "Username": r.get("username"),
                        "Device ID": r.get("deviceId"),
                        "OS Version": r.get("operatingSystemVersion"),
                        "Last Contact Time": r.get("lastContactTime"),
                        "Installed Version": r.get("version"),
                    })
                per_title_detail[t["title"]] = pd.DataFrame(detail_rows)
            except Exception as e:
                print(f"WARNING: detail fetch failed for {t['title']}: {e}")

    # Write Excel
    os.makedirs(os.path.dirname(os.path.abspath(args.output)), exist_ok=True)
    write_excel(
        output_path=args.output,
        org_name=args.org,
        report_date=report_date,
        active_days=args.days,
        overall_df=overall_df,
        top_df=top_df,
        per_title_detail=per_title_detail if per_title_detail else None,
        baseline_summary_rows=baseline_summary_rows if baseline_summary_rows else None,
    )
    print(f"Report written: {os.path.abspath(args.output)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
    