#!/usr/bin/env bash

# Prove that runtime tests actually enforce the CPU floor, including on a runner
# whose kernel could otherwise execute the target architecture without QEMU.
set -euo pipefail
: "${TARGET:?Missing target}" "${PLATFORM:?Missing platform}" "${QEMU_CPU:?Missing CPU model}"
temporary=$(mktemp -d)
probe_image="postgresql-cpu-probe:$TARGET"
trap 'docker image rm "$probe_image" >/dev/null 2>&1 || true; rm -rf "$temporary"' EXIT
python3 - "$TARGET" "$temporary" <<'PYTHON'
from pathlib import Path
import struct
import sys

target, directory = sys.argv[1], Path(sys.argv[2])
if target.startswith("i586-"):
    machine, flags = 3, 0
    exit_code = bytes.fromhex("b80100000031dbcd80")  # exit(0) via int 0x80
    newer = bytes.fromhex("660fefc0")  # pxor xmm0,xmm0 (SSE2)
elif target in ("arm-unknown-linux-musleabi", "arm-unknown-linux-gnueabihf"):
    machine = 40
    soft = target.endswith("musleabi")
    flags = 0x5000200 if soft else 0x5000400
    exit_code = struct.pack("<III", 0xe3a07001, 0xe3a00000, 0xef000000)
    # vmov s0,r0 (VFP) for soft-float; vadd.i32 q0,q0,q0 (NEON) for ARMv6 HF.
    newer = struct.pack("<I", 0xee000a10 if soft else 0xf2200840)
else:
    raise SystemExit("No CPU probe for " + target)

for name, code in (("baseline", exit_code), ("newer", newer + exit_code)):
    header = struct.pack("<16sHHIIIIIHHHHHH", b"\x7fELF\x01\x01\x01",
                         2, machine, 1, 0x10054, 52, 0, flags, 52, 32, 1, 40, 0, 0)
    segment = struct.pack("<IIIIIIII", 1, 0, 0x10000, 0x10000,
                          84 + len(code), 84 + len(code), 5, 0x1000)
    path = directory / name
    path.write_bytes(header + segment + code)
    path.chmod(0o755)
PYTHON

# These static probes need no libc and can run before the source build.
cat > "$temporary/Dockerfile" <<'DOCKERFILE'
FROM scratch
COPY baseline newer /opt/
DOCKERFILE
docker build --platform "$PLATFORM" --tag "$probe_image" "$temporary"

probe() {
    echo "Checking $TARGET: $2 with CPU $1"
    # QEMU raises the guest's fatal signal on itself. Container PID 1 ignores
    # default signal actions, so an init process must supervise the probe.
    docker run --rm --init --platform "$PLATFORM" --ulimit core=0 --env "QEMU_CPU=$1" \
        --entrypoint "/opt/$2" "$probe_image"
}
probe "$QEMU_CPU" baseline
if probe "$QEMU_CPU" newer; then
    echo "CPU restriction was bypassed: $TARGET ($QEMU_CPU) accepted newer instructions" >&2
    exit 1
else
    status=$?
    if [ "$status" -ne 132 ]; then
        echo "Expected SIGILL from newer instructions, got exit $status" >&2
        exit 1
    fi
fi
probe max newer
echo "Confirmed CPU restriction for $TARGET: $QEMU_CPU"
