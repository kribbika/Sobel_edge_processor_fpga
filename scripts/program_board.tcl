# =============================================================================
# program_board.tcl -- download the bitstream over USB-JTAG
#   vivado -mode batch -source scripts/program_board.tcl
# =============================================================================
set root [file normalize [file join [file dirname [info script]] ..]]
set bit  [file join $root vivado sobel_nexys_a7.runs impl_1 sobel_top.bit]

open_hw_manager
connect_hw_server
open_hw_target
set dev [lindex [get_hw_devices xc7a100t_0] 0]
current_hw_device $dev
set_property PROGRAM.FILE $bit $dev
program_hw_devices $dev
puts "Programmed $bit"
close_hw_manager
