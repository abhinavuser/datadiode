# build_project.tcl
# vivado tcl build script for arty a7-100t data diode

set project_name "data_diode"
set project_dir  [file normalize [pwd]]
set src_dir      [file normalize "../hdl/src"]
set xdc_dir      [file normalize "../hdl/constraints"]
set part         "xc7a100tcsg324-1"

create_project $project_name $project_dir/$project_name -part $part -force

add_files -fileset sources_1 [glob $src_dir/*.vhd]
set_property top arty_top [current_fileset]
add_files -fileset constrs_1 $xdc_dir/arty_datadiode.xdc
set_property file_type {VHDL 2008} [get_files *.vhd]

puts "running synthesis..."
launch_runs synth_1 -jobs 4
wait_on_run synth_1

if {[get_property STATUS [get_runs synth_1]] != "synth_design Complete!"} {
    puts "error: synthesis failed"
    return
}

puts "running implementation..."
launch_runs impl_1 -jobs 4
wait_on_run impl_1

if {[get_property STATUS [get_runs impl_1]] != "route_design Complete!"} {
    puts "error: implementation failed"
    return
}

puts "generating bitstream..."
launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1

open_run impl_1
report_utilization -file $project_dir/utilization_report.txt
report_timing_summary -file $project_dir/timing_report.txt

puts "build complete!"
puts "bitstream: $project_dir/$project_name/$project_name.runs/impl_1/arty_top.bit"
