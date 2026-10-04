#!/usr/bin/env bash

set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
temporary=$(mktemp -d)
trap 'rm -rf "$temporary"' EXIT
mkdir "$temporary/bin"
cat > "$temporary/bin/wget" <<'SH'
#!/usr/bin/env bash
set -eu
while [ "$#" -gt 0 ]; do
    if [ "$1" = -O ]; then
        printf '%s\n' 'corrupt or substituted source archive' > "$2"
        exit 0
    fi
    shift
done
exit 1
SH
cat > "$temporary/bin/tar" <<'SH'
#!/usr/bin/env bash
touch "$PATCH_TEST_EXTRACTED"
exit 1
SH
chmod +x "$temporary/bin/"*
export PATCH_TEST_EXTRACTED="$temporary/extracted"
# macOS provides shasum rather than sha256sum; preserve the real digest check.
if ! command -v sha256sum >/dev/null; then
    cat > "$temporary/bin/sha256sum" <<'SH'
#!/usr/bin/env bash
exec shasum -a 256 "$@"
SH
    chmod +x "$temporary/bin/sha256sum"
fi
if PATH="$temporary/bin:$PATH" bash "$root/scripts/install-patchelf.sh" > "$temporary/log" 2>&1; then
    echo 'Accepted an unverified patchelf source archive' >&2
    exit 1
fi
grep -q 'FAILED' "$temporary/log"
test ! -e "$PATCH_TEST_EXTRACTED"
echo 'Corrupt patchelf source rejected before extraction'
