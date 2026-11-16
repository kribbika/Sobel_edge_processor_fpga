// =============================================================================
// frame_buffer.v
// Simple dual-port RAM that holds the Sobel edge-magnitude image.
//   Port A : write-only (Sobel engine)
//   Port B : read-only  (VGA display), 1-cycle registered read latency
// Single clock domain -> inferred as Block RAM (SDP mode).
// =============================================================================
`timescale 1ns / 1ps

module frame_buffer #(
    parameter DATA_W = 8,
    parameter DEPTH  = 320*240,
    parameter ADDR_W = 17
)(
    input  wire              clk,
    // write port
    input  wire              we, //write enable - active high control signal
    input  wire [ADDR_W-1:0] waddr,//17-bit bus specifying where in the buffer the Sobel engine wants to store the computed pixel
    input  wire [DATA_W-1:0] wdata,//8-bit bus carrying the actual Sobel edge-magnitude pixel value to be stored.
    // read port
    input  wire [ADDR_W-1:0] raddr,//17-bit bus driven by the VGA display controller requesting the pixel for the current screen coordinate
    output reg  [DATA_W-1:0] rdata//8-bit registered output that sends the requested pixel value out to the VGA display logic
);

    (* ram_style = "block" *) reg [DATA_W-1:0] mem [0:DEPTH-1]; 
    
    always @(posedge clk) begin
        if (we)
            mem[waddr] <= wdata; //wdata is written into the memory array at index waddr
        rdata <= mem[raddr]; //the byte at mem[raddr] is latched into the rdata output register
    end

endmodule
