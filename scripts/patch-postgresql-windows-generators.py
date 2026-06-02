#!/usr/bin/env python3
"""Use winflexbison3's executable names in PostgreSQL 14/15 MSVC helpers."""

from pathlib import Path
import sys


def patch_source(source_directory: Path) -> None:
    updates = []
    for tool in ("bison", "flex"):
        path = source_directory / "src/tools/msvc" / f"pg{tool}.pl"
        original = path.read_text(encoding="utf-8")
        text = original
        # Update both the version probe and the generation command. Changing
        # only the latter leaves the helper silently skipping missing tools.
        for old in (f"`{tool} -V`", f'system("{tool} '):
            new = old.replace(tool, f"win_{tool}", 1)
            if text.count(new) == 1 and old not in text:
                continue
            if text.count(old) != 1 or new in text:
                raise RuntimeError(f"Unable to patch {path}; unexpected {tool} invocation")
            text = text.replace(old, new, 1)
        if text != original:
            updates.append((path, text))

    for path, text in updates:
        path.write_text(text, encoding="utf-8")
        print(f"Patched {path.relative_to(source_directory)} for winflexbison3")


def main() -> None:
    if len(sys.argv) != 2:
        raise SystemExit(f"Usage: {sys.argv[0]} <postgresql-source-directory>")
    patch_source(Path(sys.argv[1]))


if __name__ == "__main__":
    main()
