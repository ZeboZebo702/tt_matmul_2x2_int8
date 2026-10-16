#!/usr/bin/env bash
# One experiment point: assemble the project, run the full Tiny Tapeout flow
# (LibreLane: synthesis -> placement -> clock tree -> routing -> timing), collect numbers.
#   run_one.sh <level> <variant> <period_ns>
# Result: results/<level>-<variant>-<period>.json  (+ the full run in work/)
# Needs: Docker, Python 3.11+, git.  Works on GitHub Actions, Linux, and WSL2 on Windows.
set -uo pipefail
LEVEL=$1; VARIANT=$2; PERIOD=$3
ROOT=$(cd "$(dirname "$0")/.." && pwd)
source "$ROOT/versions.env"
TAG="$LEVEL-$VARIANT-$PERIOD"
WORK="$ROOT/work/$TAG"
mkdir -p "$ROOT/results"

bash "$ROOT/scripts/prepare.sh" "$LEVEL" "$VARIANT" "$PERIOD" "$WORK" || exit 1

cd "$WORK"
python3 -m pip install -q -r tt/requirements.txt
python3 -m pip install -q "librelane==$LIBRELANE_VERSION"

STATUS=ok
python3 tt/tt_tool.py --create-user-config --gf || STATUS=config_failed
if [ $STATUS = ok ]; then
  # --harden runs LibreLane inside its Docker image, exactly like the official action
  python3 tt/tt_tool.py --harden --gf 2>&1 | tee "$WORK/harden.log"
  [ "${PIPESTATUS[0]}" -eq 0 ] || STATUS=flow_failed
fi

python3 "$ROOT/scripts/collect_one.py" \
  --run-dir "$WORK/runs/wokwi" --level "$LEVEL" --variant "$VARIANT" --period "$PERIOD" \
  --status "$STATUS" --log "$WORK/harden.log" --out "$ROOT/results/$TAG.json"
echo "status: $STATUS"
