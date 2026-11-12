# PCM candidate stages. No board operations. Usage: -tclargs PROJECT.xpr synth|implement REPORTS
if {$argc != 3} {error "Expected project, stage, report directory"}
lassign $argv project_path stage reports
file mkdir $reports
open_project $project_path
set_param general.maxThreads 4
set_property STEPS.SYNTH_DESIGN.ARGS.FLATTEN_HIERARCHY none [get_runs synth_1]
# Endpoints exist only after synthesis. Apply the scoped external/CDC constraints
# at implementation, as in the accepted RAW flow; retain pin/clock metadata.
set timing_file [get_files pynq_z2_pcm_timing.xdc]
if {[llength $timing_file] != 1} {error "Missing PCM timing constraints"}
set_property USED_IN_SYNTHESIS false $timing_file
if {$stage eq "synth"} {
    generate_target all [get_files */pdm_pcm_capture.bd]
    launch_runs synth_1 -jobs 2
    wait_on_run synth_1
    if {[get_property PROGRESS [get_runs synth_1]] ne "100%"} {error "Synthesis failed"}
    open_run synth_1
    report_utilization -file $reports/utilization_synth.rpt
    report_clocks -file $reports/clocks_synth.rpt
    report_cdc -details -file $reports/cdc_synth.rpt
    check_timing -verbose -file $reports/check_timing_synth.rpt
    set f [open $reports/endpoints_synth.txt w]
    foreach pat {*sampled_pdm* *filter_ready_pipe* *snapshot_data* *block_length* *block_pattern* *block_pcm* *pdm_clk_reg*} {
        puts $f "PATTERN $pat"
        foreach cell [get_cells -hier -filter "NAME =~ $pat"] {puts $f $cell}
    }
    close $f
    write_checkpoint -force $reports/pcm_synth.dcp
} elseif {$stage eq "implement"} {
    launch_runs impl_1 -to_step write_bitstream -jobs 2
    wait_on_run impl_1
    if {[get_property PROGRESS [get_runs impl_1]] ne "100%"} {error "Implementation failed"}
    open_run impl_1
    set f [open $reports/endpoint_counts.tsv w]
    foreach {name expression expected} {
        samples {.*capture_i/sampled_pdm_reg\[[0-3]\]$} 4
        snapshot {.*capture_i/snapshot_data_reg\[[0-9]+\]$} 68
        configuration {.*capture_i/(block_length_reg\[[0-9]+\]|block_pattern_reg|block_pcm_reg)$} 34
    } {
        set count [llength [get_cells -hier -regexp $expression]]
        puts $f "$name\t$count\t$expected"
        if {$count != $expected} {error "PCM constraint endpoint mismatch: $name=$count expected=$expected"}
    }
    set cdc_count [llength [get_pins -hier -regexp {.*capture_i/(start_pipe|clear_pipe|stop_pipe|recover_pipe|recover_ack_pipe|read_busy_pipe|snapshot_req_pipe|snapshot_ack_pipe|filter_ready_pipe)_reg\[0\]/D$}]]
    puts $f "cdc_first\t$cdc_count\t9"
    if {$cdc_count != 9} {error "PCM CDC first-stage endpoint count mismatch"}
    close $f
    if {[llength [get_pins -hier -filter {NAME =~ */pdm_clk_reg_reg/C}]] != 1} {error "PCM divider endpoint mismatch"}
    report_timing_summary -delay_type min_max -report_unconstrained -file $reports/timing_summary.rpt
    report_timing -from [get_ports {pdm_data_i[*]}] -delay_type max -max_paths 4 -path_type full_clock_expanded -file $reports/data_setup.rpt
    report_timing -from [get_ports {pdm_data_i[*]}] -delay_type min -max_paths 4 -path_type full_clock_expanded -file $reports/data_hold.rpt
    report_bus_skew -file $reports/bus_skew.rpt
    report_cdc -details -file $reports/cdc_routed.rpt
    check_timing -verbose -file $reports/check_timing.rpt
    report_drc -file $reports/drc.rpt
    report_io -file $reports/io.rpt
    report_utilization -file $reports/utilization.rpt
    write_checkpoint -force $reports/pcm_routed.dcp
    set bits [glob -nocomplain [file join [get_property DIRECTORY [get_runs impl_1]] *.bit]]
    set hwhs [glob -nocomplain [file join [get_property DIRECTORY [current_project]] *.gen sources_1 bd pdm_pcm_capture hw_handoff *.hwh]]
    if {[llength $bits] != 1 || [llength $hwhs] != 1} {error "Expected one BIT and matching project HWH"}
    set f [open $reports/artifact-receipt.tsv w]
    puts $f "bit\t[lindex $bits 0]"
    puts $f "hwh\t[lindex $hwhs 0]"
    puts $f "project\t$project_path"
    puts $f "vivado_version\t[version -short]"
    puts $f "part\t[get_property PART [current_project]]"
    puts $f "top\t[get_property TOP [get_filesets sources_1]]"
    close $f
} else {error "Unknown stage"}
close_project
exit
