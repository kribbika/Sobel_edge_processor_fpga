// =============================================================================
// tb_sobel_top.v  --  self-checking testbench for the full design
//
// Test 1  Sobel engine : wait for LED[0] (done), compare every pixel of the
//                        frame buffer with expected_edge.mem (Python golden),
//                        dump the result to sim_edge_out.mem.
// Test 2  VGA timing   : measure HSYNC/VSYNC period and pulse widths.
// Test 3  VGA picture  : (CAPTURE_VGA=1) capture one full 640x480 frame from
//                        the VGA pins only, compare with the expected screen
//                        layout (full screen, or side by side when
//                        SIDE_BY_SIDE=1), write vga_frame.pgm.
//
// Image size comes from sobel_cfg.vh, same as the RTL.
//
// Simulated time: ~1.6 ms for test 1, ~35 ms total with CAPTURE_VGA=1.
// In Vivado: Simulation settings -> xsim.simulate.runtime = all
// =============================================================================
`timescale 1ns / 1ps
`include "sobel_cfg.vh"

module tb_sobel_top;

    parameter IMG_W        = `IMG_W;
    parameter IMG_H        = `IMG_H;
    parameter MEM_DIR      = "";     // e.g. "../mem/" for command-line sims
    parameter CAPTURE_VGA  = 1;
    parameter SIDE_BY_SIDE = 0;      // SW1 setting used for test 3

    localparam NPIX = IMG_W * IMG_H;

    // same layout rules as sobel_top
    localparam SCALE = (2*IMG_W <= 640 && 2*IMG_H <= 480) ? 2 : 1;
    localparam FS_W  = SCALE * IMG_W,       FS_H  = SCALE * IMG_H;
    localparam FS_X0 = (640 - FS_W) / 2,    FS_Y0 = (480 - FS_H) / 2;
    localparam SS_X0 = (640 - 2*IMG_W) / 2, SS_Y0 = (480 - IMG_H) / 2;

    // ------------------------------------------------------------- DUT
    reg         clk = 1'b0;
    reg         rstn = 1'b0;
    reg         btnc = 1'b0;
    reg  [15:0] sw = SIDE_BY_SIDE ? 16'h0002 : 16'h0000;   // edges, no threshold
    wire [15:0] led;
    wire [3:0]  vga_r, vga_g, vga_b;
    wire        vga_hs, vga_vs;

    always #5 clk = ~clk;            // 100 MHz

    sobel_top #(
        .IMG_W(IMG_W), .IMG_H(IMG_H),
        .INIT_FILE({MEM_DIR, "image.mem"})
    ) dut (
        .CLK100MHZ(clk), .CPU_RESETN(rstn), .BTNC(btnc), .SW(sw), .LED(led),
        .VGA_R(vga_r), .VGA_G(vga_g), .VGA_B(vga_b),
        .VGA_HS(vga_hs), .VGA_VS(vga_vs)
    );

    // ------------------------------------------------------------- golden data
    reg [7:0] expected [0:NPIX-1];
    reg [7:0] original [0:NPIX-1];
    initial begin
        $readmemh({MEM_DIR, "expected_edge.mem"}, expected);
        $readmemh({MEM_DIR, "image.mem"},         original);
    end

    // expected 4-bit value of screen pixel (sx, sy)
    function [3:0] exp_screen(input integer sx, input integer sy);
        begin
            exp_screen = 4'h0;
            if (!SIDE_BY_SIDE) begin
                if (sx >= FS_X0 && sx < FS_X0 + FS_W && sy >= FS_Y0 && sy < FS_Y0 + FS_H)
                    exp_screen = expected[((sy - FS_Y0) / SCALE) * IMG_W + (sx - FS_X0) / SCALE][7:4];
            end else begin
                if (sx >= SS_X0 && sx < SS_X0 + 2*IMG_W && sy >= SS_Y0 && sy < SS_Y0 + IMG_H) begin
                    if (sx < SS_X0 + IMG_W)
                        exp_screen = original[(sy - SS_Y0) * IMG_W + (sx - SS_X0)][7:4];
                    else
                        exp_screen = expected[(sy - SS_Y0) * IMG_W + (sx - SS_X0 - IMG_W)][7:4];
                end
            end
        end
    endfunction

    integer errors = 0;
    integer i, x, y;

    // ------------------------------------------------------------- Test 2 monitors
    realtime hs_fall_prev = 0, hs_period = 0, hs_low_start = 0, hs_width = 0;
    realtime vs_fall_prev = 0, vs_period = 0, vs_low_start = 0, vs_width = 0;
    integer  hs_count = 0, vs_count = 0;

    always @(negedge vga_hs) if (rstn) begin
        if (hs_fall_prev > 0) hs_period = $realtime - hs_fall_prev;
        hs_fall_prev = $realtime;
        hs_low_start = $realtime;
        hs_count     = hs_count + 1;
    end
    always @(posedge vga_hs) if (hs_low_start > 0) hs_width = $realtime - hs_low_start;

    always @(negedge vga_vs) if (rstn) begin
        if (vs_fall_prev > 0) vs_period = $realtime - vs_fall_prev;
        vs_fall_prev = $realtime;
        vs_low_start = $realtime;
        vs_count     = vs_count + 1;
    end
    always @(posedge vga_vs) if (vs_low_start > 0) vs_width = $realtime - vs_low_start;

    // ------------------------------------------------------------- Test 3: VGA capture
    // Reconstruct screen coordinates purely from the sync pins:
    // VSYNC falls on the first clock of pixel (h=0, v=490); a pixel lasts 4 clocks.
    reg  [3:0] frame [0:640*480-1];
    reg        synced = 0, capturing = 0, frame_done = 0;
    reg        vs_prev = 1;
    reg  [1:0] ph;
    integer    th, tv;

    always @(negedge clk) begin
        if (rstn && CAPTURE_VGA && !frame_done) begin
            if (vs_prev && !vga_vs) begin
                synced <= 1; ph <= 2'd1; th <= 0; tv <= 490;
            end else if (synced) begin
                ph <= ph + 1'b1;
                if (ph == 2'd3) begin
                    if (th == 799) begin
                        th <= 0;
                        tv <= (tv == 524) ? 0 : tv + 1;
                    end else
                        th <= th + 1;
                end
                // sample in the middle of each pixel
                if (ph == 2'd1) begin
                    if (tv == 0 && th == 0) capturing <= 1;
                    if ((capturing || (tv == 0 && th == 0)) && tv < 480 && th < 640) begin
                        frame[tv*640 + th] <= vga_r;
                        if (vga_r !== vga_g || vga_r !== vga_b) begin
                            if (errors < 10) $display("  VGA: R/G/B differ at (%0d,%0d)", th, tv);
                            errors = errors + 1;
                        end
                        if (tv == 479 && th == 639) frame_done <= 1;
                    end
                end
            end
            vs_prev <= vga_vs;
        end
    end

    // ------------------------------------------------------------- main sequence
    integer fd, mism;
    reg [7:0] got;

    initial begin
        if (SIDE_BY_SIDE)
            $display("=== Sobel / Nexys A7 testbench: %0dx%0d image, side by side ===", IMG_W, IMG_H);
        else
            $display("=== Sobel / Nexys A7 testbench: %0dx%0d image, full screen ===", IMG_W, IMG_H);
        repeat (20) @(posedge clk);
        rstn = 1'b1;

        // ---------------- Test 1
        fork : wait_done
            begin wait (led[0] === 1'b1); disable wait_done; end
            begin #5_000_000; $display("FAIL: timeout waiting for done"); $finish; end
        join
        $display("[%0t] edge detection done (%.3f ms)", $time, $realtime / 1.0e6);

        mism = 0;
        for (i = 0; i < NPIX; i = i + 1) begin
            got = dut.u_fb.mem[i];
            if (got !== expected[i]) begin
                if (mism < 10)
                    $display("  mismatch at (%0d,%0d): got %h expected %h",
                             i % IMG_W, i / IMG_W, got, expected[i]);
                mism = mism + 1;
            end
        end
        $writememh("sim_edge_out.mem", dut.u_fb.mem);
        if (mism == 0) $display("Test 1 PASS: all %0d pixels match the golden model", NPIX);
        else           $display("Test 1 FAIL: %0d mismatching pixels", mism);
        errors = errors + mism;

        // ---------------- Test 2
        wait (hs_count >= 4);
        $display("HSYNC period %.2f us (exp 32.00), low %.2f us (exp 3.84)",
                 hs_period / 1000.0, hs_width / 1000.0);
        if (hs_period != 32000 || hs_width != 3840) begin
            $display("Test 2 FAIL: HSYNC timing"); errors = errors + 1;
        end else
            $display("Test 2 PASS: HSYNC timing");

        if (CAPTURE_VGA) begin
            wait (vs_count >= 2);
            $display("VSYNC period %.3f ms (exp 16.800), low %.2f us (exp 64.00)",
                     vs_period / 1.0e6, vs_width / 1000.0);
            if (vs_period != 16_800_000 || vs_width != 64_000) begin
                $display("Test 2 FAIL: VSYNC timing"); errors = errors + 1;
            end else
                $display("Test 2 PASS: VSYNC timing");

            // ---------------- Test 3
            wait (frame_done);
            @(posedge clk);
            mism = 0;
            for (y = 0; y < 480; y = y + 1)
                for (x = 0; x < 640; x = x + 1)
                    if (frame[y*640 + x] !== exp_screen(x, y)) begin
                        if (mism < 10)
                            $display("  VGA mismatch at (%0d,%0d): got %h exp %h",
                                     x, y, frame[y*640+x], exp_screen(x, y));
                        mism = mism + 1;
                    end
            fd = $fopen("vga_frame.pgm", "w");
            $fwrite(fd, "P2\n640 480\n15\n");
            for (i = 0; i < 640*480; i = i + 1)
                $fwrite(fd, "%0d%s", frame[i], ((i % 640) == 639) ? "\n" : " ");
            $fclose(fd);
            if (mism == 0) $display("Test 3 PASS: captured VGA frame matches (640x480)");
            else           $display("Test 3 FAIL: %0d VGA pixel mismatches", mism);
            errors = errors + mism;
        end

        $display("==================================");
        if (errors == 0) $display("ALL TESTS PASSED");
        else             $display("TESTS FAILED: %0d errors", errors);
        $display("outputs: sim_edge_out.mem%s", CAPTURE_VGA ? ", vga_frame.pgm" : "");
        $finish;
    end

endmodule
