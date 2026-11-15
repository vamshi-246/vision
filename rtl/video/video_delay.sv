`default_nettype none
// No reset on storage: Vivado infers SRLs. Consumer masks startup samples.
module video_delay #(parameter integer WIDTH=8, DEPTH=1)(
 input wire clk,input wire [WIDTH-1:0] din,output wire [WIDTH-1:0] dout);
 for(genvar b=0;b<WIDTH;b++) begin: bits_delay
  // All inputs originate in this pixel domain and settle after its rising
  // edge. Sample midway through the cycle to avoid a very short path into
  // the first SRL; the next rising-edge sample has the same logical value.
  logic sample;
  always_ff @(negedge clk) sample<=din[b];
  (* shreg_extract="yes" *) logic [DEPTH-1:0] pipe;
  if(DEPTH==1) always_ff @(posedge clk) pipe<=sample;
  else always_ff @(posedge clk) pipe<={pipe[DEPTH-2:0],sample};
  assign dout[b]=pipe[DEPTH-1];
 end
endmodule
`default_nettype wire
