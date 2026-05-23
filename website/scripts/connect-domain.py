#!/usr/bin/env python3
"""
Idempotent Cloudflare DNS connector for pismenka.com -> Cloudflare Pages.

Usage:
    export CLOUDFLARE_API_TOKEN="..."   # token must have Zone -> DNS -> Edit on pismenka.com
    python3 website/scripts/connect-domain.py

What it does:
1. Verifies the API token can reach the `pismenka.com` zone.
2. Re-attaches `pismenka.com` and `www.pismenka.com` to the `pismenka` Pages project (idempotent).
3. Creates or updates two proxied CNAME records pointing at `pismenka.pages.dev`,
   removing any conflicting A/AAAA records on those names.
4. Polls the Pages domain status until both go `active` (TLS issuance).
5. Issues HTTPS HEAD requests to confirm the live site is responding.

Re-run any time. Cloudflare rate-limits are gentle for these endpoints.
"""

import json
import os
import sys
import time
import urllib.request
import urllib.error

ZONE = "pismenka.com"
PAGES_PROJECT = "pismenka"
PAGES_TARGET = "pismenka.pages.dev"
HOSTNAMES = [ZONE, f"www.{ZONE}"]

API_BASE = "https://api.cloudflare.com/client/v4"


def env_token() -> str:
    token = os.environ.get("CLOUDFLARE_API_TOKEN", "").strip()
    if not token:
        sys.exit(
            "CLOUDFLARE_API_TOKEN is not set. "
            "Create a scoped token (Edit zone DNS for pismenka.com) "
            "and export it before re-running."
        )
    return token


def cf_request(method: str, path: str, token: str, body=None):
    url = f"{API_BASE}{path}"
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(url, data=data, method=method)
    req.add_header("Authorization", f"Bearer {token}")
    req.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            return json.load(resp)
    except urllib.error.HTTPError as e:
        body = e.read().decode("utf-8", errors="replace")
        try:
            parsed = json.loads(body)
        except Exception:
            parsed = {"raw": body}
        return {"_http_error": e.code, "body": parsed}


def verify_zone(token: str) -> str:
    print("1) Verifying Cloudflare zone access via API token...")
    r = cf_request("GET", f"/zones?name={ZONE}", token)
    if "_http_error" in r or not r.get("success"):
        sys.exit(f"   token cannot read zone {ZONE}: {r}")
    zones = r.get("result") or []
    if not zones:
        sys.exit(f"   zone {ZONE} not found on this account")
    zone_id = zones[0]["id"]
    print(f"   zone {ZONE} ({zone_id}) reachable")
    return zone_id


def ensure_pages_domains(token: str):
    print("2) Ensuring Pages custom domains are attached...")
    accounts = cf_request("GET", "/accounts", token)
    if not accounts.get("success") or not accounts.get("result"):
        print("   token cannot list accounts; skipping Pages re-attach (idempotent)")
        return
    account_id = accounts["result"][0]["id"]
    existing = cf_request(
        "GET",
        f"/accounts/{account_id}/pages/projects/{PAGES_PROJECT}/domains",
        token,
    )
    have = set()
    if existing.get("success"):
        for d in existing.get("result", []):
            have.add(d.get("name"))
    for h in HOSTNAMES:
        if h in have:
            print(f"  - {h} already attached")
            continue
        r = cf_request(
            "POST",
            f"/accounts/{account_id}/pages/projects/{PAGES_PROJECT}/domains",
            token,
            {"name": h},
        )
        if r.get("success"):
            print(f"  - {h} attached")
        else:
            print(f"  - {h} attach skipped: {r}")


def ensure_dns(token: str, zone_id: str):
    print("3) Writing DNS records (proxied CNAME -> pismenka.pages.dev)...")
    for name in HOSTNAMES:
        r = cf_request("GET", f"/zones/{zone_id}/dns_records?name={name}", token)
        records = r.get("result", []) if r.get("success") else []
        for rec in records:
            if rec.get("type") in ("A", "AAAA"):
                cf_request("DELETE", f"/zones/{zone_id}/dns_records/{rec['id']}", token)
                print(f"  - removed conflicting {rec['type']} on {name}")

        cname = next((rec for rec in records if rec.get("type") == "CNAME"), None)
        body = {
            "type": "CNAME",
            "name": name,
            "content": PAGES_TARGET,
            "ttl": 1,
            "proxied": True,
        }
        if cname:
            r = cf_request(
                "PUT",
                f"/zones/{zone_id}/dns_records/{cname['id']}",
                token,
                body,
            )
            verb = "updated"
        else:
            r = cf_request(
                "POST",
                f"/zones/{zone_id}/dns_records",
                token,
                body,
            )
            verb = "created"
        if r.get("success"):
            print(f"  - {verb} CNAME {name} -> {PAGES_TARGET} (proxied)")
        else:
            print(f"  - failed to {verb} CNAME {name}: {r}")


def poll_pages_status(token: str):
    print("4) Waiting for Cloudflare to issue certs and mark domains active...")
    accounts = cf_request("GET", "/accounts", token)
    if not accounts.get("success") or not accounts.get("result"):
        print("   token cannot list accounts; skipping status poll")
        return
    account_id = accounts["result"][0]["id"]
    deadline = time.time() + 240
    while time.time() < deadline:
        existing = cf_request(
            "GET",
            f"/accounts/{account_id}/pages/projects/{PAGES_PROJECT}/domains",
            token,
        )
        statuses = {}
        if existing.get("success"):
            for d in existing.get("result", []):
                if d.get("name") in HOSTNAMES:
                    statuses[d["name"]] = d.get("status", "?")
        print(f"  status: {statuses}")
        if statuses and all(s == "active" for s in statuses.values()):
            return
        time.sleep(8)
    print("   still pending after 4 min — re-run later if needed")


def http_check():
    print("5) HTTP check:")
    paths = ["/", "/", "/support/", "/privacy/"]
    for host, path in zip(HOSTNAMES + [HOSTNAMES[0], HOSTNAMES[0]], paths):
        url = f"https://{host}{path}"
        try:
            req = urllib.request.Request(url, method="HEAD")
            with urllib.request.urlopen(req, timeout=10) as resp:
                print(f"   {url} -> {resp.status}")
        except Exception as e:
            print(f"   {url} -> err {e}")


def main():
    token = env_token()
    zone_id = verify_zone(token)
    ensure_pages_domains(token)
    ensure_dns(token, zone_id)
    poll_pages_status(token)
    http_check()
    print()
    print("Done. If pismenka.com is not reachable yet, wait 1-2 minutes for cert issuance and re-run.")


if __name__ == "__main__":
    main()
