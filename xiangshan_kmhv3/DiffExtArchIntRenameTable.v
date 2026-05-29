
`ifndef SYNTHESIS
`ifdef DIFFTEST
`include "DifftestMacros.svh"
`endif // DIFFTEST
`endif // SYNTHESIS
module DiffExtArchIntRenameTable(
  input         clock,
  input         enable,
  input  [ 7:0] io_value_0,
  input  [ 7:0] io_value_1,
  input  [ 7:0] io_value_2,
  input  [ 7:0] io_value_3,
  input  [ 7:0] io_value_4,
  input  [ 7:0] io_value_5,
  input  [ 7:0] io_value_6,
  input  [ 7:0] io_value_7,
  input  [ 7:0] io_value_8,
  input  [ 7:0] io_value_9,
  input  [ 7:0] io_value_10,
  input  [ 7:0] io_value_11,
  input  [ 7:0] io_value_12,
  input  [ 7:0] io_value_13,
  input  [ 7:0] io_value_14,
  input  [ 7:0] io_value_15,
  input  [ 7:0] io_value_16,
  input  [ 7:0] io_value_17,
  input  [ 7:0] io_value_18,
  input  [ 7:0] io_value_19,
  input  [ 7:0] io_value_20,
  input  [ 7:0] io_value_21,
  input  [ 7:0] io_value_22,
  input  [ 7:0] io_value_23,
  input  [ 7:0] io_value_24,
  input  [ 7:0] io_value_25,
  input  [ 7:0] io_value_26,
  input  [ 7:0] io_value_27,
  input  [ 7:0] io_value_28,
  input  [ 7:0] io_value_29,
  input  [ 7:0] io_value_30,
  input  [ 7:0] io_value_31,
  input  [ 7:0] io_coreid
);
  wire _dummy_unused = 1'b1;
`ifndef SYNTHESIS
`ifdef DIFFTEST
`ifndef CONFIG_DIFFTEST_FPGA

import "DPI-C" function void v_difftest_ArchIntRenameTable (
  input      byte io_value_0,
  input      byte io_value_1,
  input      byte io_value_2,
  input      byte io_value_3,
  input      byte io_value_4,
  input      byte io_value_5,
  input      byte io_value_6,
  input      byte io_value_7,
  input      byte io_value_8,
  input      byte io_value_9,
  input      byte io_value_10,
  input      byte io_value_11,
  input      byte io_value_12,
  input      byte io_value_13,
  input      byte io_value_14,
  input      byte io_value_15,
  input      byte io_value_16,
  input      byte io_value_17,
  input      byte io_value_18,
  input      byte io_value_19,
  input      byte io_value_20,
  input      byte io_value_21,
  input      byte io_value_22,
  input      byte io_value_23,
  input      byte io_value_24,
  input      byte io_value_25,
  input      byte io_value_26,
  input      byte io_value_27,
  input      byte io_value_28,
  input      byte io_value_29,
  input      byte io_value_30,
  input      byte io_value_31,
  input      byte io_coreid
);


  always @(posedge clock) begin
    if (enable)
      v_difftest_ArchIntRenameTable (io_value_0, io_value_1, io_value_2, io_value_3, io_value_4, io_value_5, io_value_6, io_value_7, io_value_8, io_value_9, io_value_10, io_value_11, io_value_12, io_value_13, io_value_14, io_value_15, io_value_16, io_value_17, io_value_18, io_value_19, io_value_20, io_value_21, io_value_22, io_value_23, io_value_24, io_value_25, io_value_26, io_value_27, io_value_28, io_value_29, io_value_30, io_value_31, io_coreid);
  end
`endif // CONFIG_DIFFTEST_FPGA
`endif // DIFFTEST
`endif // SYNTHESIS
endmodule