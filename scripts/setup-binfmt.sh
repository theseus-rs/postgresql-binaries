#!/usr/bin/env bash

set -euo pipefail

# tonistiigi/binfmt:latest, resolved 2026-09-27. Retry only the download; an
# emulator installation failure must remain visible without repeating it.
image=tonistiigi/binfmt@sha256:400a4873b838d1b89194d982c45e5fb3cda4593fbfd7e08a02e76b03b21166f0
if ! docker image inspect "$image" >/dev/null 2>&1; then
    for attempt in 1 2 3; do
        if docker pull "$image"; then break; else status=$?; fi
        printf 'Emulator image download failed (attempt %s/3, exit %s)\n' "$attempt" "$status" >&2
        if [ "$attempt" -eq 3 ]; then exit "$status"; fi
        sleep "$((attempt * 5))"
    done
fi
docker run --pull=never --privileged --rm "$image" --install all
