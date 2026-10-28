`default_nettype none

// The NMS selection part of D4. Direction is already quantised by sobel.sv;
// this module has no state and is the reference before Espresso minimisation.
module dirnms (
  input  logic [10:0] magnitude,
  input  logic [1:0]  direction,
  input  logic [10:0] mag_nw,
  input  logic [10:0] mag_n,
  input  logic [10:0] mag_ne,
  input  logic [10:0] mag_w,
  input  logic [10:0] mag_e,
  input  logic [10:0] mag_sw,
  input  logic [10:0] mag_s,
  input  logic [10:0] mag_se,
  output logic [10:0] nms_mag,
  output logic        keep
);
  logic [10:0] earlier;
  logic [10:0] later;

  always_comb begin
    unique case (direction)
      2'b00: begin earlier = mag_w;  later = mag_e;  end
      2'b01: begin earlier = mag_nw; later = mag_se; end
      2'b10: begin earlier = mag_n;  later = mag_s;  end
      default: begin earlier = mag_ne; later = mag_sw; end
    endcase
    keep = (magnitude != 0) && (magnitude >= earlier) && (magnitude > later);
    nms_mag = keep ? magnitude : '0;
  end
endmodule

`default_nettype wire

