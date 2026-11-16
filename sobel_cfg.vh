// =============================================================================
// sobel_cfg.vh  --  image size for the whole project (RTL + testbench)
//
// This is the ONLY place to change the image size. Pick one pair and
// regenerate the .mem files with the same size:
//
//   Landscape (default):  IMG_W 320, IMG_H 240
//       python img2mem.py photo.jpg --width 320 --height 240
//       full screen: 2x scaled to 640x480
//
//   Portrait (phone photos, 9:16):  IMG_W 270, IMG_H 480
//       python img2mem.py photo.jpg --width 270 --height 480 --fit crop
//       full screen: 1:1, centred
//
// Limits: IMG_W <= 320 and IMG_H <= 480 (side-by-side mode must fit in
// 640x480), and IMG_W*IMG_H <= ~260,000 so both buffers fit in block RAM.
// The display scales 2x automatically when the image is small enough
// (IMG_W <= 320 and IMG_H <= 240), otherwise 1:1.
// =============================================================================
`ifndef SOBEL_CFG_VH
`define SOBEL_CFG_VH

`define IMG_W 320
`define IMG_H 240

`endif
