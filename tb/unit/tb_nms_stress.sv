`timescale 1ns/1ps
`default_nettype none
module tb_nms_stress;
  logic [10:0] magnitude,mag_nw,mag_n,mag_ne,mag_w,mag_e,mag_sw,mag_s,mag_se;
  logic [1:0] direction;
  wire [10:0] nms_mag;
  wire keep;
  integer t,d,a,b,earlier,later,expected;
  reg [31:0] rng=32'h4321abcd;
  dirnms dut(.*);
  task automatic check;
    case(direction)
      0: begin earlier=mag_w; later=mag_e; end
      1: begin earlier=mag_nw; later=mag_se; end
      2: begin earlier=mag_n; later=mag_s; end
      3: begin earlier=mag_ne; later=mag_sw; end
    endcase
    expected=(magnitude>0 && magnitude>=earlier && magnitude>later) ? integer'(magnitude):0;
    #1;
    if(nms_mag !== 11'(expected) || keep !== (expected!=0)) $fatal(1,"NMS stress");
  endtask
  initial begin
    // All equalities / immediately adjacent comparison values in each direction.
    for(d=0;d<4;d++) for(t=0;t<2048;t++) for(a=-1;a<=1;a++) for(b=-1;b<=1;b++) begin
      direction=2'(d); magnitude=11'(t);
      mag_nw=11'(t+a); mag_n=mag_nw; mag_ne=mag_nw; mag_w=mag_nw;
      mag_se=11'(t+b); mag_s=mag_se; mag_sw=mag_se; mag_e=mag_se;
      check();
    end
    // Unrelated neighbours must not affect the selected direction.
    for(t=0;t<100000;t++) begin
      rng=rng*32'd1664525+32'd1013904223; magnitude=rng[10:0]; direction=rng[12:11];
      rng=rng*32'd1664525+32'd1013904223; mag_nw=rng[10:0]; mag_n=rng[21:11];
      rng=rng*32'd1664525+32'd1013904223; mag_ne=rng[10:0]; mag_w=rng[21:11];
      rng=rng*32'd1664525+32'd1013904223; mag_e=rng[10:0]; mag_sw=rng[21:11];
      rng=rng*32'd1664525+32'd1013904223; mag_s=rng[10:0]; mag_se=rng[21:11];
      check();
    end
    $display("PASS NMS: 73728 tie/boundary combinations + 100000 random neighbourhoods"); $finish;
  end
endmodule
`default_nettype wire
