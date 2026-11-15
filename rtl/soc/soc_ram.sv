`default_nettype none
// True dual-port 32-bit RAM with byte enables and synchronous (read-first) reads; infers block RAM.
// Port A = CPU side, port B = host (JTAG-to-AXI) side.  Contents are zero at configuration.
module soc_ram #(parameter integer DEPTH=2048,parameter integer AW=11)(
 input wire clk,
 input wire a_en,input wire [3:0] a_we,input wire [AW-1:0] a_addr,input wire [31:0] a_wdata,output logic [31:0] a_rdata,
 input wire b_en,input wire [3:0] b_we,input wire [AW-1:0] b_addr,input wire [31:0] b_wdata,output logic [31:0] b_rdata);
 (* ram_style="block" *) logic [31:0] mem [0:DEPTH-1];
 initial for(int i=0;i<DEPTH;i++) mem[i]=32'd0;
 always_ff @(posedge clk) if(a_en) begin
  a_rdata<=mem[a_addr];
  for(int k=0;k<4;k++) if(a_we[k]) mem[a_addr][8*k+:8]<=a_wdata[8*k+:8];
 end
 always_ff @(posedge clk) if(b_en) begin
  b_rdata<=mem[b_addr];
  for(int k=0;k<4;k++) if(b_we[k]) mem[b_addr][8*k+:8]<=b_wdata[8*k+:8];
 end
endmodule
`default_nettype wire
