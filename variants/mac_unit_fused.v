/*
 * Based on mac_unit.v and booth_randix4_mul.v by Julia Desmazes (Apache-2.0).
 * mac_unit — drop-in replacement for Essenceia/Systolic_MAC_with_DFT src/mac_unit.v
 * Variant "fused": the addend add_q is injected into the multiplier's
 * partial-product tree, so there is ONE 16-bit adder instead of two in series.
 *
 * Bit-exact with the original on res_o, data_o and all four JTAG user registers
 * (the full 16-bit sum still exists, so address 2'b11 returns the same byte).
 */
`timescale 1ns / 1ps
`default_nettype none

module mac_unit #(
	parameter W = 8
	)(
	input wire clk,
	input wire           step_i,
	input wire [W-1:0]   data_i,
	input wire [W-1:0]   data_top_i,
	input wire           wr_weight_v_i,
	input wire [W-1:0]   weight_i,
	input wire  [1:0]    jtag_ureg_addr_i,
	output reg   [W-1:0] jtag_ureg_data_o,
	output wire [W-1:0]  data_o,
	output wire [W-1:0]  res_o
);
reg [W-1:0] data_q, add_q, weight_q;

always @(posedge clk) if (step_i)        data_q   <= data_i;
always @(posedge clk) if (step_i)        add_q    <= data_top_i;
always @(posedge clk) if (wr_weight_v_i) weight_q <= weight_i;

wire [15:0] x, y;
mac_booth_csa_tree m_tree(.a(data_q), .w(weight_q), .c(add_q), .x(x), .y(y));

wire [15:0] s = x + y;                          // = data*weight + add (mod 2^16)
wire fits = (&s[15:7]) | ~(|s[15:7]);           // bits 15..7 all equal -> fits in 8 bits

assign res_o  = fits ? s[7:0] : (s[15] ? 8'h80 : 8'h7f);
assign data_o = data_q;

always @(*) begin
	case (jtag_ureg_addr_i)
		2'b00: jtag_ureg_data_o = weight_q;
		2'b01: jtag_ureg_data_o = data_q;
		2'b10: jtag_ureg_data_o = add_q;
		2'b11: jtag_ureg_data_o = s[15:8];
	endcase
end
endmodule

// ---------------------------------------------------------------------
// Booth partial products of data*weight plus the addend c as one more row,
// compressed by a 3:2 (carry-save) tree to two numbers: x + y = data*weight + c (mod 2^16).
// Rows are the same as in booth_randix4_mul.v.
// ---------------------------------------------------------------------
module mac_booth_csa_tree(input wire [7:0] a, input wire [7:0] w, input wire [7:0] c,
                          output wire [15:0] x, output wire [15:0] y);
  wire [8:0] e0, e1, e2, e3; wire x0, x1, x2, x3, s0, s1, s2, s3;
  booth_radix4_enc m0(.mul_i({w[1:0],1'b0}), .data_i(a), .res_o(e0), .ext_o(x0), .sign_o(s0));
  booth_radix4_enc m1(.mul_i(w[3:1]),        .data_i(a), .res_o(e1), .ext_o(x1), .sign_o(s1));
  booth_radix4_enc m2(.mul_i(w[5:3]),        .data_i(a), .res_o(e2), .ext_o(x2), .sign_o(s2));
  booth_radix4_enc m3(.mul_i(w[7:5]),        .data_i(a), .res_o(e3), .ext_o(x3), .sign_o(s3));
  wire [11:0] pp0 = {~x0, {2{x0}}, e0};
  wire [10:0] pp1 = {1'b1, ~x1, e1};
  wire [10:0] pp2 = {1'b1, ~x2, e2};
  wire [9:0]  pp3 = {~x3, e3};
  wire [15:0] r1 = {4'b0, pp0};
  wire [15:0] r2 = {3'b0, pp1, 1'b0, s0};
  wire [15:0] r3 = {9'b0, s3, 6'b0};
  wire [15:0] r4 = {1'b0, pp2, 1'b0, s1, 2'b0};
  wire [15:0] r5 = {pp3, 1'b0, s2, 4'b0};
  wire [15:0] r6 = {{8{c[7]}}, c};                    // the addend is just one more row
  wire [15:0] a1s = r1 ^ r2 ^ r3, a1c = ((r1 & r2) | (r1 & r3) | (r2 & r3)) << 1;  // 6 -> 4
  wire [15:0] b1s = r4 ^ r5 ^ r6, b1c = ((r4 & r5) | (r4 & r6) | (r5 & r6)) << 1;
  wire [15:0] a2s = a1s ^ a1c ^ b1s, a2c = ((a1s & a1c) | (a1s & b1s) | (a1c & b1s)) << 1; // 4 -> 3
  assign x = a2s ^ a2c ^ b1c;                                                          // 3 -> 2
  assign y = ((a2s & a2c) | (a2s & b1c) | (a2c & b1c)) << 1;
endmodule
