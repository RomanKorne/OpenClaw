#!/usr/bin/env python3
"""
Notion -> Airtable sync utility (hardened, one-shot).
Uses only Python standard library.
"""
import argparse
import json
import os
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

NOTION_TOKEN = os.environ.get("NOTION_API_KEY")
AIRTABLE_TOKEN = os.environ.get("AIRTABLE_API_KEY")
DEFAULT_BASE_ID = os.environ.get("AIRTABLE_BASE_ID", "appB2VMy9GXqq0I8O")
DEFAULT_TABLE = os.environ.get("AIRTABLE_TABLE", "Memories")


class ApiError(RuntimeError):
    pass


def parse_args():
    p = argparse.ArgumentParser(description="Sync Notion pages into Airtable table.")
    p.add_argument("--base-id", default=DEFAULT_BASE_ID, help="Airtable base id (app...)")
    p.add_argument("--table", default=DEFAULT_TABLE, help="Airtable table name")
    p.add_argument("--batch-size", type=int, default=10, help="Airtable create batch size (max 10)")
    p.add_argument("--max-pages", type=int, default=200, help="Max Notion pages to read")
    p.add_argument("--dry-run", action="store_true", help="Print what would be created without writing")
    p.add_argument("--verbose", action="store_true", help="Verbose logs")
    return p.parse_args()


def require_env():
    missing = []
    if not NOTION_TOKEN:
        missing.append("NOTION_API_KEY")
    if not AIRTABLE_TOKEN:
        missing.append("AIRTABLE_API_KEY")
    if missing:
        raise ApiError("Missing required env: " + ", ".join(missing))


def call_json(url, method="GET", headers=None, data=None, retries=4, timeout=30):
    headers = headers or {}
    payload = json.dumps(data).encode("utf-8") if data is not None else None

    for attempt in range(retries + 1):
        req = urllib.request.Request(url, method=method, data=payload)
        for k, v in headers.items():
            req.add_header(k, v)
        try:
            with urllib.request.urlopen(req, timeout=timeout) as f:
                return json.load(f)
        except urllib.error.HTTPError as e:
            body = e.read().decode("utf-8", errors="replace")
            retry_after = e.headers.get("Retry-After")
            if e.code in (429, 500, 502, 503, 504) and attempt < retries:
                delay = int(retry_after) if retry_after and retry_after.isdigit() else 2 ** attempt
                time.sleep(delay)
                continue
            raise ApiError(f"HTTP {e.code} {url}: {body[:400]}")
        except urllib.error.URLError as e:
            if attempt < retries:
                time.sleep(2 ** attempt)
                continue
            raise ApiError(f"Network error {url}: {e}") from e


def notion_headers():
    return {
        "Authorization": f"Bearer {NOTION_TOKEN}",
        "Notion-Version": "2022-06-28",
        "Content-Type": "application/json",
    }


def airtable_headers():
    return {
        "Authorization": f"Bearer {AIRTABLE_TOKEN}",
        "Content-Type": "application/json",
    }


def notion_search_all(max_pages=200):
    url = "https://api.notion.com/v1/search"
    results = []
    cursor = None
    while len(results) < max_pages:
        body = {"page_size": min(100, max_pages - len(results))}
        if cursor:
            body["start_cursor"] = cursor
        data = call_json(url, method="POST", headers=notion_headers(), data=body)
        items = data.get("results", [])
        results.extend(items)
        if not data.get("has_more"):
            break
        cursor = data.get("next_cursor")
        if not cursor:
            break
    return results


def airtable_list_titles(base_id, table):
    table_q = urllib.parse.quote(table, safe="")
    url = f"https://api.airtable.com/v0/{base_id}/{table_q}?pageSize=100&fields%5B%5D=Title"
    titles = set()
    while True:
        data = call_json(url, headers={"Authorization": f"Bearer {AIRTABLE_TOKEN}"})
        for rec in data.get("records", []):
            t = (rec.get("fields", {}).get("Title") or "").strip().lower()
            if t:
                titles.add(t)
        offset = data.get("offset")
        if not offset:
            break
        url = f"https://api.airtable.com/v0/{base_id}/{table_q}?pageSize=100&offset={urllib.parse.quote(offset, safe='')}&fields%5B%5D=Title"
    return titles


def extract_title(page):
    props = page.get("properties", {})
    for _, val in props.items():
        if isinstance(val, dict) and val.get("type") == "title":
            arr = val.get("title") or []
            text = "".join(chunk.get("plain_text", "") for chunk in arr).strip()
            if text:
                return text
    return (page.get("url") or page.get("id") or "").strip()


def to_airtable_records(pages, existing_titles):
    out = []
    seen = set()
    for p in pages:
        if p.get("object") != "page":
            continue
        title = extract_title(p).strip()
        key = title.lower()
        if not title or key in existing_titles or key in seen:
            continue
        seen.add(key)
        link = p.get("url") or f"https://www.notion.so/{p.get('id')}"
        out.append({"fields": {"Title": title, "Notion Link": link}})
    return out


def airtable_add_batch(base_id, table, records):
    table_q = urllib.parse.quote(table, safe="")
    url = f"https://api.airtable.com/v0/{base_id}/{table_q}"
    return call_json(url, method="POST", headers=airtable_headers(), data={"records": records, "typecast": True})


def main():
    args = parse_args()
    require_env()

    if not args.base_id.startswith("app"):
        raise ApiError(f"Invalid AIRTABLE base id '{args.base_id}'. Expected format like 'app...'.")
    if args.batch_size < 1 or args.batch_size > 10:
        raise ApiError("--batch-size must be between 1 and 10")

    pages = notion_search_all(max_pages=args.max_pages)
    existing = airtable_list_titles(args.base_id, args.table)
    to_add = to_airtable_records(pages, existing)

    summary = {
        "notion_pages_scanned": len(pages),
        "airtable_existing_titles": len(existing),
        "new_records": len(to_add),
        "dry_run": args.dry_run,
        "base_id": args.base_id,
        "table": args.table,
    }
    print(json.dumps(summary, ensure_ascii=False))

    if not to_add:
        return 0

    if args.dry_run:
        print(json.dumps({"sample_new_titles": [r["fields"]["Title"] for r in to_add[:10]]}, ensure_ascii=False))
        return 0

    created = 0
    for i in range(0, len(to_add), args.batch_size):
        chunk = to_add[i : i + args.batch_size]
        resp = airtable_add_batch(args.base_id, args.table, chunk)
        created += len(resp.get("records", []))
        if args.verbose:
            print(json.dumps({"batch_start": i, "created": len(resp.get("records", []))}, ensure_ascii=False))
    print(json.dumps({"created_total": created}, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except ApiError as e:
        print(f"ERROR: {e}", file=sys.stderr)
        raise SystemExit(2)
