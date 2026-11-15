`timescale 1ns/1ps
module tb_hdmi_timing;
`ifdef HDMI_IDEAL_CLOCKS
 // Optional diagnostic partition: drive only MMCM clock-output source nets.
 // BUFGs, the clock tree, datapath, SERDES and pin delays remain annotated.
 reg ideal_pixel=0,ideal_serial=0;
 always #19.858156 ideal_pixel=~ideal_pixel;
 always #3.9716312 ideal_serial=~ideal_serial;
 initial begin
  force dut.clocks.inst.clk_out1_video_clocks=ideal_pixel;
  force dut.clocks.inst.clk_out2_video_clocks=ideal_serial;
 end
`endif
 logic clk=0;logic[3:0] sw=0,btn=1;
 wire eth_rst_b,hdmi_out_en;wire[3:0] led;wire hdmi_tx_clk_p,hdmi_tx_clk_n;wire[2:0] hdmi_tx_p,hdmi_tx_n;
 zybo_hdmi_top dut(.*);
 always #4 clk=~clk;
 integer words=0,active=0,controls=0,i,lane;
 reg[9:0] symbol[0:2];reg[7:0] decoded[0:2];
 function automatic bit control(input reg[9:0] s);
  return s==10'b1101010100 || s==10'b0010101011 || s==10'b0101010100 || s==10'b1010101011;
 endfunction
 function automatic [7:0] decode(input reg[9:0] s);
  reg[7:0] q,d;
  begin
   q=s[9] ? ~s[7:0]:s[7:0];d[0]=q[0];
   for(integer j=1;j<8;j++) d[j]=s[8] ? (q[j]^q[j-1]):~(q[j]^q[j-1]);
   return d;
  end
 endfunction
 initial begin #1000;btn=0;end
 // Clock lane falls at bit zero of its 0000011111 serialized word.
 initial begin
  #20000;
  forever begin
   @(negedge hdmi_tx_clk_p);
   for(i=0;i<10;i++) begin
    #2;
    for(lane=0;lane<3;lane++) symbol[lane][i]=hdmi_tx_p[lane];
    #2;
   end
   words++;
   if(control(symbol[0])) begin
    if(symbol[1]!==10'b1101010100 || symbol[2]!==10'b1101010100) $fatal(1,"bad TMDS blanking %h %h %h",symbol[0],symbol[1],symbol[2]);
    controls++;
   end else begin
    for(lane=0;lane<3;lane++) decoded[lane]=decode(symbol[lane]);
    if(decoded[0]!==decoded[1] || decoded[1]!==decoded[2] ||
       !(decoded[0]===8'd24 || decoded[0]===8'd160 || decoded[0]===8'd220))
      $fatal(1,"TMDS decoded RGB invalid %h %h %h symbols=%h/%h/%h",decoded[2],decoded[1],decoded[0],symbol[2],symbol[1],symbol[0]);
    active++;
   end
   if(active>=2000 && controls>=200) begin
    if(led[0]!==1'b1 || led[3]!==1'b0) $fatal(1,"clock lock/alignment LED");
    $display("PASS routed TMDS timing: words=%0d active=%0d controls=%0d, three lanes decoded",words,active,controls);$finish;
   end
  end
 end
 initial begin #100000;
  if(words==0) $fatal(1,"TMDS clock startup failed LED=%b rst=%b tx_rst=%b",led,dut.rst,dut.tx_rst);
 end
 initial begin #600000;$fatal(1,"TMDS watchdog active=%0d controls=%0d",active,controls);end
endmodule
