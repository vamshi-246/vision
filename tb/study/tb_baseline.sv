`timescale 1ns/1ps
module tb_baseline #(parameter W=40,H=30,parameter string BASE="x");
 logic clk=0,rst=1,in_valid=0,in_sof=0,in_eol=0;logic[7:0] in_gray=0;wire out_valid,edge_o;
 always #5 clk=~clk;
 baseline_top #(.IMG_W(W),.IMG_H(H),.THR(192)) dut(.*);
 reg[7:0] img[0:W*H-1];integer fd,n=0;
 always @(posedge clk) if(out_valid) begin $fwrite(fd,"%0d\n",edge_o);n++;end
 initial begin
  $readmemh({BASE,"/img.hex"},img);fd=$fopen({BASE,"/out.txt"},"w");
  repeat(4) @(posedge clk);rst<=0;
  for(int f=0;f<2;f++) begin
   for(int y=0;y<H;y++) for(int x=0;x<W;x++) begin
    @(posedge clk);in_valid<=1;in_gray<=img[y*W+x];in_sof<=(x==0&&y==0);in_eol<=(x==W-1);
   end
   @(posedge clk);in_valid<=0;in_sof<=0;in_eol<=0;repeat(20) @(posedge clk);
  end
  repeat(40) @(posedge clk);$fclose(fd);$display("BASELINE_OUT %0d",n);$finish;
 end
endmodule
