"""Sync declaratively-held API keys into Wizarr's database.

Wizarr only mints API keys through its admin UI (random token, shown once,
sha256 stored in ``api_key``). This script makes a key declarative instead:
the raw key lives in a file the operator controls (a sops secret), and the
matching ``api_key`` row is reconciled on every service start — created if
absent, re-hashed if the file's value changed, re-activated if disabled.
Keys created in the UI are left alone.

Usage: sync-api-keys.py <database.db> <name>=<keyfile> [<name>=<keyfile> ...]
"""

from __future__ import annotations

import hashlib
import sqlite3
import sys
from datetime import datetime, timezone


def sync(db_path: str, keys: dict[str, str]) -> int:
    con = sqlite3.connect(db_path)
    con.execute("PRAGMA foreign_keys = ON")
    changes = 0

    have_table = con.execute(
        "SELECT 1 FROM sqlite_master WHERE type='table' AND name='api_key'"
    ).fetchone()
    if not have_table:
        print("api_key table absent; skipping sync", file=sys.stderr)
        return 0

    # Rows carry a NOT NULL creator; use the first admin. Before setup has
    # created one there is nobody to own the key, so wait for a later start.
    admin = con.execute("SELECT id FROM admin_account ORDER BY id LIMIT 1").fetchone()
    if admin is None:
        print("no admin account yet; skipping api key sync", file=sys.stderr)
        return 0
    admin_id = admin[0]

    now = datetime.now(timezone.utc).replace(tzinfo=None).isoformat(sep=" ")

    for name, path in keys.items():
        with open(path) as fh:
            raw = fh.read().strip()
        if not raw:
            print(f"api key '{name}': key file is empty; skipping", file=sys.stderr)
            continue
        key_hash = hashlib.sha256(raw.encode("utf-8")).hexdigest()

        row = con.execute(
            "SELECT id, key_hash, is_active FROM api_key WHERE name = ?", (name,)
        ).fetchone()
        if row is None:
            con.execute(
                "INSERT INTO api_key (name, key_hash, created_at, created_by_id, "
                "is_active) VALUES (?, ?, ?, ?, 1)",
                (name, key_hash, now, admin_id),
            )
            changes += 1
        elif row[1] != key_hash or not row[2]:
            con.execute(
                "UPDATE api_key SET key_hash = ?, is_active = 1 WHERE id = ?",
                (key_hash, row[0]),
            )
            changes += 1

    con.commit()
    con.close()
    return changes


def main() -> None:
    db_path, specs = sys.argv[1], sys.argv[2:]
    keys: dict[str, str] = {}
    for spec in specs:
        name, _, path = spec.partition("=")
        if not name or not path:
            sys.exit(f"bad key spec {spec!r}: want <name>=<keyfile>")
        keys[name] = path

    changed = sync(db_path, keys)
    if changed:
        print(f"api keys: {changed} row(s) reconciled")
    else:
        print("api keys: already in sync")


if __name__ == "__main__":
    main()
