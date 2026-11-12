# Phase 3.4: prepare and validate RAW BD only; no build or board operations.
set script_dir [file dirname [file normalize [info script]]]
set repo_root [file normalize [file join $script_dir ..]]
set part xc7z020clg400-1
set run_stamp [clock format [clock seconds] -gmt 1 -format %Y%m%dT%H%M%SZ]
set run_root [file join $repo_root builds "phase-03-step-04-$run_stamp"]
set project_root [file join $run_root project]
set reference_root [file join $run_root reference]
set report_root [file join $run_root reports]
set project_name pdm_raw_capture_candidate
set bd_name pdm_raw_capture

set source_bd [file join $repo_root src bd xadc.bd]
set source_hdl [file join $repo_root src hdl]
set source_constraints [file join $repo_root src con pynq_z2_pdm.xdc]
set tracked_bd [file join $repo_root src bd pdm_raw_capture.bd]
set tracked_wrapper [file join $source_hdl pdm_raw_capture_wrapper.vhd]

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
    [file join $source_hdl acoustic_pdm_raw_source.vhd] \
    [file join $source_hdl acoustic_pdm_raw_capture.vhd] \
    [file join $source_hdl acoustic_pdm_raw_registers.vhd] \
    [file join $source_hdl acoustic_pdm_raw_control.vhd]]
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
set_property -dict [list CONFIG.PCW_USE_S_AXI_HP0 1 CONFIG.PCW_S_AXI_HP0_DATA_WIDTH 32] $ps

set reset [create_bd_cell -type ip -vlnv xilinx.com:ip:proc_sys_reset:5.0 rst_ps7_0_100M]
# FCLK_RESET0_N is active low. The unused auxiliary/debug resets are tied low,
# therefore aux_reset_in MUST be active high or the entire AXI bus stays reset.
set_property -dict [list CONFIG.C_EXT_RESET_HIGH 0 CONFIG.C_AUX_RESET_HIGH 1] $reset
set smartconnect [create_bd_cell -type ip -vlnv xilinx.com:ip:smartconnect:1.0 axi_smc_0]
set_property -dict [list CONFIG.NUM_SI 1 CONFIG.NUM_MI 2] $smartconnect
set control [create_bd_cell -type module -reference acoustic_pdm_raw_control acoustic_capture_0]

set dma [create_bd_cell -type ip -vlnv xilinx.com:ip:axi_dma:7.1 axi_dma_audio]
set_property -dict [list CONFIG.c_include_sg 0 CONFIG.c_include_mm2s 0 \
    CONFIG.c_include_s2mm 1 CONFIG.c_sg_length_width 23 CONFIG.c_addr_width 32 \
    CONFIG.c_m_axi_s2mm_data_width 32 CONFIG.c_s_axis_s2mm_tdata_width 32 \
    CONFIG.c_s2mm_burst_size 16] $dma
set memory_connect [create_bd_cell -type ip -vlnv xilinx.com:ip:smartconnect:1.0 dma_to_hp0]
set_property -dict [list CONFIG.NUM_SI 1 CONFIG.NUM_MI 1] $memory_connect

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
make_bd_pins_external -name pdm_data_i [get_bd_pins $control/pdm_data_i]

set control_axi [get_bd_intf_pins -quiet $control/s_axi]
if {[llength $control_axi] != 1} {
    error "Vivado did not infer the control block's AXI4-Lite slave interface"
}

connect_bd_intf_net [get_bd_intf_pins $ps/M_AXI_GP0] [get_bd_intf_pins $smartconnect/S00_AXI]
connect_bd_intf_net [get_bd_intf_pins $smartconnect/M00_AXI] $control_axi

