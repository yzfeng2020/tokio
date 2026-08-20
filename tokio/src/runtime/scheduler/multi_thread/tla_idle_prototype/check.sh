#!/usr/bin/env bash
# PROTOTYPE: Run the buggy and fixed idle-bookkeeping models with TLC.
set -u -o pipefail

prototype_dir="$(cd "$(dirname "$0")" && pwd)"
scratch_dir="$(mktemp -d /tmp/tokio-tla-idle.XXXXXX)"
trap 'rm -rf "$scratch_dir"' EXIT

tools_version="v1.7.4"
tools_sha256="936a262061c914694dfd669a543be24573c45d5aa0ff20a8b96b23d01e050e88"
tools_jar="${TLA2TOOLS_JAR:-$scratch_dir/tla2tools.jar}"

if [[ -z "${TLA2TOOLS_JAR:-}" ]]; then
    curl -L --fail --silent --show-error \
        --output "$tools_jar" \
        "https://github.com/tlaplus/tlaplus/releases/download/$tools_version/tla2tools.jar"
fi

actual_sha256="$(sha256sum "$tools_jar" | cut -d ' ' -f 1)"
if [[ "$actual_sha256" != "$tools_sha256" ]]; then
    echo "unexpected tla2tools.jar checksum: $actual_sha256" >&2
    exit 1
fi

cd "$prototype_dir"

buggy_log="$scratch_dir/buggy.log"
set +e
java -cp "$tools_jar" tlc2.TLC \
    -deadlock -metadir "$scratch_dir/buggy-states" \
    -config Buggy.cfg IdleBookkeeping.tla >"$buggy_log" 2>&1
buggy_status=$?
set -e
cat "$buggy_log"

if [[ $buggy_status -eq 0 ]] || ! grep -q "PendingWorkWakeable is violated" "$buggy_log"; then
    echo "BUGGY MODEL: expected the remote-work wakeability violation" >&2
    exit 1
fi
echo "BUGGY MODEL: reproduced #8372"

java -cp "$tools_jar" tlc2.TLC \
    -deadlock -metadir "$scratch_dir/fixed-states" \
    -config Fixed.cfg IdleBookkeeping.tla
echo "FIXED MODEL: all invariants hold"
