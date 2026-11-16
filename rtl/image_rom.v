// =============================================================================
// image_rom.v
// Dual-port, read-only grayscale image memory, initialised from a .mem file.
//   Port A : used by the Sobel engine (sequential raster read)
//   Port B : used by the VGA display path (to show the original image)
// Both ports have 1-cycle registered read latency -> inferred as Block RAM.
// =============================================================================
`timescale 1ns / 1ps

module image_rom #(
    parameter DATA_W    = 8, //bit width of each pixel is 8 bits
    parameter DEPTH     = 320*240, //total number of pixels = 320 x 240 = 76,800
    parameter ADDR_W    = 17, //address bus width is 17 bits: 2^17 > 76,800
    parameter INIT_FILE = "image.mem"
)(
    input  wire              clk,
    input  wire [ADDR_W-1:0] addr_a, //17 bit address bus specifying the memory address to read from on port A (sobel engine)
    output reg  [DATA_W-1:0] q_a, //8 bit data bus hold the pixel value read from addr_a
    input  wire [ADDR_W-1:0] addr_b, //17 bit input address bus specifying the memory address to read from on port B (for VGA display)
    output reg  [DATA_W-1:0] q_b //8-bit output bus that holds pixel value read from addr_b
);

    (* rom_style = "block" *) reg [DATA_W-1:0] mem [0:DEPTH-1]; //implements this memory using dedicated on-chip block RAM primitive rather than eatng up LUTs           
                                                                // declares the actual 2D memory array named mem, consisting of 76,800 elements (0 to 76799), each 8 bits wide ([7:0])

    initial begin
        $readmemh(INIT_FILE, mem); //opens image.mem, reads its content as hexadecimal numbers and loads them sequentially into the mem array
    end

    always @(posedge clk) begin
        q_a <= mem[addr_a]; //Fetches the 8-bit pixel stored at index addr_a and schedules it to be stored in output register q_a
        q_b <= mem[addr_b]; //Simultaneously fetches the 8-bit pixel at index addr_b and updates output register q_b
    end

endmodule
