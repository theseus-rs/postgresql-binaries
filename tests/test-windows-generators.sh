#!/usr/bin/env bash

set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
temporary=$(mktemp -d)
trap 'rm -rf "$temporary"' EXIT
mkdir -p "$temporary/source/src/tools/msvc" "$temporary/bin"
source_directory="$temporary/source"

# Reproduce the legacy helpers' version probes, missing-tool fallback and
# generator calls. Keep the test offline; no Windows toolchain is needed.
cat > "$source_directory/src/tools/msvc/pgbison.pl" <<'PL'
use strict;
use warnings;
my ($bisonver) = `bison -V`;
$bisonver = (split(/\s+/, $bisonver))[3];
exit 0 unless $bisonver eq '1.875' || $bisonver ge '2.2';
my ($input, $output) = @ARGV;
my $nodep = '-Wno-deprecated';
my $headerflag = '-d';
system("bison $nodep $headerflag $input -o $output");
exit $? >> 8;
PL
cat > "$source_directory/src/tools/msvc/pgflex.pl" <<'PL'
use strict;
use warnings;
my ($flexver) = `flex -V`;
$flexver = (split(/\s+/, $flexver))[1];
$flexver =~ s/[^0-9.]//g;
exit 0 unless $flexver eq '2.6.4';
my ($input, $output) = @ARGV;
my $flexflags = '-CF';
system("flex $flexflags -o$output $input");
exit $? >> 8;
PL
cp -R "$source_directory" "$temporary/unexpected"

# Shadow any host bison/flex: only the win_* names can generate sources.
for tool in bison flex; do
    printf '#!/bin/sh\nexit 127\n' > "$temporary/bin/$tool"
done
cat > "$temporary/bin/win_bison" <<'SH'
#!/bin/sh
if [ "$1" = -V ]; then echo 'bison (GNU Bison) 3.8.2'; exit 0; fi
test "$1" = -Wno-deprecated && test "$2" = -d && test "$4" = -o || exit 2
test -f "$3" || exit 2
if [ "${FAIL_GENERATOR:-0}" = 1 ]; then exit 42; fi
printf 'generated parser\n' > "$5"
SH
cat > "$temporary/bin/win_flex" <<'SH'
#!/bin/sh
if [ "$1" = -V ]; then echo 'win_flex 2.6.4'; exit 0; fi
test "$1" = -CF && test "$2" = -oscanner.c || exit 2
test -f "$3" || exit 2
if [ "${FAIL_GENERATOR:-0}" = 1 ]; then exit 42; fi
printf 'generated scanner\n' > "${2#-o}"
SH
chmod +x "$temporary/bin/"*
export PATH="$temporary/bin:$PATH"
cd "$source_directory"
touch parser.y scanner.l

# Demonstrate the original false success with no pregenerated sources.
perl src/tools/msvc/pgbison.pl parser.y parser.c 2>/dev/null
perl src/tools/msvc/pgflex.pl scanner.l scanner.c 2>/dev/null
test ! -e parser.c && test ! -e scanner.c

python3 "$root/scripts/patch-postgresql-windows-generators.py" "$source_directory"
cp src/tools/msvc/pgbison.pl "$temporary/patched-bison.pl"
cp src/tools/msvc/pgflex.pl "$temporary/patched-flex.pl"
python3 "$root/scripts/patch-postgresql-windows-generators.py" "$source_directory"
cmp src/tools/msvc/pgbison.pl "$temporary/patched-bison.pl"
cmp src/tools/msvc/pgflex.pl "$temporary/patched-flex.pl"

for tool in bison flex; do
    if [ "$tool" = bison ]; then
        input=parser.y
        output=parser.c
    else
        input=scanner.l
        output=scanner.c
    fi
    perl "src/tools/msvc/pg$tool.pl" "$input" "$output"
    test -s "$output"
    rm "$output"
    status=0
    FAIL_GENERATOR=1 perl "src/tools/msvc/pg$tool.pl" "$input" "$output" || status=$?
    test "$status" -eq 42
    test ! -e "$output"
done

# Fail before modifying either helper if an upstream invocation changes.
printf 'unexpected helper\n' > "$temporary/unexpected/src/tools/msvc/pgflex.pl"
cp "$temporary/unexpected/src/tools/msvc/pgbison.pl" "$temporary/original-bison.pl"
if python3 "$root/scripts/patch-postgresql-windows-generators.py" "$temporary/unexpected" \
    > "$temporary/failure.log" 2>&1; then
    echo 'Unexpected success patching an unknown helper layout' >&2
    exit 1
fi
cmp "$temporary/unexpected/src/tools/msvc/pgbison.pl" "$temporary/original-bison.pl"
echo 'Legacy Windows generators produce sources and propagate failures with winflexbison3 names'
