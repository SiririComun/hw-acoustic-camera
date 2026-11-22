if {[llength $argv] != 1} {error "Expected one generated Base project path"}
set project_path [file normalize [lindex $argv 0]]
if {![file isfile $project_path]} {
    error "Expected a generated Base project path"
}
open_project $project_path
open_run impl_1
set project_dir [get_property DIRECTORY [current_project]]
set reports_dir [file join $project_dir phase11_reports]
file mkdir $reports_dir
set f [open [file join $reports_dir pcm_endpoint_counts.tsv] w]
foreach {name expression expected} {
    samples {.*capture_i/sampled_pdm_reg\[[0-3]\]$} 4
    snapshot {.*capture_i/snapshot_data_reg\[[0-9]+\]$} 132
    configuration {.*capture_i/(block_length_reg\[[0-9]+\]|block_pattern_reg|block_pcm_reg|continuous_mode_reg)$} 35
} {
    set count [llength [get_cells -hier -regexp $expression]]
    puts $f "$name\t$count\t$expected"
    if {$count != $expected} {error "PCM endpoint mismatch: $name=$count expected=$expected"}
}
set cdc_first [llength [get_pins -hier -regexp {.*capture_i/(start_pipe|clear_pipe|stop_pipe|stop_cmd_pipe|recover_pipe|recover_ack_pipe|read_busy_pipe|snapshot_req_pipe|snapshot_ack_pipe|filter_ready_pipe)_reg\[0\]/D$}]]
puts $f "cdc_first\t$cdc_first\t10"
close $f
if {$cdc_first != 10} {error "PCM CDC first-stage endpoint count mismatch: $cdc_first"}
set pcm_100m_clock_pin [get_pins -hier -regexp {.*capture_i/frames_total_visible_reg\[0\]/C}]
set pcm_24m_clock_pin [get_pins -hier -regexp {.*capture_i/sampled_pdm_reg\[0\]/C}]
set pcm_100m_clock [get_clocks -of_objects $pcm_100m_clock_pin]
set pcm_24m_clock [get_clocks -of_objects $pcm_24m_clock_pin]
if {[llength $pcm_100m_clock_pin] != 1 || [llength $pcm_100m_clock] != 1 ||
    [llength $pcm_24m_clock_pin] != 1 || [llength $pcm_24m_clock] != 1 ||
    [llength [get_pins -hier -filter {NAME =~ */pdm_clk_reg_reg/C}]] != 1} {
    error "PCM timing clock pin endpoint mismatch"
}
set f [open [file join $reports_dir pcm_clocks.tsv] w]
puts $f "snapshot_100MHz\t[ get_property NAME $pcm_100m_clock ]\t[ get_property PERIOD $pcm_100m_clock ]"
puts $f "sampler_24MHz\t[ get_property NAME $pcm_24m_clock ]\t[ get_property PERIOD $pcm_24m_clock ]"
close $f
report_timing_summary -delay_type min_max -report_unconstrained \
    -file [file join $reports_dir timing_summary.rpt]
report_clocks -file [file join $reports_dir clocks.rpt]
check_timing -verbose -file [file join $reports_dir check_timing.rpt]
report_cdc -details -file [file join $reports_dir cdc.rpt]
report_drc -file [file join $reports_dir drc.rpt]
report_io -file [file join $reports_dir io.rpt]
report_utilization -hierarchical -file [file join $reports_dir utilization.rpt]
close_project
exit
