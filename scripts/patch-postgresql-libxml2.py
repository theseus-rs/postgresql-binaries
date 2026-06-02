#!/usr/bin/env python3
"""Backport PostgreSQL's libxml2 2.12 compatibility fix to older releases."""

from pathlib import Path
import sys


def patch_source(source_directory: Path) -> None:
    # Upstream commit b2fd1dab90240ebb9017cd2fddd731c3641ba434, also
    # backpatched to PostgreSQL 14.11, 15.6 and 16.2. Check the source so
    # releases already containing the fix are left unchanged.
    xml_path = source_directory / "src/backend/utils/adt/xml.c"
    xml = xml_path.read_text(encoding="utf-8")
    old_signature = "xml_errorHandler(void *data, xmlErrorPtr error)"
    new_signature = "xml_errorHandler(void *data, PgXmlErrorPtr error)"
    anchor = "#define HAVE_XMLSTRUCTUREDERRORCONTEXT 1\n#endif\n"
    compatibility = '''
/*
 * libxml2 2.12 decided to insert "const" into the error handler API.
 */
#if LIBXML_VERSION >= 21200
#define PgXmlErrorPtr const xmlError *
#else
#define PgXmlErrorPtr xmlErrorPtr
#endif

'''

    if old_signature in xml:
        if xml.count(old_signature) != 2 or xml.count(anchor) != 1 or "PgXmlErrorPtr" in xml:
            raise RuntimeError(f"Unable to patch {xml_path}; unexpected error handler layout")
        xml = xml.replace(anchor, anchor + compatibility, 1)
        xml = xml.replace(old_signature, new_signature)
    elif xml.count(new_signature) != 2 or compatibility.strip() not in xml:
        raise RuntimeError(f"Unable to patch {xml_path}; unrecognized libxml2 compatibility code")

    # This global is deprecated in libxml2 2.12. PostgreSQL already blocks
    # external DTD loading through its entity loader.
    xpath_path = source_directory / "contrib/xml2/xpath.c"
    xpath = xpath_path.read_text(encoding="utf-8")
    xpath = xpath.replace("\txmlLoadExtDtdDefaultValue = 1;\n", "")

    for path, content in ((xml_path, xml), (xpath_path, xpath)):
        if path.read_text(encoding="utf-8") != content:
            path.write_text(content, encoding="utf-8")
            print(f"Patched {path.relative_to(source_directory)} for libxml2 2.12+")


def main() -> None:
    if len(sys.argv) != 2:
        raise SystemExit(f"Usage: {sys.argv[0]} <postgresql-source-directory>")

    patch_source(Path(sys.argv[1]))


if __name__ == "__main__":
    main()
