#!/usr/bin/env bash

set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
temporary=$(mktemp -d)
trap 'rm -rf "$temporary"' EXIT
export DIAGNOSTICS_HELPER="$root/scripts/build-diagnostics.sh"
export CLEANUP_MARKER="$temporary/cleaned"

# Exercise the otherwise silent exit code seen in CI, including nested shell
# contexts. Every failure must retain its status, source location and cleanup.
for context in direct function substitution pipeline; do
    cat > "$temporary/failure.sh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
source "$DIAGNOSTICS_HELPER"
trap 'touch "$CLEANUP_MARKER"' EXIT
build_phase 'Install test fixture'
SH
    case "$context" in
        direct) printf "bash -c 'exit 4'\n" ;;
        function) printf "fail_fixture() { bash -c 'exit 4'; }\nfail_fixture\n" ;;
        substitution) printf "result=\$(bash -c 'exit 4')\n" ;;
        pipeline) printf "bash -c 'exit 4' | cat\n" ;;
    esac >> "$temporary/failure.sh"
    rm -f "$CLEANUP_MARKER"
    if bash "$temporary/failure.sh" > "$temporary/stdout" 2> "$temporary/stderr"; then
        echo "Failure was hidden: $context" >&2; exit 1
    else
        status=$?
    fi
    test "$status" = 4
    test -f "$CLEANUP_MARKER"
    test ! -s "$temporary/stdout"
    grep -F 'Install test fixture' "$temporary/stderr" >/dev/null
    grep -E 'failure.sh:[0-9]+: .*exit 4' "$temporary/stderr" >/dev/null
    if [ "$context" = pipeline ]; then
        grep -F 'pipeline statuses: 4 0' "$temporary/stderr" >/dev/null
    fi
done

# Expected failures in conditionals must remain usable, and phase messages must
# not enter command-substitution values or cause successful commands to fail.
bash -c '
set -euo pipefail
source "$DIAGNOSTICS_HELPER"
if bash -c "exit 4"; then exit 1; fi
value=$(build_phase "Check value"; printf expected)
test "$value" = expected
' > "$temporary/stdout" 2> "$temporary/stderr"
test ! -s "$temporary/stdout"
if grep -F 'Build failed:' "$temporary/stderr"; then exit 1; fi
echo 'Build diagnostics preserve failures, cleanup and command output'
