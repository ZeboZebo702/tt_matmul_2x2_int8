/*
 * Based on mac_unit.v and booth_randix4_mul.v by Julia Desmazes (Apache-2.0).
 * mac_unit — replacement for Essenceia/Systolic_MAC_with_DFT src/mac_unit.v
 * Variant "hybrid": the best arithmetic for each row of the systolic array.
 *
 *   TOP_ROW = 1 : units in the top row; their top input is always 0 in tt_um_essen,
 *                 so the result is clamp(a*w). The "presat" arithmetic is the smallest here.
 *   TOP_ROW = 0 : all other units; the "tree" arithmetic (Booth rows + c summed by one
 *                 multi-operand "+") is the smallest here.
 *
 * Both bodies compute res_o = clamp_i8(data_q * weight_q + add_q) for ANY input, so each
 * setting is bit-exact with the original unit on its own; TOP_ROW only picks the structure.
 * mac.v passes TOP_ROW = (y == 0) — the only change outside this file.
 * JTAG user register, address 2'b11: returns {6'b0, sat_max, sat_min}. 00/01/10 unchanged.
 */
`timescale 1ns / 1ps
`default_nettype none

module mac_unit #(
	parameter W = 8,
	parameter TOP_ROW = 0
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

wire sat_max, sat_min;

generate
if (TOP_ROW) begin : g_presat
	wire [15:0] p;
	wire        unused_sign;
	booth_randix4_mul m_mul(.data_i(data_q), .w_i(weight_q), .res_o(p), .res_sign_o(unused_sign));

	// big = 1 if bits 15..8 of p are not all equal (p does not fit in 9 signed bits)
	wire big = ~((&p[15:8]) | ~(|p[15:8]));

	// 10-bit sum of the 9-bit product and sign-extended add_q
	wire [9:0] sum = {p[8], p[8:0]} + {{2{add_q[7]}}, add_q};
	wire ov = ~sum[9] & (sum[8] | sum[7]);   // sum > 127
	wire un =  sum[9] & ~(sum[8] & sum[7]);  // sum < -128

	assign sat_max = big ? ~p[15] : ov;
	assign sat_min = big ?  p[15] : un;

	assign res_o  = sat_max ? 8'h7f : sat_min ? 8'h80 : sum[7:0];
end else begin : g_tree
	wire [8:0] e0, e1, e2, e3; wire x0, x1, x2, x3, s0, s1, s2, s3;
	booth_radix4_enc m0(.mul_i({weight_q[1:0],1'b0}), .data_i(data_q), .res_o(e0), .ext_o(x0), .sign_o(s0));
	booth_radix4_enc m1(.mul_i(weight_q[3:1]),        .data_i(data_q), .res_o(e1), .ext_o(x1), .sign_o(s1));
	booth_radix4_enc m2(.mul_i(weight_q[5:3]),        .data_i(data_q), .res_o(e2), .ext_o(x2), .sign_o(s2));
	booth_radix4_enc m3(.mul_i(weight_q[7:5]),        .data_i(data_q), .res_o(e3), .ext_o(x3), .sign_o(s3));
	wire [11:0] pp0 = {~x0, {2{x0}}, e0};
	wire [10:0] pp1 = {1'b1, ~x1, e1};
	wire [10:0] pp2 = {1'b1, ~x2, e2};
	wire [9:0]  pp3 = {~x3, e3};
	wire [15:0] r1 = {4'b0, pp0};
	wire [15:0] r2 = {3'b0, pp1, 1'b0, s0};
	wire [15:0] r3 = {9'b0, s3, 6'b0};
	wire [15:0] r4 = {1'b0, pp2, 1'b0, s1, 2'b0};
	wire [15:0] r5 = {pp3, 1'b0, s2, 4'b0};
	wire [15:0] r6 = {8'b0, ~add_q[7], add_q[6:0]};   // c + 128, unsigned
	wire [15:0] k6 = 16'hFF80;                          // -128
	wire [15:0] s = r1 + r2 + r3 + r4 + r5 + r6 + k6;

	wire fits = (&s[15:7]) | ~(|s[15:7]);
	assign sat_max = ~fits & ~s[15];
	assign sat_min = ~fits &  s[15];
	assign res_o = fits ? s[7:0] : (s[15] ? 8'h80 : 8'h7f);
end
endgenerate

assign data_o = data_q;

always @(*) begin
	case (jtag_ureg_addr_i)
		2'b00: jtag_ureg_data_o = weight_q;
		2'b01: jtag_ureg_data_o = data_q;
		2'b10: jtag_ureg_data_o = add_q;
		2'b11: jtag_ureg_data_o = {6'b0, sat_max, sat_min};
	endcase
end
endmodule
