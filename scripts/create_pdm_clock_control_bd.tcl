# Create and synthesize the phase-2 clock/control candidate only. This flow
# validates the BD/RTL and emits reports; it intentionally does not implement
# the design or generate a bitstream.

set script_dir [file dirname [file normalize [info script]]]
set repo_root [file normalize [file join $script_dir ..]]
set part xc7z020clg400-1
set run_stamp [clock format [clock seconds] -gmt 1 -format %Y%m%dT%H%M%SZ]
set run_root [file join $repo_root builds "phase-02-step-04-$run_stamp"]
set project_root [file join $run_root project]
set reference_root [file join $run_root reference]
set report_root [file join $run_root reports]
set project_name pdm_clock_control_candidate
set bd_name pdm_clock_control

set source_bd [file join $repo_root src bd xadc.bd]
set source_hdl [file join $repo_root src hdl]
set source_constraints [file join $repo_root src con pynq_z2_pdm.xdc]
set tracked_bd [file join $repo_root src bd pdm_clock_control.bd]
set tracked_wrapper [file join $source_hdl pdm_clock_control_wrapper.vhd]

if {![file isfile $source_bd] || ![file isfile $source_constraints]} {
    error "Missing XADC PS template or PDM constraints source"
}

file mkdir $run_root
file mkdir $reference_root
file mkdir $report_root
file copy -force $source_bd [file join $reference_root xadc.bd]

create_project $project_name $project_root -part $part
set_property target_language VHDL [current_project]
set_property simulator_language Mixed [current_project]
set_property enable_vhdl_2008 1 [current_project]

add_files -norecurse [list \
    [file join $source_hdl acoustic_pdm_clock.vhd] \
    [file join $source_hdl acoustic_pdm_clock_control.vhd]]
update_compile_order -fileset sources_1

# Copy only the PS cell and its accepted PYNQ-Z2 DDR/FIXED_IO configuration
# from the reference BD. The reference itself remains read-only and unchanged.
set reference_bd [file join $reference_root xadc.bd]
add_files -norecurse $reference_bd
open_bd_design $reference_bd
set reference_design [current_bd_design]
set ps_template [get_bd_cells processing_system7_0]

create_bd_design $bd_name
set copy_result [copy_bd_objs -from_design $reference_design / $ps_template]
if {$copy_result != 0} {
    error "Could not copy the PS configuration into the PDM block design"
}
set ps [get_bd_cells processing_system7_0]
if {[llength $ps] != 1} {
    error "Could not find the copied processing_system7_0 cell"
}
# This phase has no DMA; disable the unused PS HP interface.
set_property CONFIG.PCW_USE_S_AXI_HP0 0 $ps

set reset [create_bd_cell -type ip -vlnv xilinx.com:ip:proc_sys_reset:5.0 rst_ps7_0_100M]
set smartconnect [create_bd_cell -type ip -vlnv xilinx.com:ip:smartconnect:1.0 axi_smc_0]
set_property -dict [list CONFIG.NUM_SI 1 CONFIG.NUM_MI 1] $smartconnect
set control [create_bd_cell -type module -reference acoustic_pdm_clock_control acoustic_capture_0]

set lock_constant [create_bd_cell -type ip -vlnv xilinx.com:ip:xlconstant:1.1 constant_locked]
set_property -dict [list CONFIG.CONST_WIDTH 1 CONFIG.CONST_VAL 1] $lock_constant
set reset_constant [create_bd_cell -type ip -vlnv xilinx.com:ip:xlconstant:1.1 constant_reset_low]
set_property -dict [list CONFIG.CONST_WIDTH 1 CONFIG.CONST_VAL 0] $reset_constant

set ps_interfaces [get_bd_intf_pins -of_objects $ps]
set ps_ddr_pin [lsearch -glob -inline $ps_interfaces */DDR]
set ps_fixed_io_pin [lsearch -glob -inline $ps_interfaces */FIXED_IO]
if {$ps_ddr_pin eq "" || $ps_fixed_io_pin eq ""} {
    error "Copied PS cell is missing DDR or FIXED_IO interfaces: $ps_interfaces"
}
set ps_ddr [make_bd_intf_pins_external -name DDR $ps_ddr_pin]
set ps_fixed_io [make_bd_intf_pins_external -name FIXED_IO $ps_fixed_io_pin]
make_bd_pins_external -name pdm_clk_o [get_bd_pins $control/pdm_clk_o]
create_bd_port -dir I -from 3 -to 0 pdm_data_i

