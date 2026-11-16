# Sobel Edge Detection on the Nexys A7-100T

Real-time 3×3 Sobel edge detection in Verilog on the Digilent **Nexys A7-100T**
(Artix-7 XC7A100T). A photo is converted on the PC into an 8-bit grayscale
`.mem` file and built into Block RAM with the bitstream. After reset, a
streaming Sobel engine writes the edge image into a frame buffer in a few
milliseconds, and the VGA output shows it at **640×480 @ 60 Hz**. The board
switches select the original image, the edges, or both side by side, and add
a threshold and an invert option.

---

## Contents

- [Results on the board](#results-on-the-board)
- [Block diagram](#block-diagram)
- [Files](#files)
- [Board controls](#board-controls)
- [Image size and screen layout](#image-size-and-screen-layout)
- [How the design works](#how-the-design-works)
- [1 · Convert your image](#1--convert-your-image)
- [2 · Simulate](#2--simulate)
- [3 · Vivado implementation](#3--vivado-implementation)
- [Troubleshooting](#troubleshooting)

---

## Results on the board

These photos were taken with the **320×240 landscape** setting.

### Input image

<p align="center">
  <img src="images/input.jpg" width="600" alt="Input: aerial photo of a football pitch">
</p>

The colour photo is resized to 320×240 and converted to 8-bit gray by
`img2mem.py` before it goes into the FPGA.

### Output for different switch settings

| # | SW0 | SW1 | SW2 (threshold) | SW3 (invert) | What is shown |
|:-:|:---:|:---:|:---:|:---:|---|
| 1 | 1 | 0 | – | – | Original image, full screen, scaled 2× |
| 2 | – | 1 | 1 | 0 | Side by side: original \| thresholded edges, white on black |
| 3 | – | 1 | 0 | 1 | Side by side: original \| raw edges, inverted |
| 4 | – | 1 | 1 | 1 | Side by side: original \| thresholded edges, inverted |

`–` means the switch has no effect in that mode. The threshold level is set
with `SW15..SW8`.

<table>
  <tr>
    <td align="center"><img src="images/1_fullscreen_original.jpg" width="420"><br><b>1.</b> Original, full screen (SW0 = 1, SW1 = 0)</td>
    <td align="center"><img src="images/2_sbs_edges_threshold.jpg" width="420"><br><b>2.</b> Side by side, threshold on (SW1 = 1, SW2 = 1)</td>
  </tr>
  <tr>
    <td align="center"><img src="images/3_sbs_inverted_raw.jpg" width="420"><br><b>3.</b> Side by side, inverted, no threshold (SW1 = 1, SW3 = 1)</td>
    <td align="center"><img src="images/4_sbs_inverted_threshold.jpg" width="420"><br><b>4.</b> Side by side, threshold + invert (SW1 = 1, SW2 = 1, SW3 = 1)</td>
  </tr>
</table>

**What the photos show**

- **Photo 3 (no threshold):** the grass texture gives many weak gradients, so
  the whole pitch looks grainy. The pitch lines, centre circle and penalty
  boxes are still clearly the strongest edges.
- **Photos 2 and 4 (threshold on):** the weak texture edges are removed and
  only the pitch markings, benches and goals remain. Photo 4 is the same
  result with the colours inverted (black edges on white).
- **Photo 1:** the visible banding in the grass comes from the VGA port's
  16 gray levels (4 bits per colour). Edge detection itself uses all 8 bits.
- Each line in the input shows up as a **double line** in the edge image.
  This is expected: Sobel responds to both sides of a thin bright line
  (dark → bright and bright → dark).

---

## Block diagram

```
 PC (Python)                              FPGA  xc7a100tcsg324-1, single 100 MHz clock
 ───────────                              ─────────────────────────────────────────────────────────
 photo.jpg                                 ┌──────────────┐ port A  ┌────────────────────────────┐
   │ img2mem.py                            │  image_rom   │────────▶│        sobel_engine        │
   │  resize W×H, gray (BT.601)            │  W×H×8 BRAM  │ raster  │ 2 line buffers + 3×3 window│
   ├─▶ image.mem ── $readmemh ────────────▶│              │ read    │ |Gx|+|Gy|, saturate 255    │
   └─▶ expected_edge.mem (golden)          └──────┬───────┘         └─────────────┬──────────────┘
           │                                      │ port B (original)             │ write
           │ testbench compares                   │                ┌──────────────▼──────────────┐
           ▼                                      │                │ frame_buffer  W×H×8 BRAM    │
       PASS / FAIL                                │                └──────────────┬──────────────┘
                                                  │                               │ read (edges)
                                             ┌────▼───────────────────────────────▼────┐
  vga_timing (640×480, /4 pixel enable) ────▶│ display mux: full screen / side by side │──▶ VGA_R/G/B[3:0]
                                             │ threshold, invert   (5-clock pipeline)  │──▶ VGA_HS, VGA_VS
                                             └─────────────────────────────────────────┘
```

---

## Files

```
rtl/sobel_cfg.vh            image size (IMG_W, IMG_H). The only place to change it
rtl/sobel_top.v             top level: reset/button/switch sync, memories, engine, VGA mux
rtl/sobel_engine.v          streaming Sobel, FSM CLEAR -> RUN -> FLUSH -> DONE
rtl/image_rom.v             dual-port ROM, $readmemh(INIT_FILE), 1-cycle read
rtl/frame_buffer.v          simple dual-port RAM for the edge image, 1-cycle read
rtl/vga_timing.v            640x480@60 sync generator, 25 MHz pixel enable (100 MHz / 4)
constraints/nexys_a7_100t.xdc
sim/tb_sobel_top.v          self-checking testbench (engine, sync timing, full VGA frame)
sim/run_iverilog.sh         command-line simulation with Icarus Verilog
scripts/img2mem.py          image -> image.mem + expected_edge.mem (+ previews)
scripts/mem2img.py          .mem / .pgm -> PNG, optional diff against the golden file
scripts/create_project.tcl  builds the Vivado project (optionally the bitstream)
scripts/program_board.tcl   JTAG programming
mem/image.mem, mem/expected_edge.mem   image data (replace with your own)
images/                     photos used in this README
```

---

## Board controls

| Control | Function |
|---|---|
| `CPU_RESET` | Reset and re-run edge detection |
| `BTNC` | Re-run edge detection (when LED0 is lit) |
| `SW0` | 0 = edges, 1 = original (full-screen mode only) |
| `SW1` | 0 = full screen · 1 = side by side, 1:1 (original left, edges right) |
| `SW2` | Binary threshold on the edges, level = `SW15..SW8` (try `0100 0000` = 64) |
| `SW3` | Invert the edges (black edges on white) |
| `LED0` / `LED1` | Done / busy |
| `LED15..LED8` | Mirror the threshold switches |

All switches are registered once at 100 MHz before use. `BTNC` goes through a
two-flop synchroniser and an edge detector, so one press gives one start
pulse.

---

## Image size and screen layout

The image size is set in **one file**, `rtl/sobel_cfg.vh`. The RTL and the
testbench both read it. Pick one pair and generate the `.mem` files with the
same size:

| Image type | `sobel_cfg.vh` | `img2mem.py` arguments | Full screen | Side by side |
|---|---|---|---|---|
| Landscape | `IMG_W 320`, `IMG_H 240` | `--width 320 --height 240` | 2× scaled, fills 640×480 | 1:1, at y = 120 |
| Portrait (phone photos, 9:16) | `IMG_W 270`, `IMG_H 480` | `--width 270 --height 480 --fit crop` | 1:1, centred, x = 185 | 1:1, at x = 50 |

### Layout formulas

The layout is computed from the size in `sobel_top.v` (the testbench repeats the
same formulas). $`W`$ and $`H`$ are the image width and height.

**Scale factor** (2× only if the doubled image still fits on the screen):

```math
\text{SCALE} =
\begin{cases}
2, & \text{if } 2W \le 640 \text{ and } 2H \le 480 \\
1, & \text{otherwise}
\end{cases}
```

**Top-left corner in full-screen mode** (image centred):

```math
X_0^{\,\text{FS}} = \frac{640 - \text{SCALE}\cdot W}{2}
\qquad\qquad
Y_0^{\,\text{FS}} = \frac{480 - \text{SCALE}\cdot H}{2}
```

**Top-left corner in side-by-side mode** (two images next to each other, 1:1):

```math
X_0^{\,\text{SS}} = \frac{640 - 2W}{2}
\qquad\qquad
Y_0^{\,\text{SS}} = \frac{480 - H}{2}
```

**Worked examples:**

| Size | SCALE | $`X_0^{\,\text{FS}}`$ | $`Y_0^{\,\text{FS}}`$ | $`X_0^{\,\text{SS}}`$ | $`Y_0^{\,\text{SS}}`$ |
|---|:-:|:-:|:-:|:-:|:-:|
| 320×240 | 2 | $`(640-640)/2 = 0`$ | $`(480-480)/2 = 0`$ | $`(640-640)/2 = 0`$ | $`(480-240)/2 = 120`$ |
| 270×480 | 1 ($`2\cdot480 = 960 > 480`$) | $`(640-270)/2 = 185`$ | $`0`$ | $`(640-540)/2 = 50`$ | $`0`$ |

### Memory limits

$`W \le 320`$ and $`H \le 480`$ so that side-by-side mode fits on the screen.
The two buffers must also fit in the 135 RAMB36 blocks of the XC7A100T. One
RAMB36 holds 4096 bytes at 8-bit width:

```math
\text{RAMB36 per buffer} = \left\lceil \frac{W \cdot H}{4096} \right\rceil
```

| Size | Pixels | RAMB36 per buffer | Total (ROM + frame buffer) |
|---|---|---|---|
| 320×240 | 76 800 | $`\lceil 18.75 \rceil = 19`$ | 38 of 135 |
| 270×480 | 129 600 | $`\lceil 31.64 \rceil = 32`$ | 64 of 135 |

Both buffers together must fit:

```math
2\left\lceil \frac{W H}{4096} \right\rceil \le 135
\quad\Longrightarrow\quad
W H \lesssim 67 \cdot 4096 \approx 274\,000 \text{ pixels}
```

The comment in `sobel_cfg.vh` uses about 260 000 as a safe limit. A full
640×480 image would need $`2 \cdot 75 = 150`$ blocks and does not fit.

---

## How the design works

### Clocking and reset

Everything runs on the 100 MHz board clock. The VGA timing uses a
divide-by-4 clock enable (25.000 MHz, close enough to the nominal 25.175 MHz
for monitors). There is one clock domain, no Clocking Wizard IP and no clock
domain crossing. `rst_sync` powers up as `2'b11`, so the engine runs once
automatically after configuration.

### Sobel engine (`sobel_engine.v`)

**The 3×3 window.** For every pixel, the engine looks at its 8 neighbours.
The pixels in the window are named by row and column:

```
        col 0   col 1   col 2
row 0    p00     p01     p02
row 1    p10     p11     p12      p11 = centre pixel
row 2    p20     p21     p22
```

**The two Sobel kernels.** $`K_x`$ finds vertical edges (change from left to
right), and $`K_y`$ finds horizontal edges (change from top to bottom):

```math
K_x =
\begin{bmatrix}
-1 & 0 & +1 \\
-2 & 0 & +2 \\
-1 & 0 & +1
\end{bmatrix}
\qquad\qquad
K_y =
\begin{bmatrix}
-1 & -2 & -1 \\
\phantom{-}0 & \phantom{-}0 & \phantom{-}0 \\
+1 & +2 & +1
\end{bmatrix}
```

**Applying the kernels.** Multiplying each kernel with the window and adding
up the terms gives:

```math
G_x = \big(p_{02} + 2p_{12} + p_{22}\big) - \big(p_{00} + 2p_{10} + p_{20}\big)
```

```math
G_y = \big(p_{20} + 2p_{21} + p_{22}\big) - \big(p_{00} + 2p_{01} + p_{02}\big)
```

**Edge strength.** The exact magnitude $`\sqrt{G_x^2 + G_y^2}`$ needs
multipliers and a square root, so the hardware uses the usual approximation
and limits the result to 8 bits:

```math
|G| \approx \min\big(|G_x| + |G_y|,\ 255\big)
```

No multipliers are needed: the ×2 terms are a 1-bit left shift.

**Bit widths.** In the worst case each kernel gives $`4 \cdot 255 = 1020`$, so

```math
|G_x| + |G_y| \le 4\cdot255 + 4\cdot255 = 2040
```

$`G_x`$ and $`G_y`$ fit in signed 11 bits, and the sum fits in 12 bits before
saturation to 255.

**FSM:**

| State | Work | Cycles |
|---|---|---|
| `S_CLEAR` | Write 0 to every frame-buffer address (gives zero borders) | $`W H`$ |
| `S_RUN` | Stream the image from the ROM, one pixel per clock | $`W H`$ |
| `S_FLUSH` | Let the pipeline drain | 8 |
| `S_DONE` | `done` = 1, wait for `start` | – |

**Pipeline** (one pixel per clock, no stalls):

| Stage | Work |
|---|---|
| S0 | Raster counters `x0, y0` drive the ROM address and line-buffer read address |
| S1 | ROM pixel (row y), `lb0` (row y−1) and `lb1` (row y−2) arrive together as one column |
| S2 | Column shifts into the window `p00..p22`; `lb1 ← lb0`, `lb0 ← pixel` |
| S3 | Compute $`G_x`$ and $`G_y`$ (formulas above); valid when x ≥ 2 and y ≥ 2 |
| S4 | $`\min(\lvert G_x\rvert + \lvert G_y\rvert,\ 255)`$ |
| S5 | Registered write to the frame buffer |

**Write address.** The newest pixel is at $`(x, y)`$, so the window centre is
one row up and one column left, at $`(x-1,\ y-1)`$:

```math
a_{\text{centre}} = (y-1)\,W + (x-1) = (yW + x) - W - 1
```

The line buffers are `distributed` RAM (W bytes each). The first and last rows
and columns are never written during `S_RUN`, so they stay 0 from the clear.

**Run time** at 100 MHz (10 ns per cycle). `S_CLEAR` and `S_RUN` each take
$`W H`$ cycles:

```math
t \approx 2\,W H \cdot 10\ \text{ns}
```

| Size | Calculation | Time |
|---|---|---|
| 320×240 | $`2 \cdot 76\,800 \cdot 10\ \text{ns}`$ | ≈ 1.54 ms |
| 270×480 | $`2 \cdot 129\,600 \cdot 10\ \text{ns}`$ | ≈ 2.59 ms |

### Display path (`sobel_top.v`)

The screen coordinate is mapped to an image coordinate and a source (original
or edges), then registered through five stages:

| Stage | Work |
|---|---|
| A (comb) | Screen (h, v) → image (x, y), in-image flag, edge/original select |
| 1 | Register (x, y) |
| 2 | Read address $`yW + x`$ |
| 3 | BRAM output (`image_rom` port B and `frame_buffer` both read) |
| 4 | Threshold / invert / mux → `pix_r` (top 4 bits) |
| 5 | Output registers (packed into the IOBs) |

HSYNC, VSYNC, the in-image flag and the select are delayed with 4-bit shift
registers so they line up with the data. Outside the image the address is held
at 0 and the output is black. An earlier 3-stage version missed timing at
100 MHz by 1 ps, which is why the BRAM → threshold → IOB route is split.

The VGA port is 4 bits per colour, so the screen shows 16 gray levels
(`pix[7:4]`). The threshold compares the full 8-bit edge value.

---

## 1 · Convert your image

```bash
pip install pillow numpy
cd scripts

# portrait
python img2mem.py ~/Downloads/photo.jpg --width 270 --height 480 --fit crop \
    -o ../mem/image.mem --golden ../mem/expected_edge.mem \
    --preview --preview-dir ../mem

# landscape
python img2mem.py ~/Downloads/photo.jpg --width 320 --height 240 \
    -o ../mem/image.mem --golden ../mem/expected_edge.mem \
    --preview --preview-dir ../mem

# built-in synthetic image, no photo needed
python img2mem.py --test-pattern --width 270 --height 480 -o ../mem/image.mem --golden ../mem/expected_edge.mem
```

| Option | Meaning |
|---|---|
| `--width`, `--height` | Must match `sobel_cfg.vh`. Default is 320×240; any other size prints a reminder |
| `--fit pad` (default) | Letterbox with black bars, keeps the whole picture |
| `--fit crop` | Fill the frame and crop the overflow (best for phone photos) |
| `--fit stretch` | Resize ignoring aspect ratio |
| `--preview` | Also write `preview_gray.png` (what the FPGA sees) and `preview_edge.png` (what it should show) |

The script honours the EXIF rotation of phone photos and converts to gray with
integer BT.601 weights:

```math
Y = \left\lfloor \frac{77R + 150G + 29B + 128}{256} \right\rfloor
```

It computes `expected_edge.mem` with the same arithmetic as the RTL, so the
golden file must match bit for bit.

> **Windows:** `photo.jpg` is only a placeholder. Give the real path (drag the
> file into the Command Prompt window to paste it). Turn on
> *View → Show → File name extensions* to see the real file type.

---

## 2 · Simulate

**Icarus Verilog** (quick check, no Vivado needed):

```bash
cd sim && ./run_iverilog.sh          # includes a full VGA frame capture
./run_iverilog.sh quick              # engine + HSYNC only
```

When compiling by hand with Icarus, pass `-P 'tb_sobel_top.MEM_DIR="./"'`.
Icarus does not handle the empty default string and the `.mem` files will not
load.

**What the testbench checks** (`tb_sobel_top.v`):

| Test | Check |
|---|---|
| 1 · Engine | Waits for LED0 (timeout 5 ms), compares every frame-buffer pixel with `expected_edge.mem`, writes `sim_edge_out.mem` |
| 2 · Timing | HSYNC period 32.00 µs, low 3.84 µs; VSYNC period 16.800 ms, low 64.00 µs |
| 3 · Picture | (`CAPTURE_VGA=1`) Rebuilds one 640×480 frame from the VGA pins only, compares it with the expected layout, checks R = G = B, writes `vga_frame.pgm` |

Expected output:

```
Test 1 PASS: all <W*H> pixels match the golden model
Test 2 PASS: HSYNC timing
Test 2 PASS: VSYNC timing
Test 3 PASS: captured VGA frame matches (640x480)
ALL TESTS PASSED
```

Testbench parameters:

| Parameter | Effect |
|---|---|
| `SIDE_BY_SIDE=1` | Check the split-screen layout instead of full screen |
| `CAPTURE_VGA=0` | Skip the VSYNC and picture checks for a much shorter run |
| `MEM_DIR` | Where the `.mem` files are read from |

**View the results.** `mem2img.py` defaults to 320×240, so give the size for
other images:

```bash
python mem2img.py sim_edge_out.mem --width 270 --height 480 -o sim_edge.png
python mem2img.py sim_edge_out.mem --width 270 --height 480 --compare expected_edge.mem
python mem2img.py vga_frame.pgm -o vga_frame.png      # size is read from the file
```

`--compare` prints the number of mismatching pixels and exits with code 1 if
there are any.

**Vivado xsim:** Flow Navigator → *Run Simulation → Run Behavioral Simulation*.
Set `xsim.simulate.runtime` to `all` (the project script does this). The full
run simulates about 35 ms of design time and takes a few minutes. Set the
`CAPTURE_VGA` generic to 0 in *Simulation Settings → Generics* for a run of a
few seconds. The output files are written to
`vivado/sobel_nexys_a7.sim/sim_1/behav/xsim/`.

---

## 3 · Vivado implementation

**Scripted:**

```bash
vivado -mode batch -source scripts/create_project.tcl -tclargs build
vivado -mode batch -source scripts/program_board.tcl
```

**GUI, step by step:**

1. *Create Project* → RTL Project → part **xc7a100tcsg324-1** (or board
   *Nexys A7-100T* if the Digilent board files are installed).
2. *Add Sources → design sources*: everything in `rtl/` (including
   `sobel_cfg.vh`) plus `mem/image.mem`. Untick *Copy sources into project* so
   a regenerated `image.mem` is picked up. Vivado normally classifies `.mem`
   as *Memory Initialization Files*; if not, set **File Type** in Source File
   Properties. Set the file dialog filter to *All Files* if `.mem` files are
   hidden.
3. *Add Sources → constraints*: `constraints/nexys_a7_100t.xdc`.
4. *Add Sources → simulation*: `sim/tb_sobel_top.v` and
   `mem/expected_edge.mem`. Set `tb_sobel_top` as the simulation top.
5. Set `sobel_top` as the design top. Run the simulation first and look for
   `ALL TESTS PASSED` in the Tcl console.
6. **Run Synthesis.** In the log, confirm that `image_rom` and `frame_buffer`
   were inferred as Block RAM (RAM/ROM report) and that `image.mem` was read.
   LUT and FF use is small (under 2 %).
7. **Run Implementation** and open *Report Timing Summary*: WNS ≥ 0 at
   100 MHz.
8. **Generate Bitstream** → *Open Hardware Manager* → *Open Target → Auto
   Connect* → *Program Device*.
9. Connect a VGA monitor. LED0 lights a few ms after configuration and the
   edge image appears.

**Board setup:** JP3 (top left, next to the power jack) on **USB**. JP1
(programming mode) does not matter for JTAG. JTAG programming is lost at power
off; write the configuration flash to keep it.

### Changing the image

Re-run `img2mem.py`, then generate the bitstream again. The image is part of
the bitstream, so synthesis and implementation have to run again. Swapping
BRAM contents with `updatemem` and an `.mmi` file is faster but not worth the
setup for an occasional new image.

### Changing the size

1. Edit `IMG_W` / `IMG_H` in `rtl/sobel_cfg.vh`.
2. Regenerate both `.mem` files with the same `--width` / `--height`.
3. Re-run the simulation, then rebuild.

The address width, line-buffer size, display scaling and screen offsets all
follow from the two defines. Both sizes pass in simulation in both
full-screen and side-by-side layouts.

---

## Troubleshooting

| Symptom | Cause / fix |
|---|---|
| Monitor says "no signal" | Check the VGA cable, the XDC pins, and that the bitstream was programmed (DONE LED on the board) |
| Black screen, LED0 off | Engine held in reset: check that `CPU_RESETN` is on C12 (active low) |
| Image squashed, shifted or garbled | `sobel_cfg.vh` size does not match the `--width/--height` used for `image.mem` |
| Test 1 fails on every pixel | Same cause, or `expected_edge.mem` is from a different image than `image.mem` |
| Image all black or all white in sim | `$readmemh` did not find the file; add the `.mem` as a Memory Initialization File or set `MEM_DIR` |
| `mem2img.py` picture looks sheared | Missing `--width/--height` (it defaults to 320×240) |
| Edges look noisy | Turn on SW2 and raise the threshold (SW15..SW8) |
| Synthesis says the ROM uses LUTs | Check the `rom_style = "block"` attribute and that the ROM outputs are registered |
| Original image looks banded | Expected: the VGA port has 16 gray levels. Edge detection still uses 8 bits |
| Curved stripes in a phone photo of the screen | Camera moiré against the monitor pixel grid; the screen itself is fine |
