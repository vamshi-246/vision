`default_nettype none

package p7_pkg;
  parameter int unsigned IMG_W       = 640;
  parameter int unsigned IMG_H       = 480;
  parameter int unsigned H_FP        = 16;
  parameter int unsigned H_SYNC      = 96;
  parameter int unsigned H_BP        = 48;
  parameter int unsigned V_FP        = 10;
  parameter int unsigned V_SYNC      = 2;
  parameter int unsigned V_BP        = 33;
  parameter int unsigned H_TOTAL     = IMG_W + H_FP + H_SYNC + H_BP;
  parameter int unsigned V_TOTAL     = IMG_H + V_FP + V_SYNC + V_BP;
  parameter int unsigned PIXEL_BITS  = 8;
  parameter int unsigned MAG_BITS    = 11;
  parameter int unsigned DIR_NUM     = 13;
  parameter int unsigned DIR_DEN     = 32;

  typedef enum logic [1:0] {
    DIR_H = 2'b00,
    DIR_DN = 2'b01,
    DIR_V = 2'b10,
    DIR_DP = 2'b11
  } direction_t;
endpackage

`default_nettype wire

