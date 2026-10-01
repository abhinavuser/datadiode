##############################################################################
## Vivado TCL Build Script — FPGA Data Diode for Arty A7-100T
##############################################################################
## Usage: Open Vivado, then in the Tcl Console:
##   cd E:/datadiode/vivado
##   source ../hdl/build_project.tcl
##############################################################################

# Project settings
set project_name "data_diode"
set project_dir  [file normalize [pwd]]
set src_dir      [file normalize "../hdl/src"]
set xdc_dir      [file normalize "../hdl/constraints"]
set part         "xc7a100tcsg324-1"

# Create project
create_project $project_name $project_dir/$project_name -part $part -force

# Add VHDL source files
add_files -fileset sources_1 [glob $src_dir/*.vhd]

# Set top module
set_property top arty_top [current_fileset]

# Add constraints
add_files -fileset constrs_1 $xdc_dir/arty_datadiode.xdc

# Set VHDL version to 2008
set_property file_type {VHDL 2008} [get_files *.vhd]

# Run synthesis
puts "================================================================"
puts "  Running Synthesis..."
puts "================================================================"
launch_runs synth_1 -jobs 4
wait_on_run synth_1

# Check synthesis status
if {[get_property STATUS [get_runs synth_1]] != "synth_design Complete!"} {
    puts "ERROR: Synthesis failed!"
    return
}
puts "Synthesis completed successfully!"

# Run implementation
puts "================================================================"
puts "  Running Implementation..."
puts "================================================================"
launch_runs impl_1 -jobs 4
wait_on_run impl_1

# Check implementation status
if {[get_property STATUS [get_runs impl_1]] != "route_design Complete!"} {
    puts "ERROR: Implementation failed!"
    return
}
puts "Implementation completed successfully!"

# Generate bitstream
puts "================================================================"
puts "  Generating Bitstream..."
puts "================================================================"
launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1

puts "================================================================"
puts "  Build Complete!"
puts "  Bitstream: $project_dir/$project_name/$project_name.runs/impl_1/arty_top.bit"
puts "================================================================"

# Open implementation to view reports
open_run impl_1

# Print utilization summary
report_utilization -file $project_dir/utilization_report.txt
report_timing_summary -file $project_dir/timing_report.txt

puts ""
puts "  Reports saved:"
puts "    - utilization_report.txt"
puts "    - timing_report.txt"
puts ""
puts "  To program the Arty A7:"
puts "    open_hw_manager"
puts "    connect_hw_server"
puts "    open_hw_target"
puts "    set_property PROGRAM.FILE {arty_top.bit} [current_hw_device]"
puts "    program_hw_devices"
