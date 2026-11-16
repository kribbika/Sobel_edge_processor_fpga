# =============================================================================
# create_project.tcl -- builds the Vivado project for the Nexys A7-100T
#
#   Vivado GUI : Tools -> Run Tcl Script... -> scripts/create_project.tcl
#   Batch      : vivado -mode batch -source scripts/create_project.tcl
#   Add "-tclargs build" to also run synthesis, implementation and bitstream.
# =============================================================================
set root [file normalize [file join [file dirname [info script]] ..]]
set part xc7a100tcsg324-1

create_project sobel_nexys_a7 [file join $root vivado] -part $part -force

# ---- design sources
add_files -norecurse [glob [file join $root rtl *.v]]
add_files -norecurse [file join $root mem image.mem]
set_property file_type {Memory Initialization Files} [get_files image.mem]
set_property top sobel_top [get_filesets sources_1]

# ---- constraints
add_files -fileset constrs_1 -norecurse [file join $root constraints nexys_a7_100t.xdc]

# ---- simulation
add_files -fileset sim_1 -norecurse [file join $root sim tb_sobel_top.v]
add_files -fileset sim_1 -norecurse [file join $root mem expected_edge.mem]
set_property file_type {Memory Initialization Files} [get_files expected_edge.mem]
set_property top tb_sobel_top [get_filesets sim_1]
set_property -name {xsim.simulate.runtime} -value {all} -objects [get_filesets sim_1]

update_compile_order -fileset sources_1
update_compile_order -fileset sim_1
puts "Project created in [file join $root vivado]"

# ---- optional full build
if {[llength $argv] > 0 && [lindex $argv 0] eq "build"} {
    launch_runs synth_1 -jobs 4
    wait_on_run synth_1
    launch_runs impl_1 -to_step write_bitstream -jobs 4
    wait_on_run impl_1
    open_run impl_1
    report_utilization    -file [file join $root vivado utilization.rpt]
    report_timing_summary -file [file join $root vivado timing.rpt]
    puts "Bitstream: [get_property DIRECTORY [get_runs impl_1]]/sobel_top.bit"
}
