# Implement the already generated phase-2 PDM project and export its matching
# BIT/HWH pair. This script does not program a board.

if {$argc != 2} {
    error "Usage: implement_pdm_clock_control.tcl <project.xpr> <artifact-dir>"
}

set project_file [file normalize [lindex $argv 0]]
set artifact_dir [file normalize [lindex $argv 1]]
if {![file isfile $project_file]} {
    error "Project file does not exist: $project_file"
}

set project_dir [file dirname $project_file]
set project_name [file rootname [file tail $project_file]]
set top_name pdm_clock_control_wrapper
set bd_name pdm_clock_control
set reports_dir [file join $artifact_dir reports]
file mkdir $reports_dir

open_project $project_file
if {[current_project] eq ""} {
    error "Vivado did not open the PDM clock-control project"
}
if {[get_property PART [current_project]] ne "xc7z020clg400-1"} {
    error "Unexpected target part: [get_property PART [current_project]]"
}
if {[get_property TOP [get_filesets sources_1]] ne $top_name} {
    error "Unexpected top-level module: [get_property TOP [get_filesets sources_1]]"
}

set implementation [get_runs impl_1]
launch_runs $implementation -to_step write_bitstream -jobs 4
wait_on_run $implementation
if {[get_property PROGRESS $implementation] ne "100%"} {
    error "Implementation did not complete: [get_property STATUS $implementation]"
}

open_run $implementation
report_clocks -file [file join $reports_dir clocks_implementation.rpt]
report_clock_interaction -file [file join $reports_dir clock_interaction_implementation.rpt]
check_timing -verbose -file [file join $reports_dir check_timing_implementation.rpt]
report_io -file [file join $reports_dir io_implementation.rpt]
report_timing_summary -delay_type min_max -file [file join $reports_dir timing_summary_implementation.rpt]
report_drc -file [file join $reports_dir drc_implementation.rpt]
report_utilization -hierarchical -file [file join $reports_dir utilization_implementation.rpt]

set bit_file [file join [get_property DIRECTORY $implementation] "${top_name}.bit"]
set hwh_file [file join $project_dir "${project_name}.gen" sources_1 bd $bd_name hw_handoff "${bd_name}.hwh"]
if {![file isfile $bit_file] || [file size $bit_file] == 0} {
    error "Completed implementation has no nonempty BIT: $bit_file"
}
if {![file isfile $hwh_file] || [file size $hwh_file] == 0} {
    error "Generated root BD HWH is missing: $hwh_file"
}

file copy -force $bit_file [file join $artifact_dir pdm_clock_control.bit]
file copy -force $hwh_file [file join $artifact_dir pdm_clock_control.hwh]
puts "IMPLEMENTATION_STATUS=[get_property STATUS $implementation]"
puts "BIT_FILE=[file join $artifact_dir pdm_clock_control.bit]"
puts "HWH_FILE=[file join $artifact_dir pdm_clock_control.hwh]"
puts "REPORTS_DIR=$reports_dir"
puts "BOARD_PROGRAMMED=NO"
close_project
exit
