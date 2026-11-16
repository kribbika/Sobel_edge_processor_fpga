// =============================================================================
// vga_timing.v
// 640x480 @ 60 Hz VGA timing generator.
// Runs from the 100 MHz system clock with a /4 pixel-clock enable (25 MHz),
// so the whole design stays in one clock domain and no clocking IP is needed.
//
//              visible  front  sync  back   total
//   horizontal   640     16     96    48  =  800 pixels
//   vertical     480     10      2    33  =  525 lines
//   sync polarity: negative (both)
// =============================================================================
`timescale 1ns / 1ps

module vga_timing (
    input  wire       clk,       // 100 MHz
    input  wire       rst,       //While rst = 1, every register is forced to 0 on the next clock edge
    output reg        pix_tick,  // 1-cycle pulse every 4 clocks (25 MHz)
    output reg  [9:0] hcount,    // 0..799
    output reg  [9:0] vcount,    // 0..524
    output wire       hsync,     // active low, horizontal position counters
    output wire       vsync,     // active low, vertical position counters
    output wire       video_on   //tells your pixel logic whether it's in the visible area
);

    localparam H_VISIBLE = 640, H_FP = 16, H_SYNC = 96, H_BP = 48; //horizontal timing for one line, 640 visible pixels, a 16-pixel front porch, a 96-pixel sync pulse and a 48-pixel back porc
    localparam V_VISIBLE = 480, V_FP = 10, V_SYNC = 2,  V_BP = 33;
    localparam H_TOTAL   = H_VISIBLE + H_FP + H_SYNC + H_BP;   // 800
    localparam V_TOTAL   = V_VISIBLE + V_FP + V_SYNC + V_BP;   // 525

    reg [1:0] div; //A 2-bit counter used to divide the clock by 4

    //This block is a divide-by-4 clock enable generator. It takes the 100 MHz clock and produces pix_tick, a signal that is high for one clock cycle out of every four
    always @(posedge clk) begin
        if (rst) begin
            div      <= 2'd0;
            pix_tick <= 1'b0;
        end else begin
            div      <= div + 1'b1;
            pix_tick <= (div == 2'd3);
        end
    end

    //. It keeps track of which pixel the monitor is currently drawing, as an (x, y) position: hcount is the column and vcount is the line
    always @(posedge clk) begin
        if (rst) begin
            hcount <= 10'd0;
            vcount <= 10'd0;
        end else if (pix_tick) begin
            if (hcount == H_TOTAL-1) begin
                hcount <= 10'd0;
                vcount <= (vcount == V_TOTAL-1) ? 10'd0 : vcount + 1'b1;
            end else
                hcount <= hcount + 1'b1;
        end
    end

    //sync and blanking decoder
    //They read the current scan position (hcount, vcount) from the counters and produce the three control signals the monitor and your pixel logic need
    assign hsync    = ~((hcount >= H_VISIBLE + H_FP) &&
                        (hcount <  H_VISIBLE + H_FP + H_SYNC));
    assign vsync    = ~((vcount >= V_VISIBLE + V_FP) &&
                        (vcount <  V_VISIBLE + V_FP + V_SYNC));
    assign video_on = (hcount < H_VISIBLE) && (vcount < V_VISIBLE);

endmodule
