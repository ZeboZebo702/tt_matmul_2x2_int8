/*
 * Based on mac_unit.v and booth_randix4_mul.v by Julia Desmazes (Apache-2.0).
 * mac_unit — drop-in replacement for Essenceia/Systolic_MAC_with_DFT src/mac_unit.v
 * Variant "table": the MAC as a system of truth tables.
 *   T2: p9 = clamp_9(a*w)        — Booth product + 9-bit pre-saturation (Verilog)
 *   T3: r  = clamp_8(p9 + c)     — gate netlist synthesized from the 131 072-row truth table
 *                                  (gen_pla.py -> ABC: BDD collapse + deep AIG optimization)
 * res_o is bit-exact with the original for all inputs.
 * JTAG user register, address 2'b11: {6'b0, res==127, res==-128} (saturation flags). 00/01/10 unchanged.
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
wire big = ~((&p[15:8]) | ~(|p[15:8]));
wire [8:0] p9 = big ? {p[15], {8{~p[15]}}} : p[8:0];

// T3: r = clamp_8(p9 + c), synthesized from its truth table (T3_add_sat8_9p8bit.pla)
mac_t3_table m_t3(
	.a8(p9[8]), .a7(p9[7]), .a6(p9[6]), .a5(p9[5]), .a4(p9[4]), .a3(p9[3]), .a2(p9[2]), .a1(p9[1]), .a0(p9[0]),
	.b7(add_q[7]), .b6(add_q[6]), .b5(add_q[5]), .b4(add_q[4]), .b3(add_q[3]), .b2(add_q[2]), .b1(add_q[1]), .b0(add_q[0]),
	.r7(res_o[7]), .r6(res_o[6]), .r5(res_o[5]), .r4(res_o[4]), .r3(res_o[3]), .r2(res_o[2]), .r1(res_o[1]), .r0(res_o[0]));

assign data_o = data_q;

always @(*) begin
	case (jtag_ureg_addr_i)
		2'b00: jtag_ureg_data_o = weight_q;
		2'b01: jtag_ureg_data_o = data_q;
		2'b10: jtag_ureg_data_o = add_q;
		2'b11: jtag_ureg_data_o = {6'b0, res_o == 8'h7f, res_o == 8'h80};
	endcase
end
endmodule


module mac_t3_table(a8, a7, a6, a5, a4, a3, a2, a1, a0, b7, b6, b5, b4, b3, b2, b1, b0, r7, r6, r5, r4
, r3, r2, r1, r0);
  input a0;
  wire a0;
  input a1;
  wire a1;
  input a2;
  wire a2;
  input a3;
  wire a3;
  input a4;
  wire a4;
  input a5;
  wire a5;
  input a6;
  wire a6;
  input a7;
  wire a7;
  input a8;
  wire a8;
  input b0;
  wire b0;
  input b1;
  wire b1;
  input b2;
  wire b2;
  input b3;
  wire b3;
  input b4;
  wire b4;
  input b5;
  wire b5;
  input b6;
  wire b6;
  input b7;
  wire b7;
  wire new_n101_;
  wire new_n102_;
  wire new_n103_;
  wire new_n26_;
  wire new_n27_;
  wire new_n28_;
  wire new_n29_;
  wire new_n30_;
  wire new_n31_;
  wire new_n32_;
  wire new_n33_;
  wire new_n34_;
  wire new_n35_;
  wire new_n36_;
  wire new_n37_;
  wire new_n38_;
  wire new_n39_;
  wire new_n40_;
  wire new_n41_;
  wire new_n42_;
  wire new_n43_;
  wire new_n44_;
  wire new_n45_;
  wire new_n46_;
  wire new_n47_;
  wire new_n48_;
  wire new_n49_;
  wire new_n50_;
  wire new_n51_;
  wire new_n52_;
  wire new_n53_;
  wire new_n54_;
  wire new_n55_;
  wire new_n56_;
  wire new_n57_;
  wire new_n58_;
  wire new_n59_;
  wire new_n60_;
  wire new_n61_;
  wire new_n63_;
  wire new_n64_;
  wire new_n65_;
  wire new_n66_;
  wire new_n67_;
  wire new_n68_;
  wire new_n69_;
  wire new_n70_;
  wire new_n71_;
  wire new_n72_;
  wire new_n73_;
  wire new_n74_;
  wire new_n75_;
  wire new_n77_;
  wire new_n78_;
  wire new_n79_;
  wire new_n81_;
  wire new_n82_;
  wire new_n83_;
  wire new_n85_;
  wire new_n86_;
  wire new_n87_;
  wire new_n88_;
  wire new_n89_;
  wire new_n90_;
  wire new_n91_;
  wire new_n93_;
  wire new_n94_;
  wire new_n95_;
  wire new_n97_;
  wire new_n98_;
  wire new_n99_;
  output r0;
  wire r0;
  output r1;
  wire r1;
  output r2;
  wire r2;
  output r3;
  wire r3;
  output r4;
  wire r4;
  output r5;
  wire r5;
  output r6;
  wire r6;
  output r7;
  wire r7;
  assign new_n26_ = 4'h2 >> { b7, a7 };
  assign new_n35_ = 4'h8 >> { b3, a3 };
  assign new_n36_ = 4'h1 >> { b2, a2 };
  assign new_n37_ = 4'h8 >> { b2, a2 };
  assign new_n38_ = 4'h1 >> { new_n37_, new_n36_ };
  assign new_n39_ = 4'h8 >> { b1, a1 };
  assign new_n40_ = 4'h8 >> { b0, a0 };
  assign new_n41_ = 4'h1 >> { b1, a1 };
  assign new_n42_ = 4'h1 >> { new_n41_, new_n39_ };
  assign new_n43_ = 4'h8 >> { new_n42_, new_n40_ };
  assign new_n44_ = 4'h1 >> { new_n43_, new_n39_ };
  assign new_n27_ = 4'h2 >> { new_n26_, a8 };
  assign new_n45_ = 4'h8 >> { new_n44_, new_n38_ };
  assign new_n46_ = 4'h1 >> { new_n45_, new_n36_ };
  assign new_n47_ = 4'h1 >> { b3, a3 };
  assign new_n48_ = 4'h1 >> { new_n47_, new_n35_ };
  assign new_n49_ = 4'h8 >> { new_n48_, new_n46_ };
  assign new_n50_ = 4'h1 >> { new_n49_, new_n35_ };
  assign new_n51_ = 4'h1 >> { b4, a4 };
  assign new_n52_ = 4'h1 >> { new_n51_, new_n34_ };
  assign new_n53_ = 4'h4 >> { new_n52_, new_n50_ };
  assign new_n54_ = 4'h1 >> { new_n53_, new_n34_ };
  assign new_n28_ = 4'h4 >> { b7, a7 };
  assign new_n55_ = 4'h8 >> { b5, a5 };
  assign new_n56_ = 4'h1 >> { new_n55_, new_n33_ };
  assign new_n57_ = 4'h8 >> { new_n56_, new_n54_ };
  assign new_n58_ = 4'h1 >> { new_n57_, new_n33_ };
  assign new_n59_ = 4'h8 >> { new_n58_, new_n32_ };
  assign new_n60_ = 4'h1 >> { new_n59_, new_n30_ };
  assign new_n61_ = 4'h4 >> { new_n60_, new_n29_ };
  assign r7 = 4'he >> { new_n61_, new_n27_ };
  assign new_n63_ = 4'h1 >> { new_n33_, new_n31_ };
  assign new_n64_ = 4'h1 >> { new_n55_, new_n34_ };
  assign new_n29_ = 4'h1 >> { new_n28_, a8 };
  assign new_n65_ = 4'h2 >> { new_n64_, new_n63_ };
  assign new_n66_ = 4'h1 >> { new_n65_, new_n30_ };
  assign new_n67_ = 4'h4 >> { new_n63_, new_n51_ };
  assign new_n68_ = 4'h1 >> { new_n67_, new_n26_ };
  assign new_n69_ = 4'h8 >> { new_n68_, new_n66_ };
  assign new_n70_ = 4'h2 >> { new_n69_, new_n29_ };
  assign new_n71_ = 4'h1 >> { new_n58_, new_n32_ };
  assign new_n72_ = 4'h1 >> { new_n66_, new_n28_ };
  assign new_n73_ = 4'h2 >> { new_n72_, new_n27_ };
  assign new_n74_ = 4'h1 >> { new_n73_, new_n59_ };
  assign new_n30_ = 4'h8 >> { b6, a6 };
  assign new_n75_ = 4'h4 >> { new_n74_, new_n71_ };
  assign r6 = 4'he >> { new_n75_, new_n70_ };
  assign new_n77_ = 4'h1 >> { new_n56_, new_n54_ };
  assign new_n78_ = 4'h1 >> { new_n70_, new_n57_ };
  assign new_n79_ = 4'h4 >> { new_n78_, new_n77_ };
  assign r5 = 4'h1 >> { new_n79_, new_n73_ };
  assign new_n81_ = 4'h2 >> { new_n52_, new_n50_ };
  assign new_n82_ = 4'h1 >> { new_n73_, new_n53_ };
  assign new_n83_ = 4'h4 >> { new_n82_, new_n81_ };
  assign r4 = 4'he >> { new_n83_, new_n70_ };
  assign new_n31_ = 4'h1 >> { b6, a6 };
  assign new_n85_ = 4'h4 >> { new_n60_, new_n26_ };
  assign new_n86_ = 4'h2 >> { new_n85_, new_n29_ };
  assign new_n87_ = 4'h1 >> { new_n60_, new_n28_ };
  assign new_n88_ = 4'h2 >> { new_n87_, new_n27_ };
  assign new_n89_ = 4'h1 >> { new_n48_, new_n46_ };
  assign new_n90_ = 4'h1 >> { new_n89_, new_n49_ };
  assign new_n91_ = 4'h4 >> { new_n90_, new_n88_ };
  assign r3 = 4'he >> { new_n91_, new_n86_ };
  assign new_n93_ = 4'h1 >> { new_n44_, new_n38_ };
  assign new_n94_ = 4'h1 >> { new_n93_, new_n45_ };
  assign new_n32_ = 4'h1 >> { new_n31_, new_n30_ };
  assign new_n95_ = 4'h1 >> { new_n94_, new_n88_ };
  assign r2 = 4'he >> { new_n95_, new_n86_ };
  assign new_n97_ = 4'h1 >> { new_n42_, new_n40_ };
  assign new_n98_ = 4'h1 >> { new_n97_, new_n43_ };
  assign new_n99_ = 4'h4 >> { new_n98_, new_n88_ };
  assign r1 = 4'he >> { new_n99_, new_n86_ };
  assign new_n101_ = 4'h1 >> { b0, a0 };
  assign new_n102_ = 4'h1 >> { new_n101_, new_n40_ };
  assign new_n103_ = 4'h1 >> { new_n102_, new_n86_ };
  assign r0 = 4'h1 >> { new_n103_, new_n88_ };
  assign new_n33_ = 4'h1 >> { b5, a5 };
  assign new_n34_ = 4'h8 >> { b4, a4 };
endmodule
