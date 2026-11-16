// =============================================================================
// sobel_top.v  --  Nexys A7-100T top level
//
// Image size is set in sobel_cfg.vh (one place for RTL and testbench).
// The image is stored in image.mem and baked into Block RAM at bitstream
// time. After reset the Sobel engine computes the edge image into a frame
// buffer (a few ms), and the VGA path displays it at 640x480@60.
//
// Display layout (derived from the image size):
//   full screen  : 2x scaled if the image fits (W<=320, H<=240), else 1:1,
//                  centred on the screen
//   side by side : 1:1, original left, edges right, centred
//
// Controls
//   CPU_RESETN   reset + re-run edge detection
//   BTNC         re-run edge detection (when LED0 is lit)
//   SW[0]        0 = show edges, 1 = show original        (full-screen mode)
//   SW[1]        0 = full screen
//                1 = side-by-side (original left, edges right)
//   SW[2]        1 = binary threshold on edge image
//   SW[3]        1 = invert edge image (black edges on white)
//   SW[15:8]     threshold value (used when SW[2]=1)
//
// LEDs
//   LED[0]       edge detection done
//   LED[1]       engine busy
//   LED[15:8]    mirror of threshold switches
// =============================================================================
`timescale 1ns / 1ps
`include "sobel_cfg.vh"

