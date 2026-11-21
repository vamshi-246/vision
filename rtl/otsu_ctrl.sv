`default_nettype none

// Control FSM of the streaming adaptive-Otsu unit (rtl/otsu_stream.sv is its datapath).
// Minimised STG (logic/fsm_otsu.py: the specification STG had a separate RECOVER state that the implication
// chart proved equivalent to INIT, so the two were merged):
//
//   INIT    clear both histogram banks; counting off                          cdone            -> ARM
//   ARM     wait for the first pixel of a frame                               en & sof         -> COLLECT
//   COLLECT histogram of the current frame                                    !en -> INIT;  eof -> SWEEP
//   SWEEP   Otsu sweep of the finished bank, next frame being counted        odone            -> CLEAR
//   CLEAR   zero the finished bank                                            cdone: ovr|!en -> INIT,
//                                                                             px -> PEND, else -> COLLECT (apply)
//   PEND    result waits for a frame boundary                                 !en -> INIT;  eof -> SWEEP (apply)
//
// The state codes are parameters so that a hand-chosen encoding can be synthesised with FSM extraction off
// (logic/fsm_encodings.py); the default is plain binary in declaration order.
module otsu_ctrl #(
  parameter logic [2:0] C_INIT = 3'd0, C_ARM = 3'd1, C_COLLECT = 3'd2,
  parameter logic [2:0] C_SWEEP = 3'd3, C_CLEAR = 3'd4, C_PEND = 3'd5
) (
  input  wire       clk,
  input  wire       rst,
  input  wire       en,       // adaptive mode enabled
  input  wire       sof,      // first NMS pixel of a frame
  input  wire       eof,      // last NMS pixel of a frame
  input  wire       odone,    // Otsu sweep finished (pulse)
  input  wire       cdone,    // 256-bin clear pass finished
  input  wire       px,       // a pixel of the next frame has been (or is being) classified
  input  wire       ovr,      // a frame ended while the previous one was still being swept/cleared
  output logic [2:0] state,
  output logic      count_en, // histogram counting enabled for this pixel
  output logic      clr_both, // clear both banks (INIT)
  output logic      clr_one,  // clear the swept bank (CLEAR)
  output logic      swap,     // swap banks and start the Otsu sweep (pulse)
  output logic      apply,    // load the Otsu result into the threshold registers (pulse)
  output logic      init_done, // INIT finished: reset bank totals and flags (pulse)
  output logic      sweeping   // SWEEP or CLEAR: a frame that ends now overruns
);
  logic [2:0] next;

  always_comb begin
    next = state;
    sweeping = (state == C_SWEEP) || (state == C_CLEAR);
    count_en = 1'b0; clr_both = 1'b0; clr_one = 1'b0; swap = 1'b0; apply = 1'b0; init_done = 1'b0;
    unique case (state)
      C_INIT: begin
        clr_both = 1'b1;
        if (cdone) begin next = C_ARM; init_done = 1'b1; end
      end
      C_ARM: if (en && sof) begin next = C_COLLECT; count_en = 1'b1; end
      C_COLLECT: begin
        count_en = 1'b1;
        if (!en) next = C_INIT;
        else if (eof) begin next = C_SWEEP; swap = 1'b1; end
      end
      C_SWEEP: begin
        count_en = 1'b1;
        if (odone) next = C_CLEAR;
      end
      C_CLEAR: begin
        count_en = 1'b1; clr_one = 1'b1;
        if (cdone) begin
          if (ovr || !en) next = C_INIT;
          else if (px) next = C_PEND;
          else begin next = C_COLLECT; apply = 1'b1; end
        end
      end
      C_PEND: begin
        count_en = 1'b1;
        if (!en) next = C_INIT;
        else if (eof) begin next = C_SWEEP; swap = 1'b1; apply = 1'b1; end
      end
      default: next = C_INIT;
    endcase
  end

  always_ff @(posedge clk) begin
    if (rst) state <= C_INIT;
    else     state <= next;
  end
endmodule

`default_nettype wire
