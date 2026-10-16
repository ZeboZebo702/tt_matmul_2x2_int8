#!/bin/bash
# Formal proof: each variant of mac_unit == original mac_unit.
# Flip-flops have the same names in both, so Yosys pairs them up and proves
# that the logic between them is identical (for every possible register value).
# Checked outputs: res_o, data_o and the JTAG register for addresses 00/01/10
# (address 11 is checked too for "fused", where it must be identical).
# Usage: formal_equiv.sh <dir with original sources> <dir with variants>
set -e
ORIG=$1; VAR=$2; TMP=$(mktemp -d)
sed 's/^module mac_unit\b/module mac_unit_gold/' $ORIG/mac_unit.v > $TMP/gold.v
status=0
for entry in presat fused fused_eq tree table hybrid:0 hybrid:1; do
  v=${entry%%:*}; P=""; [ "$v" != "$entry" ] && P="#(.TOP_ROW(${entry#*:}))"
  sed "s/^module mac_unit\b/module mac_unit_gate/" $VAR/mac_unit_$v.v > $TMP/gate.v
  if [ $v = fused ]; then MASK=0; else MASK=1; fi
  cat > $TMP/wrap.v <<W
module wrap_gold(input clk, step, wrw, input [7:0] d, top, w, input [1:0] addr, output [7:0] r, o, j);
  wire [7:0] jj; mac_unit_gold u(.clk(clk),.step_i(step),.data_i(d),.data_top_i(top),.wr_weight_v_i(wrw),.weight_i(w),.jtag_ureg_addr_i(addr),.jtag_ureg_data_o(jj),.data_o(o),.res_o(r));
  assign j = ($MASK && addr == 2'b11) ? 8'h00 : jj;
endmodule
module wrap_gate(input clk, step, wrw, input [7:0] d, top, w, input [1:0] addr, output [7:0] r, o, j);
  wire [7:0] jj; mac_unit_gate $P u(.clk(clk),.step_i(step),.data_i(d),.data_top_i(top),.wr_weight_v_i(wrw),.weight_i(w),.jtag_ureg_addr_i(addr),.jtag_ureg_data_o(jj),.data_o(o),.res_o(r));
  assign j = ($MASK && addr == 2'b11) ? 8'h00 : jj;
endmodule
W
  printf 'jj\nu.jtag_ureg_data_o\n' > $TMP/blacklist   # names that legitimately differ before masking
  if yosys -q -p "read_verilog -sv $TMP/gold.v $TMP/gate.v $TMP/wrap.v $ORIG/booth_radix4_mul.v $ORIG/booth_radix4_enc.v;
       proc; flatten; opt_clean;
       equiv_make -blacklist $TMP/blacklist wrap_gold wrap_gate eq; hierarchy -top eq; flatten;
       equiv_simple; equiv_induct; equiv_status -assert" > $TMP/log 2>&1
  then echo "  mac_unit_$entry == original : PROVEN"
  else echo "  mac_unit_$entry : NOT PROVEN (see $TMP/log)"; status=1; fi
  cp $TMP/log $TMP/log_${v}_${entry#*:}
done
exit $status
