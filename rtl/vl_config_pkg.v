// ============================================================
// vl_config_pkg.v
//
// M4-A shared VL configuration parameters.
//
// NOTE:
// The project baseline is Verilog-2001, which has no
// `package` / `endpackage` (SystemVerilog). Shared parameters
// are therefore provided as preprocessor macros and pulled in
// with `include.
//
// Expand to more VLs by changing VL_NUM only (and widening the
// VL-id bus accordingly).
// ============================================================

`define VL_NUM          4
`define BAG_WIDTH       32
`define LMAX_WIDTH      16
`define PRIORITY_WIDTH  2
`define DEST_WIDTH      8
