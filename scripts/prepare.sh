#!/usr/bin/env bash
# Assemble one Tiny Tapeout project for one experiment point.
#   prepare.sh <level> <variant> <period_ns> <out_dir>
#     level   : single  — one MAC unit on a 1x1 tile (bench_single/)
#               full    — Julia's whole tt_um_essen, only src/mac_unit.v replaced
#     variant : orig | presat | fused | fused_eq
#     period  : clock period in ns (20 = 50 MHz)
set -euo pipefail
LEVEL=$1; VARIANT=$2; PERIOD=$3; OUT=$4
ROOT=$(cd "$(dirname "$0")/.." && pwd)
source "$ROOT/versions.env"

# 1. Julia's sources (downloaded once, fixed commit)
UP="$ROOT/.cache/upstream"
if [ ! -d "$UP/.git" ]; then
  git clone -q "$UPSTREAM_REPO" "$UP"
fi
git -C "$UP" checkout -q "$UPSTREAM_REF"

# 2. Tiny Tapeout tools (downloaded once, fixed commit)
TT="$ROOT/.cache/tt-support-tools"
if [ ! -d "$TT/.git" ]; then
  git clone -q "$TT_TOOLS_REPO" "$TT"
fi
git -C "$TT" checkout -q "$TT_TOOLS_REF"

# 3. Which mac_unit.v to use
if [ "$VARIANT" = orig ]; then
  MAC="$UP/src/mac_unit.v"
else
  MAC="$ROOT/variants/mac_unit_$VARIANT.v"
fi
[ -f "$MAC" ] || { echo "unknown variant: $VARIANT"; exit 1; }

# 4. Build the project folder
rm -rf "$OUT"; mkdir -p "$OUT/src"
case "$LEVEL" in
  single)
    cp "$ROOT/bench_single/tt_um_mac_bench.v" "$OUT/src/"
    cp "$ROOT/bench_single/config.json"       "$OUT/src/"
    cp "$ROOT/bench_single/info.yaml"         "$OUT/"
    cp "$UP/src/booth_radix4_mul.v" "$UP/src/booth_radix4_enc.v" "$OUT/src/"
    ;;
  full)
    cp -r "$UP/src/." "$OUT/src/"
    cp "$UP/info.yaml" "$OUT/"
    [ -d "$UP/docs" ] && cp -r "$UP/docs" "$OUT/"
    ;;
  *) echo "unknown level: $LEVEL"; exit 1;;
esac
cp "$MAC" "$OUT/src/mac_unit.v"
# some variants also change other files of the full chip (e.g. "hybrid" changes one line of mac.v)
if [ "$LEVEL" = full ] && [ -d "$ROOT/variants/extra/$VARIANT" ]; then
  cp "$ROOT/variants/extra/$VARIANT/"* "$OUT/src/"
fi
cp "$UP/LICENSE" "$OUT/" 2>/dev/null || true

# 5. Set the clock period (the only setting we change between runs)
python3 - "$OUT/src/config.json" "$PERIOD" <<'PY'
import re, sys
path, period = sys.argv[1], sys.argv[2]
s = open(path).read()
s, n = re.subn(r'("CLOCK_PERIOD"\s*:\s*)[0-9.]+', r'\g<1>' + period, s)
if n != 1:
    sys.exit(f"expected exactly one CLOCK_PERIOD in {path}, found {n}")
open(path, "w").write(s)
PY

# 6. Tiny Tapeout tools expect: a git repo, and the tools in ./tt
cp -r "$TT" "$OUT/tt"
printf 'tt/\nruns/\n' > "$OUT/.gitignore"
(
  cd "$OUT"
  git init -q
  git -c user.name=bench -c user.email=bench@localhost add -A
  git -c user.name=bench -c user.email=bench@localhost commit -q -m "$LEVEL $VARIANT ${PERIOD}ns"
)
echo "prepared $OUT  (level=$LEVEL variant=$VARIANT period=${PERIOD}ns)"
