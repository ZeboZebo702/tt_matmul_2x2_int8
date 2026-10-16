/*
 * Based on mac_unit.v and booth_randix4_mul.v by Julia Desmazes (Apache-2.0).
 * mac_unit — drop-in replacement for Essenceia/Systolic_MAC_with_DFT src/mac_unit.v
 * Variant "tree": the four Booth partial products and the addend c are summed by ONE
 * multi-operand "+", so Yosys builds a single carry-save tree for multiply-and-add
 * (no separate 16-bit adder after the multiplier). The addend is sign-extended with
 * the "invert the sign bit, subtract 128" trick: c = (c ^ 0x80) - 128, so the eight
 * copies of the sign bit become one constant row.
 *
 *   res_o = clamp_i8(data_q * weight_q + add_q)
 *
 * Bit-exact with the original on res_o and data_o for all inputs.
 * JTAG user register, address 2'b11: returns {6'b0, sat_max, sat_min}. 00/01/10 unchanged.
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
wire sat_max = ~fits & ~s[15];
wire sat_min = ~fits &  s[15];
assign res_o = fits ? s[7:0] : (s[15] ? 8'h80 : 8'h7f);
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
