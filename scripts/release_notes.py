#!/usr/bin/env python3
"""Read the newest version and release notes from CHANGELOG.md."""

import argparse
import datetime
import pathlib
import re
import sys


RELEASE_HEADING = re.compile(r"^## \[(\d+\.\d+\.\d+)\] - (\d{4}-\d{2}-\d{2})\s*$", re.MULTILINE)


def latest_release(changelog: str) -> tuple[str, str] | None:
    headings = list(RELEASE_HEADING.finditer(changelog))
    if not headings:
        return None

    heading = headings[0]
    datetime.date.fromisoformat(heading.group(2))
    end = headings[1].start() if len(headings) > 1 else len(changelog)
    notes = changelog[heading.end():end].strip()
    if not notes:
        raise ValueError(f"Version {heading.group(1)} has no release notes")
    return heading.group(1), notes


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("field", choices=("version", "notes"))
    parser.add_argument("--changelog", type=pathlib.Path, default=pathlib.Path("CHANGELOG.md"))
    args = parser.parse_args()

    try:
        release = latest_release(args.changelog.read_text(encoding="utf-8"))
    except (OSError, ValueError) as error:
        print(error, file=sys.stderr)
        return 1

    if release:
        print(release[0] if args.field == "version" else release[1])
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
