#!/usr/bin/env bash
# Rebuild the gate netlist of table T3 (r = clamp_8(p9 + c)) used by variants/mac_unit_table.v,
# straight from its truth table:
#   gen_pla.py  -> T3.pla (131 072 rows)
#   ABC         -> BDD collapse, AIG optimization (compress2rs, deepsyn), BLIF
#   Yosys       -> Verilog module mac_t3_table
# To try YOUR OWN logic synthesis method: give it tools/out/T3.pla (or T2.pla) and put the
# resulting Verilog module in place of mac_t3_table at the end of variants/mac_unit_table.v.
# Needs: python3, yosys and yosys-abc (apt install yosys).
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p out
python3 gen_pla.py add --wa 9 --wb 8 -o out/T3.pla          # T3: 9-bit p + 8-bit c, saturate to 8
python3 gen_pla.py mul -n 8 -m 9    -o out/T2.pla          # T2: 8x8 product, saturate to 9 (for experiments)
cp abc.rc out/                                             # ABC reads aliases (resyn2, compress2rs) from here
cd out
yosys-abc -q "read_pla T3.pla; collapse; strash; dc2; resyn2; dc2; resyn2;
              compress2rs; compress2rs; &get -n; &deepsyn -T 150; &put; resyn2;
              print_stats; write_blif T3.blif"
yosys -q -p "read_blif T3.blif; rename T3 mac_t3_table; opt_clean; write_verilog -noattr T3_table.v"
echo "netlist: tools/out/T3_table.v"
