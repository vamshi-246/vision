`timescale 1ns/1ps
`default_nettype none
module tb_arithmetic_stress;
  logic clk=0, in_valid=0;
  logic [7:0] w00,w01,w02,w10,w11,w12,w20,w21,w22;
  wire gauss_valid, sobel_valid;
  wire [7:0] smooth;
  wire [10:0] magnitude;
  wire [1:0] direction;
  integer em[0:3], ed[0:3], eg;
  logic ev[0:3];
  integer sample=0, checked=0, gx, gy, ax, ay, sum, i, j, bitpos;
  reg [31:0] rng=32'h1234beef;
  reg [7:0] window[0:8];
  always #5 clk=~clk;
  gauss g(.clk,.in_valid,.w00,.w01,.w02,.w10,.w11,.w12,.w20,.w21,.w22,.out_valid(gauss_valid),.smooth);
  sobel s(.clk,.in_valid,.w00,.w01,.w02,.w10,.w11,.w12,.w20,.w21,.w22,.out_valid(sobel_valid),.magnitude,.direction);
  initial begin
    for(i=0;i<4;i++) begin ev[i]=0; em[i]=0; ed[i]=0; end
    for(sample=0;sample<100512;sample++) begin
      @(negedge clk);
      for(j=0;j<9;j++) begin
        rng=rng*32'd1664525+32'd1013904223;
        window[j]=(sample<512) ? ((sample>>j)&1 ? 255:0) : rng[31:24];
      end
      {w00,w01,w02,w10,w11,w12,w20,w21,w22}={window[0],window[1],window[2],window[3],window[4],window[5],window[6],window[7],window[8]};
      in_valid=(sample<512 || rng[3:0]!=0);
      gx=integer'(w02)+2*integer'(w12)+integer'(w22)-integer'(w00)-2*integer'(w10)-integer'(w20);
      gy=integer'(w20)+2*integer'(w21)+integer'(w22)-integer'(w00)-2*integer'(w01)-integer'(w02);
      ax=(gx<0)?-gx:gx; ay=(gy<0)?-gy:gy;
      for(i=3;i>0;i--) begin ev[i]=ev[i-1]; em[i]=em[i-1]; ed[i]=ed[i-1]; end
      ev[0]=in_valid; em[0]=ax+ay;
      ed[0]=(32*ay<=13*ax)?0:((32*ax<=13*ay)?2:(((gx<0)==(gy<0))?1:3));
      sum=integer'(w00)+2*integer'(w01)+integer'(w02)+2*integer'(w10)+4*integer'(w11)+2*integer'(w12)+integer'(w20)+2*integer'(w21)+integer'(w22);
      eg=(sum+8)/16;
      @(posedge clk); #1;
      if(gauss_valid !== ev[0] || (ev[0] && smooth !== 8'(eg))) $fatal(1,"Gaussian stress sample=%0d got=%0d expected=%0d",sample,smooth,eg);
      if(sample>=3 && (sobel_valid !== ev[3] || (ev[3] && (magnitude !== 11'(em[3]) || direction !== 2'(ed[3])))))
        $fatal(1,"Sobel stress sample=%0d got=%0d/%0d expected=%0d/%0d",sample,magnitude,direction,em[3],ed[3]);
      if(sample>=3 && ev[3]) checked++;
    end
    // Drain the final three Sobel results too.
    for(j=0;j<3;j++) begin
      @(negedge clk); in_valid=0;
      for(i=3;i>0;i--) begin ev[i]=ev[i-1]; em[i]=em[i-1]; ed[i]=ed[i-1]; end
      ev[0]=0;
      @(posedge clk); #1;
      if(sobel_valid !== ev[3] || (ev[3] && (magnitude !== 11'(em[3]) || direction !== 2'(ed[3])))) $fatal(1,"Sobel drain");
      if(ev[3]) checked++;
    end
    $display("PASS arithmetic: 512 binary extrema + 100000 random windows, Sobel accepted=%0d",checked); $finish;
  end
endmodule
`default_nettype wire
