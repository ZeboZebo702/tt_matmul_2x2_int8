/*
 * Based on mac_unit.v and booth_randix4_mul.v by Julia Desmazes (Apache-2.0).
 * mac_unit — drop-in replacement for Essenceia/Systolic_MAC_with_DFT src/mac_unit.v
 * Variant "presat": same ports, same flip-flops, new arithmetic.
 *
 *   res_o = clamp_i8(data_q * weight_q + add_q)
 *
 * Idea: if the 16-bit product p does not fit in 9 signed bits (|p| >= 256),
 * the result is saturated by the sign of p whatever add_q is (add_q is 8 bits).
 * So: a "big" flag + a 10-bit adder on p[8:0], working in parallel,
 * instead of the 16-bit adder after the multiplier.
 *
 * Bit-exact with the original on res_o and data_o for all inputs.
 * JTAG user register, address 2'b11: the original returns the upper byte of the
 * 16-bit intermediate sum; that sum no longer exists here, so this variant
 * returns the saturation flags {6'b0, sat_max, sat_min}. Addresses 00/01/10 unchanged.
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

wire [15:0] p;
wire        unused_sign;
booth_randix4_mul m_mul(.data_i(data_q), .w_i(weight_q), .res_o(p), .res_sign_o(unused_sign));

// big = 1 if bits 15..8 of p are not all equal (p does not fit in 9 signed bits)
wire big = ~((&p[15:8]) | ~(|p[15:8]));

// 10-bit sum of the 9-bit product and sign-extended add_q
wire [9:0] sum = {p[8], p[8:0]} + {{2{add_q[7]}}, add_q};
wire ov = ~sum[9] & (sum[8] | sum[7]);   // sum > 127
wire un =  sum[9] & ~(sum[8] & sum[7]);  // sum < -128

wire sat_max = big ? ~p[15] : ov;
wire sat_min = big ?  p[15] : un;

assign res_o  = sat_max ? 8'h7f : sat_min ? 8'h80 : sum[7:0];
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