set control_axi [get_bd_intf_pins -quiet $control/s_axi]
if {[llength $control_axi] != 1} {
    error "Vivado did not infer the control block's AXI4-Lite slave interface"
}

connect_bd_intf_net [get_bd_intf_pins $ps/M_AXI_GP0] [get_bd_intf_pins $smartconnect/S00_AXI]
connect_bd_intf_net [get_bd_intf_pins $smartconnect/M00_AXI] $control_axi

connect_bd_net [get_bd_pins $ps/FCLK_CLK0] \
    [get_bd_pins $ps/M_AXI_GP0_ACLK] \
    [get_bd_pins $smartconnect/aclk] \
    [get_bd_pins $reset/slowest_sync_clk] \
    [get_bd_pins $control/aclk]
connect_bd_net [get_bd_pins $ps/FCLK_RESET0_N] [get_bd_pins $reset/ext_reset_in]
connect_bd_net [get_bd_pins $reset/peripheral_aresetn] [get_bd_pins $control/aresetn]
connect_bd_net [get_bd_pins $reset/interconnect_aresetn] [get_bd_pins $smartconnect/aresetn]
connect_bd_net [get_bd_pins $lock_constant/dout] [get_bd_pins $reset/dcm_locked]
connect_bd_net [get_bd_pins $reset_constant/dout] \
    [get_bd_pins $reset/aux_reset_in] \
    [get_bd_pins $reset/mb_debug_sys_rst]

set control_reg [get_bd_addr_segs -quiet $control/s_axi/reg0]
if {[llength $control_reg] != 1} {
    error "Could not identify the AXI-Lite control register segment"
}
assign_bd_address -offset 0x43C00000 -range 64K $control_reg

validate_bd_design
save_bd_design
write_bd_tcl -force [file join $run_root pdm_clock_control_replay.tcl]

set bd_file [file join $project_root "${project_name}.srcs" sources_1 bd $bd_name "${bd_name}.bd"]
if {![file isfile $bd_file]} {
    error "Vivado did not save the candidate block design at the expected path"
}
generate_target all [get_files $bd_file]

set wrapper_generated [lindex [make_wrapper -files [get_files $bd_file] -top] 0]
if {![file isfile $wrapper_generated]} {
    error "Vivado did not generate a top-level wrapper"
}
add_files -norecurse $wrapper_generated
add_files -fileset constrs_1 -norecurse $source_constraints
set_property top pdm_clock_control_wrapper [get_filesets sources_1]
update_compile_order -fileset sources_1

# Run project synthesis so Vivado resolves the BD module reference and its RTL.
# place_design, route_design, write_bitstream and board programming are omitted.
set_property top pdm_clock_control_wrapper [get_filesets sources_1]
set_property STEPS.SYNTH_DESIGN.ARGS.FLATTEN_HIERARCHY none [get_runs synth_1]
launch_runs synth_1 -jobs 4
wait_on_run synth_1
if {[get_property PROGRESS [get_runs synth_1]] ne "100%"} {
    error "Vivado synthesis run did not complete"
}
open_run synth_1

set output_clock [get_clocks -quiet -of_objects [get_ports pdm_clk_o]]
if {[llength $output_clock] != 1} {
    error "Vivado did not recognize the generated PDM output clock"
}
foreach index {0 1 2 3} {
    set data_port [get_ports -quiet "pdm_data_i\[$index\]"]
    if {[llength $data_port] != 1} {
        error "Vivado did not preserve the top-level PDM DATA input $index"
    }
}

report_clocks -file [file join $report_root clocks.rpt]
report_clock_interaction -file [file join $report_root clock_interaction.rpt]
check_timing -verbose -file [file join $report_root check_timing.rpt]
report_io -file [file join $report_root io.rpt]
report_timing_summary -delay_type min_max -file [file join $report_root timing_summary_synth.rpt]
report_drc -file [file join $report_root drc_synth.rpt]
report_utilization -hierarchical -file [file join $report_root utilization_synth.rpt]

file copy -force $bd_file $tracked_bd
file copy -force $wrapper_generated $tracked_wrapper
puts "PDM_BD_SOURCE=$tracked_bd"
puts "PDM_WRAPPER_SOURCE=$tracked_wrapper"
puts "PDM_CONTROL_BASE=0x43C00000"
puts "PDM_CLOCK_OBJECT=$output_clock"
puts "REPORT_DIRECTORY=$report_root"
puts "BITSTREAM_GENERATED=NO"
close_project
exit
