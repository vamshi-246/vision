`timescale 1ns/1ps
`default_nettype none
module tb_linebuf_recovery;
  localparam W=11,H=7;
  logic clk=0,rst=1,pix_valid=0,pix_sof=0,pix_eol=0;
  logic [7:0] pix_data=0;
  wire win_valid;
  wire [3:0] win_x;
  wire [2:0] win_y;
  wire [7:0] w00,w01,w02,w10,w11,w12,w20,w21,w22;
  integer trial,p,seen=0,watch=0,ex,ey;
  reg [7:0] base;
  always #5 clk=~clk;
  linebuf #(.IMG_W(W),.IMG_H(H)) dut(.*);
  always @(posedge clk) begin
    #1;
    if(watch && win_valid) begin
      ex=1+seen%(W-2);ey=1+seen/(W-2);
      base=8'((ey-1)*17+ex-1+trial*7);
      if(win_x!=ex || win_y!=ey ||
         {w00,w01,w02,w10,w11,w12,w20,w21,w22} !==
         {base,base+8'd1,base+8'd2,base+8'd17,base+8'd18,base+8'd19,base+8'd34,base+8'd35,base+8'd36})
        $fatal(1,"linebuf SOF recovery trial=%0d seen=%0d at=%0d,%0d",trial,seen,win_x,win_y);
      seen++;
    end
  end
  task automatic send(input integer pos,input logic[7:0] value);
    @(negedge clk);pix_valid=1;pix_sof=(pos==0);pix_eol=(pos%W==W-1);pix_data=value;
  endtask
  initial begin
    repeat(3) @(negedge clk);rst=0;
    for(trial=0;trial<W*H-1;trial++) begin
      watch=0;
      for(p=0;p<=trial;p++) send(p,8'(p*33));
      // Fresh SOF must apply to this pixel's address as well as future counters.
      send(0,8'(trial*7));
      for(p=1;p<W*H;p++) begin
        send(p,8'((p/W)*17+p%W+trial*7));
        watch=1;
        if(p%9==0) begin @(negedge clk);pix_valid=0;pix_sof=0;pix_eol=0; end
      end
      @(negedge clk);pix_valid=0;pix_sof=0;pix_eol=0;
      repeat(2) @(negedge clk);
      if(seen!=(W-2)*(H-2)) $fatal(1,"linebuf recovery count=%0d",seen);
      seen=0;
    end
    $display("PASS linebuf: 76 SOF abort/restarts, odd frame height, random data, valid gaps");$finish;
  end
endmodule
`default_nettype wire
