// =============================================================================
// sobel_engine.v
// Streaming 3x3 Sobel edge detector.
//
// Reads the source image from ROM in raster order (one pixel per clock),
// builds a 3x3 sliding window with two line buffers, computes
//
//        Gx = [-1 0 +1]        Gy = [-1 -2 -1]
//             [-2 0 +2]             [ 0  0  0]
//             [-1 0 +1]             [+1 +2 +1]
//
//        |G| ~= |Gx| + |Gy|, saturated to 255
//
// and writes the magnitude into the frame buffer. Border pixels (first/last
// row and column) are 0: the buffer is cleared before every run.
//
// Pipeline (one pixel per clock, no stalls):
//   S0  raster counters drive ROM address + line-buffer read address
//   S1  ROM data + line-buffer data arrive (column {y-2, y-1, y})
//   S2  3x3 window registers (line buffers updated)
//   S3  Gx, Gy (signed 11-bit)
//   S4  |Gx|+|Gy|, saturate to 8 bits
//   S5  frame-buffer write (registered outputs)
//
// The output pixel for window centre (x-1, y-1) is written at address
// (y*W + x) - W - 1, i.e. the newest pixel's address minus W+1.
//
// Run time at 100 MHz for 320x240: clear 76,800 + process 76,800 cycles
// ~= 1.54 ms.
// =============================================================================
`timescale 1ns / 1ps

module sobel_engine #(
    parameter IMG_W  = 320,
    parameter IMG_H  = 240,
    parameter ADDR_W = 17
)(
    input  wire              clk,
    input  wire              rst,        // synchronous, active high reset-> starts a fresh processing run
    input  wire              start,      // 1-cycle pulse: re-run when DONE

    // source image ROM (1-cycle read latency)
    output reg  [ADDR_W-1:0] rom_addr, //The engine outputs this memory address to request a specific raw pixel from the source image memory (ROM).
    input  wire [7:0]        rom_data,  //The ROM responds one clock cycle later with the 8-bit grayscale pixel value located at that address.

    // edge frame buffer write port
    output reg               fb_we,//The engine drives this signal high (1) when it has successfully computed an edge pixel and wants to save it
    output reg  [ADDR_W-1:0] fb_waddr, //The destination address in the output memory (Frame Buffer RAM) where the processed pixel belongs.
    output reg  [7:0]        fb_wdata, //The 8-bit calculated edge magnitude (the result of the Sobel math) that is written into the memory.

    output wire              busy, //tells rest of the system if engine is currently working
    output wire              done // or finished
);

    localparam NPIX = IMG_W * IMG_H; //76,800 pixels
    localparam XW   = $clog2(IMG_W); //9 bits
    localparam YW   = $clog2(IMG_H); //8 bits

    //4 FSM states:
    localparam [2:0] S_CLEAR = 3'd0, //zeroes the frame buffer before processing a new image
                     S_RUN   = 3'd1, //streams the image
                                     // The engine sequentially reads raw pixels from the source ROM, feeds them into the sliding window pipeline, calculates the edge magnitudes, and writes the results to the frame buffer
                     S_FLUSH = 3'd2, //waits for the pipeline to empty
                                     //This state forces the controller to wait a few extra clock cycles to allow the very last pixels to finish their math calculations and be safely written to memory before shutting down.
                     S_DONE  = 3'd3; //The processing is completely finished

    reg [2:0] state; // This 3-bit register stores the current state of the FSM
    reg [3:0] flush_cnt; //A 4-bit counter (counting from 0 to 15) used exclusively during the S_FLUSH state
    reg [ADDR_W-1:0] clr_addr; //During the S_CLEAR state, this register acts as a counter that sequentially steps through every single address in the frame buffer so the engine can write a 0 to each location, wiping it clean

    assign done = (state == S_DONE); //This continuously updates the done output signal
                                     //It will output a 1 (true) only when the state register exactly matches the S_DONE phase
    assign busy = ~done;

    // ------------------------------------------------------------------ S0
    reg [XW-1:0] x0; //x0/y0 are the column/row of the pixel whose address is currently on rom_addr
    reg [YW-1:0] y0; //these are the engine's raster-scan counters
    wire         v0 = (state == S_RUN); //"Valid" flag for Stage 0. High only when actively streaming pixels (S_RUN)

    // ------------------------------------------------------------------ FSM
    always @(posedge clk) begin
        //If rst is high, all counters and addresses reset to 0 and the FSM enters S_CLEAR
        if (rst) begin
            state     <= S_CLEAR;
            clr_addr  <= 0;
            x0        <= 0;
            y0        <= 0;
            rom_addr  <= 0;
            flush_cnt <= 0;
        end else begin
            //Increments clr_addr from 0 to 76,799. Once every address in the frame buffer has been zeroed out, it resets coordinates and transitions to S_RUN
            case (state)
            S_CLEAR: begin
                if (clr_addr == NPIX-1) begin
                    clr_addr <= 0;
                    x0       <= 0;
                    y0       <= 0;
                    rom_addr <= 0;
                    state    <= S_RUN;
                end else
                    clr_addr <= clr_addr + 1'b1;
            end
            //On every clock tick it moves to the next pixel: left to right, and at the end of a line you drop to the start of the next one
            S_RUN: begin
                rom_addr <= rom_addr + 1'b1;
                if (x0 == IMG_W-1) begin
                    x0 <= 0;
                    if (y0 == IMG_H-1) begin
                        y0        <= 0;
                        flush_cnt <= 0;
                        state     <= S_FLUSH;
                    end else
                        y0 <= y0 + 1'b1;
                end else
                    x0 <= x0 + 1'b1;
            end
            //The engine sits here for a few ticks so the last pixels can finish going through the pipeline
            S_FLUSH: begin   // let the pipeline drain
                flush_cnt <= flush_cnt + 1'b1;
                if (flush_cnt == 4'd7)
                    state <= S_DONE;
            end
            //The edge image is done and sitting in the frame buffer. The engine stays idle until someone tells it to run again.
            S_DONE: begin
                if (start) begin
                    clr_addr <= 0;
                    state    <= S_CLEAR;
                end
            end
            default: state <= S_CLEAR;
            endcase
        end
    end

    // ------------------------------------------------------------------ line buffers
    // lb0 holds row y-1, lb1 holds row y-2. Synchronous read at x0 so the data
    // lines up with the ROM output in S1; write at x1 in S1.
    
    //instructing the FPGA tool to implement these small arrays using LUT-RAM (distributed RAM) instead of dedicated Block RAM
    //Two line buffers, each 320 bytes wide. lb0 stores row y-1; lb1 stores row y-2.
    (* ram_style = "distributed" *) reg [7:0] lb0 [0:IMG_W-1]; 
    (* ram_style = "distributed" *) reg [7:0] lb1 [0:IMG_W-1];
    
    //Output registers holding the pixels read from the line buffers.
    reg [7:0] lb0_q, lb1_q;

    //Simulation/FPGA power-on initialization clearing both line buffers to 0
    integer i;
    initial begin
        for (i = 0; i < IMG_W; i = i + 1) begin
            lb0[i] = 8'd0;
            lb1[i] = 8'd0;
        end
    end

    // ------------------------------------------------------------------ S1
    reg              v1;
    reg [XW-1:0]     x1;
    reg [YW-1:0]     y1;
    reg [ADDR_W-1:0] a1;

    always @(posedge clk) begin
        lb0_q <= lb0[x0]; //Performs a synchronous read from the two line buffers at the current column x0
        lb1_q <= lb1[x0];
        v1    <= v0 & ~rst; //: Propagates the valid flag (v0) forward to Stage 1, gating it with ~rst so any in-flight pixel is immediately invalidated on reset
        x1    <= x0; //Delays the pixel's (x, y) coordinates by one clock cycle so they stay aligned with the fetched pixel data (rom_data, lb0_q, lb1_q) as it enters Stage 2
        y1    <= y0;
        a1    <= rom_addr; //Carries the target write address forward alongside the pixel
    end

    // ------------------------------------------------------------------ S2 (window)
    //Nine 8-bit registers forming the 3x3 pixel matrix
    // p<row><col>: row 0 = top (y-2), col 2 = newest (x)
    reg [7:0] p00, p01, p02,
              p10, p11, p12,
              p20, p21, p22;
    reg              v2;
    reg [XW-1:0]     x2;
    reg [YW-1:0]     y2;
    reg [ADDR_W-1:0] a2; //memory address of the centre pixel in the 3×3 Sobel window

    always @(posedge clk) begin
        if (v1) begin
            lb0[x1] <= rom_data;   // current row becomes "previous row"
            lb1[x1] <= lb0_q;      // previous row becomes "row before"

            //All three rows shift left, , and the newest column enters on the right
            p00 <= p01;  p01 <= p02;  p02 <= lb1_q;
            p10 <= p11;  p11 <= p12;  p12 <= lb0_q;
            p20 <= p21;  p21 <= p22;  p22 <= rom_data;
        end
        v2 <= v1 & ~rst;
        x2 <= x1;
        y2 <= y1;
        a2 <= a1;
    end

    // ------------------------------------------------------------------ S3 (gradients)
    //Combinational wires computing the positive and negative halves of the Sobel kernels
    wire [9:0] gx_pos = p02 + {p12, 1'b0} + p22;
    wire [9:0] gx_neg = p00 + {p10, 1'b0} + p20;
    wire [9:0] gy_pos = p20 + {p21, 1'b0} + p22;
    wire [9:0] gy_neg = p00 + {p01, 1'b0} + p02;

    reg signed [10:0] gx3, gy3; //Maximum possible sum is 255 + 510 + 255 = 1020, which fits cleanly in a 10-bit unsigned wire 
    reg               v3; //Marks the calculation valid only when x2 >= 2 and y2 >= 2
    reg [ADDR_W-1:0]  a3; // The newest pixel p22 is at (x2, y2), meaning the center of the 3x3 window (p11) is at (x2 - 1, y2 - 1)

    always @(posedge clk) begin
        gx3 <= $signed({1'b0, gx_pos}) - $signed({1'b0, gx_neg});
        gy3 <= $signed({1'b0, gy_pos}) - $signed({1'b0, gy_neg});
        // window is complete only from the 3rd column / 3rd row onwards
        v3  <= v2 && (x2 >= 2) && (y2 >= 2) && ~rst;
        a3  <= a2 - (IMG_W + 1);
    end

    // ------------------------------------------------------------------ S4 (magnitude)
    wire [10:0] abs_gx = gx3[10] ? -gx3 : gx3; //Checks the sign bit ([10]). If negative (1), takes the two's complement (-gx3) to get the absolute value
    wire [10:0] abs_gy = gy3[10] ? -gy3 : gy3;
    wire [11:0] mag    = abs_gx + abs_gy;

    reg [7:0]        mag4;
    reg              v4;
    reg [ADDR_W-1:0] a4;

    always @(posedge clk) begin
    //Clamps (saturates) any gradient sum above 255 down to 8'd255 so bright edges do not wrap around to black when truncated to 8 bits
        mag4 <= (mag > 12'd255) ? 8'd255 : mag[7:0];
        v4   <= v3 & ~rst;
        a4   <= a3;
    end

    // ------------------------------------------------------------------ S5 (Frame Buffer Write)
    always @(posedge clk) begin
        //During S_CLEAR, it continuously writes 0 (fb_we <= 1'b1) to every address clr_addr
        if (state == S_CLEAR && !rst) begin
            fb_we    <= 1'b1;
            fb_waddr <= clr_addr;
            fb_wdata <= 8'd0;
        //During S_RUN / S_FLUSH, it forwards the pipelined valid flag (v4), center pixel address (a4), and saturated edge value (mag4) to the output memory
        end else begin
            fb_we    <= v4;
            fb_waddr <= a4;
            fb_wdata <= mag4;
        end
    end

endmodule