connect_bd_intf_net [get_bd_intf_pins $smartconnect/M01_AXI] [get_bd_intf_pins $dma/S_AXI_LITE]
connect_bd_intf_net [get_bd_intf_pins $control/m_axis] [get_bd_intf_pins $dma/S_AXIS_S2MM]
connect_bd_intf_net [get_bd_intf_pins $dma/M_AXI_S2MM] [get_bd_intf_pins $memory_connect/S00_AXI]
connect_bd_intf_net [get_bd_intf_pins $memory_connect/M00_AXI] [get_bd_intf_pins $ps/S_AXI_HP0]
connect_bd_net [get_bd_pins $dma/s2mm_prmry_reset_out_n] [get_bd_pins $control/stream_resetn_i]
connect_bd_net [get_bd_pins $ps/FCLK_CLK0] \
    [get_bd_pins $ps/M_AXI_GP0_ACLK] \
    [get_bd_pins $smartconnect/aclk] \
    [get_bd_pins $reset/slowest_sync_clk] \
    [get_bd_pins $control/aclk] \
    [get_bd_pins $dma/s_axi_lite_aclk] [get_bd_pins $dma/m_axi_s2mm_aclk] \
    [get_bd_pins $memory_connect/aclk] \
    [get_bd_pins $ps/S_AXI_HP0_ACLK]
connect_bd_net [get_bd_pins $ps/FCLK_RESET0_N] [get_bd_pins $reset/ext_reset_in]
connect_bd_net [get_bd_pins $reset/peripheral_aresetn] [get_bd_pins $control/aresetn] [get_bd_pins $dma/axi_resetn]
connect_bd_net [get_bd_pins $reset/interconnect_aresetn] [get_bd_pins $smartconnect/aresetn] [get_bd_pins $memory_connect/aresetn]
connect_bd_net [get_bd_pins $lock_constant/dout] [get_bd_pins $reset/dcm_locked]
connect_bd_net [get_bd_pins $reset_constant/dout] \
    [get_bd_pins $reset/aux_reset_in] \
    [get_bd_pins $reset/mb_debug_sys_rst]

set control_reg [get_bd_addr_segs -quiet $control/s_axi/reg0]
if {[llength $control_reg] != 1} {
    error "Could not identify the AXI-Lite control register segment"
}
assign_bd_address -offset 0x43C00000 -range 64K $control_reg

assign_bd_address -offset 0x40400000 -range 64K [get_bd_addr_segs $dma/S_AXI_LITE/Reg]
# Map DMA writes onto the PS DDR address range; AXI-Lite uses the separate GP0 path.
assign_bd_address

validate_bd_design
if {[get_property CONFIG.C_EXT_RESET_HIGH $reset] != 0 ||
    [get_property CONFIG.C_AUX_RESET_HIGH $reset] != 1} {
    error "Reset polarity mismatch: FCLK_RESET0_N low-active, auxiliary reset high-active required"
}
save_bd_design
write_bd_tcl -force [file join $run_root pdm_raw_capture_replay.tcl]

set bd_file [file join $project_root "${project_name}.srcs" sources_1 bd $bd_name "${bd_name}.bd"]
if {![file isfile $bd_file]} {
    error "Vivado did not save the candidate block design at the expected path"
}
# Generate only the HDL wrapper. No synthesis, implementation or bitstream in step 3.4.
set wrapper_generated [lindex [make_wrapper -files [get_files $bd_file] -top] 0]
add_files -norecurse $wrapper_generated
add_files -fileset constrs_1 -norecurse $source_constraints
set_property top pdm_raw_capture_wrapper [get_filesets sources_1]
update_compile_order -fileset sources_1
foreach {key expected} {c_include_sg 0 c_include_mm2s 0 c_include_s2mm 1 c_sg_length_width 23 c_m_axi_s2mm_data_width 32 c_s_axis_s2mm_tdata_width 32} {
    if {[get_property CONFIG.$key $dma] != $expected} {error "DMA parameter mismatch: $key"}
}
file copy -force $bd_file $tracked_bd
file copy -force $wrapper_generated $tracked_wrapper
puts "RAW_BD_VALIDATED=$tracked_bd"
puts "PROJECT_FILE=[file join $project_root ${project_name}.xpr]"
puts "BITSTREAM_GENERATED=NO"
close_project
exit
