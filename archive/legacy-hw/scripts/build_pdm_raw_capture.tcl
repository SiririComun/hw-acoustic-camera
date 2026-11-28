# Native RAW candidate build. Usage: -tclargs PROJECT.xpr synth|implement REPORT_DIR
if {$argc != 3} {error "Expected project, stage, report directory"}
lassign $argv project_path stage reports
file mkdir $reports
open_project $project_path
set_property STEPS.SYNTH_DESIGN.ARGS.FLATTEN_HIERARCHY none [get_runs synth_1]
if {$stage eq "synth"} {
    generate_target all [get_files */pdm_raw_capture.bd]
    launch_runs synth_1 -jobs 4
    wait_on_run synth_1
    if {[get_property PROGRESS [get_runs synth_1]] ne "100%"} {error "Synthesis failed"}
    open_run synth_1
    report_clocks -file $reports/clocks_synth.rpt
    report_cdc -details -file $reports/cdc_synth.rpt
    check_timing -verbose -file $reports/check_timing_synth.rpt
    set f [open $reports/endpoints.txt w]
    foreach pat {*source_i* *start_pipe* *snapshot* *length_24* *block_length* *pdm_clk_reg*} {
        puts $f "PATTERN $pat"
        foreach cell [get_cells -hier -filter "NAME =~ $pat"] {puts $f $cell}
    }
    close $f
    write_checkpoint -force $reports/raw_synth.dcp
} elseif {$stage eq "implement"} {
    set repo [file normalize [file join [file dirname [info script]] ..]]
    add_files -fileset constrs_1 -norecurse $repo/src/con/pynq_z2_raw_timing.xdc
    set_property USED_IN_SYNTHESIS false [get_files pynq_z2_raw_timing.xdc]
    launch_runs impl_1 -to_step write_bitstream -jobs 4
    wait_on_run impl_1
    if {[get_property PROGRESS [get_runs impl_1]] ne "100%"} {error "Implementation failed"}
    open_run impl_1
    if {[llength [get_cells -hier -regexp {.*source_i/frame_data_reg\[[0-3]\]$}]] != 4 ||
        [llength [get_pins -hier -regexp {.*capture_i/(start_pipe|clear_pipe|stop_pipe|recover_pipe|recover_ack_pipe|read_busy_pipe|snapshot_req_pipe|snapshot_ack_pipe)_reg\[0\]/D$}]] != 8 ||
        [llength [get_cells -hier -regexp {.*capture_i/snapshot_data_reg\[[0-9]+\]$}]] != 36 ||
        [llength [get_cells -hier -regexp {.*capture_i/(block_length_reg\[[0-9]+\]|block_pattern_reg)$}]] != 33 ||
        [llength [get_pins -hier -filter {NAME =~ */pdm_clk_reg_reg/C}]] != 1} {error "RAW timing endpoint count mismatch"}
    report_bus_skew -file $reports/bus_skew.rpt
    report_timing_summary -delay_type min_max -report_unconstrained -file $reports/timing_summary.rpt
    report_timing -from [get_ports {pdm_data_i[*]}] -delay_type max -max_paths 4 -path_type full_clock_expanded -file $reports/data_setup.rpt
    report_timing -from [get_ports {pdm_data_i[*]}] -delay_type min -max_paths 4 -path_type full_clock_expanded -file $reports/data_hold.rpt
    report_cdc -details -file $reports/cdc_routed.rpt
    check_timing -verbose -file $reports/check_timing.rpt
    report_drc -file $reports/drc.rpt
    report_io -file $reports/io.rpt
    report_utilization -file $reports/utilization.rpt
    write_checkpoint -force $reports/raw_routed.dcp
} else {error "Unknown stage"}
close_project
exit
