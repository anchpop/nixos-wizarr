"""Sync declaratively-defined wizard steps into Wizarr's database.

Wizarr seeds its ``wizard_step`` table from bundled markdown on first run and
then never touches those rows again, so onboarding copy normally lives only in
the admin UI. This script makes the copy declarative instead: it reconciles the
rows for each (server_type, category) named in the spec against the spec, and
leaves every other server type alone.

Usage: sync-wizard-steps.py <spec.json> <database.db>
"""

from __future__ import annotations

import json
import sqlite3
import sys
from datetime import datetime, timezone


def sync(spec: dict[str, list[dict]], db_path: str) -> int:
    con = sqlite3.connect(db_path)
    con.execute("PRAGMA foreign_keys = ON")
    changes = 0

    # The table only exists once Alembic has run. Bail out quietly if it does
    # not, so a first boot that fails migrations does not also fail here.
    have_table = con.execute(
        "SELECT 1 FROM sqlite_master WHERE type='table' AND name='wizard_step'"
    ).fetchone()
    if not have_table:
        print("wizard_step table absent; skipping sync", file=sys.stderr)
        return 0

    now = datetime.now(timezone.utc).replace(tzinfo=None).isoformat(sep=" ")

    for server_type, steps in spec.items():
        by_category: dict[str, list[dict]] = {}
        for step in steps:
            by_category.setdefault(step["category"], []).append(step)

        for category, wanted in by_category.items():
            existing = {
                row[0]: row
                for row in con.execute(
                    "SELECT position, title, markdown, require_interaction "
                    "FROM wizard_step WHERE server_type = ? AND category = ?",
                    (server_type, category),
                )
            }

            for position, step in enumerate(wanted):
                title = step["title"]
                markdown = step["markdown"]
                interaction = 1 if step["requireInteraction"] else 0

                have = existing.get(position)
                if have is None:
                    con.execute(
                        "INSERT INTO wizard_step (server_type, category, position, "
                        "title, markdown, requires, require_interaction, "
                        "created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)",
                        (
                            server_type,
                            category,
                            position,
                            title,
                            markdown,
                            "[]",
                            interaction,
                            now,
                            now,
                        ),
                    )
                    changes += 1
                elif tuple(have) != (position, title, markdown, interaction):
                    con.execute(
                        "UPDATE wizard_step SET title = ?, markdown = ?, "
                        "require_interaction = ?, updated_at = ? "
                        "WHERE server_type = ? AND category = ? AND position = ?",
                        (
                            title,
                            markdown,
                            interaction,
                            now,
                            server_type,
                            category,
                            position,
                        ),
                    )
                    changes += 1

            # Drop steps past the end of the declared list. ON DELETE CASCADE
            # takes any wizard_bundle_step rows pointing at them with it.
            stale = [p for p in existing if p >= len(wanted)]
            for position in stale:
                con.execute(
                    "DELETE FROM wizard_step WHERE server_type = ? AND "
                    "category = ? AND position = ?",
                    (server_type, category, position),
                )
                changes += 1

    con.commit()
    con.close()
    return changes


def main() -> None:
    spec_path, db_path = sys.argv[1], sys.argv[2]
    with open(spec_path) as fh:
        spec = json.load(fh)

    changed = sync(spec, db_path)
    if changed:
        print(f"wizard steps: {changed} row(s) reconciled")
    else:
        print("wizard steps: already in sync")


if __name__ == "__main__":
    main()
