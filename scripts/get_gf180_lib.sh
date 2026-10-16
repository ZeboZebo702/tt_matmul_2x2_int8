#!/usr/bin/env bash
# Download the GF180 standard-cell library (typical corner, 3.3 V — the one Tiny Tapeout
# synthesizes with) and assemble it into one liberty file for scripts/synth_local.py.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
OUT="$ROOT/.cache/gf180"; mkdir -p "$OUT"
LIB="$OUT/gf180mcu_fd_sc_mcu7t5v0__tt_025C_3v30.lib"
[ -f "$LIB" ] && { echo "already there: $LIB"; exit 0; }
SRC="$OUT/src"; rm -rf "$SRC"
git clone -q --depth 1 --filter=blob:none --sparse \
  https://github.com/google/globalfoundries-pdk-libs-gf180mcu_fd_sc_mcu7t5v0.git "$SRC"
git -C "$SRC" sparse-checkout set --no-cone '/liberty/*tt_025C_3v30*' '/cells/*/*__tt_025C_3v30.lib'
python3 - "$SRC" "$LIB" <<'PY'
import glob, re, sys
src, out = sys.argv[1], sys.argv[2]
hdr = open(f"{src}/liberty/gf180mcu_fd_sc_mcu7t5v0__tt_025C_3v30.lib").read().rstrip()[:-1]
cells = [re.sub(r"/\*.*?\*/", "", open(f).read(), flags=re.S)
         for f in sorted(glob.glob(f"{src}/cells/*/*__tt_025C_3v30.lib"))]
open(out, "w").write(hdr + "\n".join(cells) + "\n}\n")
print(f"{len(cells)} cells -> {out}")
PY
rm -rf "$SRC"
