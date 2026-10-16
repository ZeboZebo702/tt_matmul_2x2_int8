// Exhaustive check: the original mac_unit and every variant are driven by the same
// signals; every (data, weight, top) combination, 2^24 cases, is compared.
// Modules are renamed by verify.sh: mac_unit_orig, mac_unit_<variant>.
// "hybrid" is checked with both settings of its TOP_ROW parameter.
`timescale 1ns/1ps
`define DUT(name, mod, params) \
  wire [7:0] r_``name, o_``name, j_``name; \
  mod params u_``name(.clk(clk), .step_i(step), .data_i(d), .data_top_i(top), .wr_weight_v_i(wrw), \
    .weight_i(w), .jtag_ureg_addr_i(addr), .jtag_ureg_data_o(j_``name), .data_o(o_``name), .res_o(r_``name)); \
  integer e_``name = 0;
`define CHECK(name) \
  if (r_``name !== r_orig || o_``name !== o_orig) e_``name = e_``name + 1; \
  if (addr != 2'b11 && j_``name !== j_orig) ej = ej + 1;

module tb_mac_unit_all;
  reg clk = 0, step = 0, wrw = 0;
  reg [7:0] d = 0, top = 0, w = 0;
  reg [1:0] addr = 0;
  `DUT(orig,     mac_unit_orig,     )
  `DUT(presat,   mac_unit_presat,   )
  `DUT(fused,    mac_unit_fused,    )
  `DUT(fused_eq, mac_unit_fused_eq, )
  `DUT(tree,     mac_unit_tree,     )
  `DUT(table,    mac_unit_table,    )
  `DUT(hybrid0,  mac_unit_hybrid,   #(.TOP_ROW(0)))
  `DUT(hybrid1,  mac_unit_hybrid,   #(.TOP_ROW(1)))
  integer a, b, c, p, e, n = 0, emath = 0, ej = 0, efj = 0;
  initial begin
    for (b = -128; b < 128; b = b + 1) begin
      w = b; wrw = 1; #1 clk = 1; #1 clk = 0; wrw = 0;
      for (a = -128; a < 128; a = a + 1)
        for (c = -128; c < 128; c = c + 1) begin
          d = a; top = c; step = 1; #1 clk = 1; #1 clk = 0; step = 0;
          addr = n[1:0]; #1;
          p = a * b + c; e = p > 127 ? 127 : (p < -128 ? -128 : p);
          n = n + 1;
          if (r_orig !== e[7:0]) emath = emath + 1;
          `CHECK(presat) `CHECK(fused) `CHECK(fused_eq) `CHECK(tree)
          `CHECK(table) `CHECK(hybrid0) `CHECK(hybrid1)
          if (j_fused !== j_orig) efj = efj + 1;   // fused keeps even JTAG address 11 identical
        end
    end
    $display("RESULT cases=%0d orig_vs_math=%0d presat=%0d fused=%0d fused_eq=%0d tree=%0d table=%0d hybrid0=%0d hybrid1=%0d jtag_00_01_10=%0d fused_jtag_11=%0d",
             n, emath, e_presat, e_fused, e_fused_eq, e_tree, e_table, e_hybrid0, e_hybrid1, ej, efj);
    $finish;
  end
endmodule
