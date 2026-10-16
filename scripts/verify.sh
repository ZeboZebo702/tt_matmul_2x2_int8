#!/usr/bin/env bash
# Correctness checks BEFORE spending time on the chip flow.
#   verify.sh          all checks (~30 min)
#   verify.sh --quick  skip the 2^24 exhaustive simulation and the formal proof (~1 min)
# Needs: iverilog, yosys, python3 with cocotb==2.0.1 and pytest (pip install cocotb==2.0.1 pytest)
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
source "$ROOT/versions.env"
QUICK=${1:-}
UP="$ROOT/.cache/upstream"
[ -d "$UP/.git" ] || git clone -q "$UPSTREAM_REPO" "$UP"
git -C "$UP" checkout -q "$UPSTREAM_REF"
J="$UP/src"; V="$ROOT/variants"; TMP=$(mktemp -d)
mac() { [ "$1" = orig ] && echo "$J/mac_unit.v" || echo "$V/mac_unit_$1.v"; }
FAIL=0

echo "=== 1. 1x1 bench: 20 000 random cases, every variant ==="
for v in orig presat fused fused_eq tree hybrid table; do
  iverilog -g2012 -o "$TMP/b" "$ROOT/verify/tb_bench.v" "$ROOT/bench_single/tt_um_mac_bench.v" \
    "$(mac $v)" "$J/booth_radix4_mul.v" "$J/booth_radix4_enc.v"
  r=$(vvp -n "$TMP/b" | grep RESULT); echo "  $v: $r"
  [[ "$r" == *"errors=0"* ]] || FAIL=1
done

echo "=== 2. Julia's own testbench (cocotb, 7 tests) on the whole chip, every variant ==="
for v in orig presat fused fused_eq tree hybrid table; do
  rm -rf "$TMP/chip"; cp -r "$UP" "$TMP/chip"; cp "$(mac $v)" "$TMP/chip/src/mac_unit.v"
  [ -d "$V/extra/$v" ] && cp "$V/extra/$v/"* "$TMP/chip/src/"   # e.g. hybrid: mac.v with TOP_ROW
  # her interactive.py uses a type name that only exists at runtime; this line is needed on Python < 3.14
  sed -i '1i from __future__ import annotations' "$TMP/chip/test/interactive.py"
  r=$(cd "$TMP/chip/test" && make -s WAVES=0 2>&1 | grep -oE "TESTS=[0-9]+ PASS=[0-9]+ FAIL=[0-9]+" | tail -1)
  echo "  $v: $r"
  [[ "$r" == *"FAIL=0"* ]] || FAIL=1
done

if [ "$QUICK" != "--quick" ]; then
  echo "=== 3. Exhaustive: all 2^24 (data, weight, top), 8 units side by side (~12 min) ==="
  sed 's/^module mac_unit\b/module mac_unit_orig/' "$J/mac_unit.v" > "$TMP/orig.v"
  for v in presat fused fused_eq tree table hybrid; do
    sed "s/^module mac_unit\b/module mac_unit_$v/; s/mac_booth_csa_tree/mac_booth_csa_tree_$v/" "$V/mac_unit_$v.v" > "$TMP/$v.v"
  done
  iverilog -g2012 -o "$TMP/all" "$ROOT/verify/tb_mac_unit_all.v" "$TMP"/{orig,presat,fused,fused_eq,tree,table,hybrid}.v \
    "$J/booth_radix4_mul.v" "$J/booth_radix4_enc.v"
  r=$(vvp -n "$TMP/all" | grep RESULT); echo "  $r"
  [[ "$r" == *"orig_vs_math=0 presat=0 fused=0 fused_eq=0 tree=0 table=0 hybrid0=0 hybrid1=0 jtag_00_01_10=0 fused_jtag_11=0"* ]] || FAIL=1

  echo "=== 4. Formal proof of equivalence (Yosys, ~12 min) ==="
  bash "$ROOT/verify/formal_equiv.sh" "$J" "$V" || FAIL=1
fi

[ $FAIL = 0 ] && echo "ALL CHECKS PASSED" || { echo "SOME CHECKS FAILED"; exit 1; }
