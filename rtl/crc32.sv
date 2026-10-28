`default_nettype none

// CRC-32/IEEE of raster-order edge bytes: 8'hff for edge, 8'h00 otherwise.
// The final complement and reflected polynomial match Python zlib.crc32.
module crc32 (
  input  logic        clk,
  input  logic        rst,
  input  logic        frame_start,
  input  logic        pixel_valid,
  input  logic        pixel_edge,
  input  logic        frame_end,
  output logic [31:0] crc_out,
  output logic        crc_valid
);
  function automatic logic [31:0] update_byte(
    input logic [31:0] crc_in,
    input logic [7:0] data
  );
    logic [31:0] crc;
    integer bit_idx;
    begin
      crc = crc_in ^ data;
      for (bit_idx = 0; bit_idx < 8; bit_idx = bit_idx + 1) begin
        crc = crc[0] ? ((crc >> 1) ^ 32'hEDB88320) : (crc >> 1);
      end
      update_byte = crc;
    end
  endfunction

  logic [31:0] crc_state;
  logic [31:0] crc_input;
  logic [31:0] crc_next;

  always_comb begin
    crc_input = frame_start ? 32'hFFFF_FFFF : crc_state;
    crc_next = update_byte(crc_input, pixel_edge ? 8'hFF : 8'h00);
  end

  always_ff @(posedge clk) begin
    if (rst) begin
      crc_state <= 32'hFFFF_FFFF;
      crc_out <= '0;
      crc_valid <= 1'b0;
    end else begin
      crc_valid <= 1'b0;
      if (pixel_valid) begin
        crc_state <= crc_next;
        if (frame_end) begin
          crc_out <= ~crc_next;
          crc_valid <= 1'b1;
        end
      end
    end
  end
endmodule

`default_nettype wire
