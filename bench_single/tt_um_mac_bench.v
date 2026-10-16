/*
 * tt_um_mac_bench — one MAC unit (mac_unit.v) of tt_um_essen on its own 1x1 tile.
 * Purpose: a clean area / timing comparison of the MAC arithmetic only.
 *
 * The timing path measured by STA is exactly the one inside the real chip:
 *   data_q, weight_q, add_q (flip-flops in mac_unit)
 *     -> multiply -> add -> saturate ->  r_q (flip-flop here)
 *
 * Pins:
 *   ui_in[7:0]   data byte (int8)
 *   uio_in[0]    step:   mac_unit takes data <- ui_in, top <- top_q
 *   uio_in[1]    load top_q <- ui_in   (the value "from the unit above")
 *   uio_in[2]    write weight <- ui_in
 *   uio_in[4:3]  JTAG user-register address (debug readout of mac_unit)
 *   uio_in[7]    output select: 0 = result, 1 = debug register
 *   uo_out[7:0]  registered result clamp_i8(data*weight + top) (one clock after step)
 */
`timescale 1ns / 1ps
`default_nettype none

module tt_um_mac_bench (
    input  wire [7:0] ui_in,
    output wire [7:0] uo_out,
    input  wire [7:0] uio_in,
    output wire [7:0] uio_out,
    output wire [7:0] uio_oe,
    input  wire       ena,
    input  wire       clk,
    input  wire       rst_n
);
  reg  [7:0] top_q, r_q, j_q;
  wire [7:0] res, unused_data, jtag;

  always @(posedge clk) if (uio_in[1]) top_q <= ui_in;

  mac_unit #(.W(8)) u_mac (
      .clk              (clk),
      .step_i           (uio_in[0]),
      .data_i           (ui_in),
      .data_top_i       (top_q),
      .wr_weight_v_i    (uio_in[2]),
      .weight_i         (ui_in),
      .jtag_ureg_addr_i (uio_in[4:3]),
      .jtag_ureg_data_o (jtag),
      .data_o           (unused_data),
      .res_o            (res)
  );

  always @(posedge clk) begin
    r_q <= res;     // end point of the arithmetic path
    j_q <= jtag;
  end

  assign uo_out  = uio_in[7] ? j_q : r_q;
  assign uio_out = 8'h00;
  assign uio_oe  = 8'h00;

  wire _unused = &{ena, rst_n, uio_in[6:5], unused_data, 1'b0};
endmodule
