// Quick functional test of the 1x1 bench: random values, compare with clamp(a*w+c).
`timescale 1ns/1ps
module tb_bench;
  reg clk = 0; always #5 clk = ~clk;
  reg [7:0] ui = 0, uio = 0; wire [7:0] uo, uio_out, uio_oe;
  tt_um_mac_bench dut(.ui_in(ui), .uo_out(uo), .uio_in(uio), .uio_out(uio_out), .uio_oe(uio_oe), .ena(1'b1), .clk(clk), .rst_n(1'b1));
  integer i, a, w, c, p, e, errs = 0;
  task tick; begin @(posedge clk); #1; end endtask
  initial begin
    for (i = 0; i < 20000; i = i + 1) begin
      a = $random % 128; w = $random % 128; c = $random % 128;
      if (i % 3 == 0) begin a = -128 + ($random & 255); w = -128 + ($random & 255); end
      ui = w; uio = 8'b0000_0100; tick;            // write weight
      ui = c; uio = 8'b0000_0010; tick;            // load top
      ui = a; uio = 8'b0000_0001; tick;            // step
      uio = 0; tick;                               // result registered
      p = a * w + c; e = p > 127 ? 127 : (p < -128 ? -128 : p);
      if (uo !== e[7:0]) begin errs = errs + 1; if (errs < 5) $display("a=%0d w=%0d c=%0d got=%0d exp=%0d", a, w, c, $signed(uo), e); end
      uio = 8'b1000_0000; tick;                    // read debug reg 00 = weight
      if (uo !== w[7:0]) errs = errs + 1;
    end
    $display("RESULT bench errors=%0d", errs); $finish;
  end
endmodule
