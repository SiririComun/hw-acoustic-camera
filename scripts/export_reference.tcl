# Run AFTER Hog WORK returns. Arguments: project.xpr, export/, reports/.
proc export_reference {} {
    global argv
    if {[llength $argv] != 3} { error "Expected project.xpr, export/, reports/" }
    lassign $argv project_file export_dir reports_dir
    set project_file [file normalize $project_file]
    set export_dir [file normalize $export_dir]
    set reports_dir [file normalize $reports_dir]
    if {![file isfile $project_file]} { error "Generated project is missing" }
    if {![file isdirectory $export_dir] || ![file isdirectory $reports_dir]} {
        error "Build wrapper must create fresh output directories"
    }
    set archive [file join $export_dir reference.xsa]
    set receipt [file join $export_dir export-receipt.tsv]
    if {[file exists $archive] || [file exists $receipt]} { error "Export already exists" }
    open_project $project_file
    set part [get_property PART [current_project]]
    if {$part ne "xc7z020clg400-1"} { error "Unexpected FPGA part: $part" }
    set run [get_runs impl_1]
    set status [get_property STATUS $run]
    if {![regexp -nocase {write_bitstream.*complete} $status]} {
        error "Implementation has not completed write_bitstream: $status"
    }
    if {[get_property NEEDS_REFRESH $run]} { error "Implementation needs refresh" }
    set top [get_property TOP [get_filesets sources_1]]
    if {$top ne "xadc_wrapper"} { error "Unexpected reference top: $top" }
    set bit_file [file normalize [file join [get_property DIRECTORY $run] "${top}.bit"]]
    if {![file isfile $bit_file] || [file size $bit_file] == 0} {
        error "Completed run has no nonempty bitstream"
    }
    open_run impl_1
    report_timing_summary -delay_type min_max -report_unconstrained \
        -file [file join $reports_dir timing_summary.rpt]
    report_utilization -file [file join $reports_dir utilization.rpt]
    report_drc -file [file join $reports_dir drc.rpt]
    # Root BD handoff generated in this fresh checkout. Hierarchical XSAs may
    # contain only internal SmartConnect HWH files, not the overlay handoff.
    set bd_files [get_files -all -quiet */xadc.bd]
    if {[llength $bd_files] != 1} { error "Expected one root xadc.bd" }
    set hwh_file [file normalize [file join [file dirname [lindex $bd_files 0]] hw_handoff xadc.hwh]]
    if {![file isfile $hwh_file] || [file size $hwh_file] == 0} {
        error "Fresh root BD handoff is missing"
    }
    # Export implemented bitstream and PS platform metadata.
    write_hw_platform -fixed -include_bit $archive
    set out [open $receipt {WRONLY CREAT EXCL}]
    foreach {key value} [list project_file $project_file bit_file $bit_file hwh_file $hwh_file \
            part $part top $top implementation_status $status vivado_version [version -short]] {
        if {[regexp {[\t\r\n]} $value]} { close $out; error "Invalid receipt value" }
        puts $out "${key}\t${value}"
    }
    close $out
    close_project
}
if {[catch {export_reference} failure]} {
    puts stderr "Reference export failed: $failure"
    exit 1
}
exit 0