module sobel_top #(
    parameter IMG_W     = `IMG_W,
    parameter IMG_H     = `IMG_H,
    parameter INIT_FILE = "image.mem"
)(
    input  wire        CLK100MHZ, //100 MHz board oscillator
    input  wire        CPU_RESETN, //Red CPU RESET button, active-low (it reads 0 when pressed)
    input  wire        BTNC, //	Centre push-button
    input  wire [15:0] SW, //The 16 slide switches
    output wire [15:0] LED, //The 16 LEDs above the switches
    output reg  [3:0]  VGA_R, //4 bits per colour, going to the board's resistor-ladder DAC
    output reg  [3:0]  VGA_G,
    output reg  [3:0]  VGA_B,
    output reg         VGA_HS,//Horizontal and vertical sync
    output reg         VGA_VS
);

    wire clk = CLK100MHZ;

    localparam NPIX   = IMG_W * IMG_H;
    localparam ADDR_W = $clog2(NPIX);

    // ---------------------------------------------------------------- display layout
    localparam SCALE = (2*IMG_W <= 640 && 2*IMG_H <= 480) ? 2 : 1; //If the image still fits on the 640×480 screen when doubled in size, it is shown at 2× scale. Otherwise it is shown at 1:1
    //FS_W and FS_H are the size of the image on screen in full-screen mode
    localparam FS_W  = SCALE * IMG_W,      FS_H  = SCALE * IMG_H;
    //FS_X0 and FS_Y0 are its top-left corner, chosen so the image is centred
    localparam FS_X0 = (640 - FS_W) / 2,   FS_Y0 = (480 - FS_H) / 2;     // full screen
    //This is the top-left corner in side-by-side mode
    localparam SS_X0 = (640 - 2*IMG_W) / 2, SS_Y0 = (480 - IMG_H) / 2;   // side by side

    // ---------------------------------------------------------------- reset / button sync
    reg [1:0] rst_sync = 2'b11;          // power-up value forces an initial run
    always @(posedge clk)
        rst_sync <= {rst_sync[0], ~CPU_RESETN};
    wire rst = rst_sync[1];
    
    //btn_sync[0] and btn_sync[1] are the two-flip-flop synchronizer.
    //btn_sync[2] is the value from one clock earlier
    reg [2:0] btn_sync = 3'b000;
    always @(posedge clk)
        btn_sync <= {btn_sync[1:0], BTNC};
    //start pulse - high when the signal is 1 now and was 0 one clock ago. That is a rising edge, so pressing the button gives a pulse exactly one clock wide
    wire start_pulse = btn_sync[1] & ~btn_sync[2];

    //This registers the switches once into the clock domain
    reg [15:0] sw_r = 16'd0;              // switches are asynchronous
    always @(posedge clk)
        sw_r <= SW;

    // ---------------------------------------------------------------- memories
    //the Sobel engine reads the original image through these.
    wire [ADDR_W-1:0] eng_rom_addr;
    wire [7:0]        eng_rom_data;
    //the Sobel engine writes edge pixels into the frame buffer through these
    wire              fb_we;
    wire [ADDR_W-1:0] fb_waddr;
    wire [7:0]        fb_wdata;

    //one shared read address used by the display
    reg  [ADDR_W-1:0] disp_addr;
    //the original pixel and the edge pixel read out at that same address
    wire [7:0]        disp_orig;
    wire [7:0]        disp_edge;

    image_rom #(
        .DATA_W(8), .DEPTH(NPIX), .ADDR_W(ADDR_W), .INIT_FILE(INIT_FILE)
    ) u_rom (
        .clk   (clk),
        .addr_a(eng_rom_addr), .q_a(eng_rom_data),
        .addr_b(disp_addr),    .q_b(disp_orig)
    );

    frame_buffer #(
        .DATA_W(8), .DEPTH(NPIX), .ADDR_W(ADDR_W)
    ) u_fb (
        .clk  (clk),
        .we   (fb_we), .waddr(fb_waddr), .wdata(fb_wdata),
        .raddr(disp_addr), .rdata(disp_edge)
    );

    // ---------------------------------------------------------------- Sobel engine
    wire eng_busy, eng_done;

    sobel_engine #(
        .IMG_W(IMG_W), .IMG_H(IMG_H), .ADDR_W(ADDR_W)
    ) u_sobel (
        .clk     (clk),
        .rst     (rst),
        .start   (start_pulse),
        .rom_addr(eng_rom_addr),
        .rom_data(eng_rom_data),
        .fb_we   (fb_we),
        .fb_waddr(fb_waddr),
        .fb_wdata(fb_wdata),
        .busy    (eng_busy),
        .done    (eng_done)
    );

    // ---------------------------------------------------------------- VGA
    wire       pix_tick;
    wire [9:0] hcount, vcount;
    wire       hs_raw, vs_raw, von_raw;

    vga_timing u_vga (
        .clk(clk), .rst(rst),
        .pix_tick(pix_tick),
        .hcount(hcount), .vcount(vcount),
        .hsync(hs_raw), .vsync(vs_raw), .video_on(von_raw)
    );

    // Stage A (comb): map screen coordinate -> image coordinate + source select
    reg  [9:0] img_x, img_y;
    reg        in_img;
    reg        sel_edge;

    always @* begin
        img_x    = 10'd0;          // keep the address in range outside the image
        img_y    = 10'd0;
        in_img   = 1'b0;
        sel_edge = ~sw_r[0];
        if (!sw_r[1]) begin //Full screen (SW[1] = 0)
            // full screen (SCALE x SCALE screen pixels per image pixel)
            if (hcount >= FS_X0 && hcount < FS_X0 + FS_W &&
                vcount >= FS_Y0 && vcount < FS_Y0 + FS_H) begin
                in_img = 1'b1;
                img_x  = (hcount - FS_X0) / SCALE;
                img_y  = (vcount - FS_Y0) / SCALE;
            end
        end else begin
            // side by side, 1:1
            if (hcount >= SS_X0 && hcount < SS_X0 + 2*IMG_W &&
                vcount >= SS_Y0 && vcount < SS_Y0 + IMG_H) begin
                in_img = 1'b1;
                img_y  = vcount - SS_Y0;
                if (hcount < SS_X0 + IMG_W) begin
                    img_x    = hcount - SS_X0;
                    sel_edge = 1'b0;
                end else begin
                    img_x    = hcount - SS_X0 - IMG_W;
                    sel_edge = 1'b1;
                end
            end
        end
    end

    // Stage 1: register image coordinate
    // Stage 2: read address = y*IMG_W + x
    // Stage 3: BRAM output
    // Stage 4: pixel formatting -> pix_r (register placed next to the BRAMs)
    // Stage 5: pix_r -> output registers (packed in the IOBs)
    // Sync / control signals are delayed to line up with the data.
    reg [9:0] img_x_r, img_y_r;
    reg [3:0] hs_d, vs_d, in_d, sel_d;

    always @(posedge clk) begin
        img_x_r   <= img_x;
        img_y_r   <= img_y;
        disp_addr <= img_y_r * IMG_W + img_x_r;
        hs_d  <= {hs_d[2:0],  hs_raw};
        vs_d  <= {vs_d[2:0],  vs_raw};
        in_d  <= {in_d[2:0],  in_img};
        sel_d <= {sel_d[2:0], sel_edge};
    end

    // pixel formatting (uses stage-3 BRAM data)
    reg [7:0] edge_px, pix;
    always @* begin
        edge_px = disp_edge;
        if (sw_r[2])
            edge_px = (disp_edge >= sw_r[15:8]) ? 8'hFF : 8'h00;
        if (sw_r[3])
            edge_px = ~edge_px;
        pix = sel_d[2] ? edge_px : disp_orig;
    end

    reg [3:0] pix_r;
    always @(posedge clk)
        pix_r <= pix[7:4];

    always @(posedge clk) begin
        VGA_HS <= hs_d[3];
        VGA_VS <= vs_d[3];
        if (in_d[3]) begin
            VGA_R <= pix_r;
            VGA_G <= pix_r;
            VGA_B <= pix_r;
        end else begin
            VGA_R <= 4'h0;
            VGA_G <= 4'h0;
            VGA_B <= 4'h0;
        end
    end

    // ---------------------------------------------------------------- LEDs
    assign LED = {sw_r[15:8], 6'd0, eng_busy, eng_done};

endmodule
