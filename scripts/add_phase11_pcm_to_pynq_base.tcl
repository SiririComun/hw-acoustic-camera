# Add the accepted continuous PCM subsystem to the pinned PYNQ-Z2 Base BD.
# Usage: vivado -mode batch -source this_file -tclargs BASE.xpr HW_REPO_ROOT
# This edits only the isolated Base project supplied by the build harness.

if {$argc != 2} {error "Expected BASE.xpr and HW repository root"}
lassign $argv project_path hw_repo
set project_path [file normalize $project_path]
set hw_repo [file normalize $hw_repo]

foreach path [list \
    [file join $hw_repo src hdl acoustic_pdm_clock.vhd] \
    [file join $hw_repo src hdl acoustic_pcm_filter_pkg.vhd] \
    [file join $hw_repo src hdl acoustic_pdm_pcm_filter.vhd] \
    [file join $hw_repo src hdl acoustic_pdm_pcm_continuous_capture.vhd] \
    [file join $hw_repo src hdl acoustic_pdm_pcm_continuous_registers.vhd] \
    [file join $hw_repo src hdl acoustic_pdm_pcm_continuous_control.vhd] \
    [file join $hw_repo src hdl acoustic_video_marker.vhd] \
    [file join $hw_repo src con pynq_z2_pcm.xdc] \
    [file join $hw_repo src con pynq_z2_pcm_continuous_timing.xdc]] {
    if {![file isfile $path]} {error "Missing phase-7 PCM source: $path"}
}

open_project $project_path
set bd_files [get_files -quiet */base.bd]
if {[llength $bd_files] != 1} {error "Expected one PYNQ Base Block Design; found $bd_files"}
open_bd_design $bd_files
current_bd_design base

foreach cell {ps7_0 ps7_0_axi_periph axi_mem_intercon rst_ps7_0_fclk3} {
    if {[llength [get_bd_cells -quiet /$cell]] != 1} {
        error "PYNQ Base cell missing or ambiguous: $cell"
    }
}
foreach name {acoustic_capture_0 axi_dma_audio axi_smc_pcm_lite} {
    if {[llength [get_bd_cells -quiet /$name]] != 0} {
        error "Refusing to overwrite existing cell: $name"
    }
}

# Pmod B is the physical PCM header. Remove the Base external GPIO port so its
# eight package pins are not driven by the IOP and can be assigned to PDM.
set pmod_b_port [get_bd_intf_ports -quiet pmodb_gpio]
if {[llength $pmod_b_port] != 1} {error "Expected the PYNQ Base Pmod B port"}
delete_bd_objs $pmod_b_port

add_files -norecurse [list \
    [file join $hw_repo src hdl acoustic_pdm_clock.vhd] \
    [file join $hw_repo src hdl acoustic_pcm_filter_pkg.vhd] \
    [file join $hw_repo src hdl acoustic_pdm_pcm_filter.vhd] \
    [file join $hw_repo src hdl acoustic_pdm_pcm_continuous_capture.vhd] \
    [file join $hw_repo src hdl acoustic_pdm_pcm_continuous_registers.vhd] \
    [file join $hw_repo src hdl acoustic_pdm_pcm_continuous_control.vhd]]
update_compile_order -fileset sources_1

set ps [get_bd_cells /ps7_0]
if {[get_property CONFIG.PCW_S_AXI_HP2_DATA_WIDTH $ps] != 64 ||
    [get_property CONFIG.PCW_USE_S_AXI_HP2 $ps] != 1} {
    error "PYNQ Base must expose a 64-bit PS HP2 port for PCM"
}

set ps_lite [get_bd_cells /ps7_0_axi_periph]
set_property CONFIG.NUM_MI 9 $ps_lite
set memory_interconnect [get_bd_cells /axi_mem_intercon]
set_property CONFIG.NUM_SI 4 $memory_interconnect

set control [create_bd_cell -type module -reference acoustic_pdm_pcm_continuous_control acoustic_capture_0]
set dma [create_bd_cell -type ip -vlnv xilinx.com:ip:axi_dma:7.1 axi_dma_audio]
set_property -dict [list \
    CONFIG.c_include_sg 1 \
    CONFIG.c_include_mm2s 0 \
    CONFIG.c_include_s2mm 1 \
    CONFIG.c_sg_length_width 23 \
    CONFIG.c_addr_width 32 \
    CONFIG.c_m_axi_s2mm_data_width 32 \
    CONFIG.c_s_axis_s2mm_tdata_width 32 \
    CONFIG.c_s2mm_burst_size 16 \
    CONFIG.c_sg_include_stscntrl_strm 0] $dma
set lite_connect [create_bd_cell -type ip -vlnv xilinx.com:ip:smartconnect:1.0 axi_smc_pcm_lite]
set_property -dict [list CONFIG.NUM_SI 1 CONFIG.NUM_MI 2] $lite_connect

make_bd_pins_external -name pdm_clk_o [get_bd_pins $control/pdm_clk_o]
make_bd_pins_external -name pdm_data_i [get_bd_pins $control/pdm_data_i]

connect_bd_intf_net [get_bd_intf_pins /ps7_0_axi_periph/M08_AXI] \
    [get_bd_intf_pins $lite_connect/S00_AXI]
connect_bd_intf_net [get_bd_intf_pins $lite_connect/M00_AXI] \
    [get_bd_intf_pins $control/s_axi]
connect_bd_intf_net [get_bd_intf_pins $lite_connect/M01_AXI] \
    [get_bd_intf_pins $dma/S_AXI_LITE]
connect_bd_intf_net [get_bd_intf_pins $control/m_axis] \
    [get_bd_intf_pins $dma/S_AXIS_S2MM]
connect_bd_intf_net [get_bd_intf_pins /axi_mem_intercon/S02_AXI] \
    [get_bd_intf_pins $dma/M_AXI_S2MM]
connect_bd_intf_net [get_bd_intf_pins /axi_mem_intercon/S03_AXI] \
    [get_bd_intf_pins $dma/M_AXI_SG]
connect_bd_net [get_bd_pins $dma/s2mm_prmry_reset_out_n] \
    [get_bd_pins $control/stream_resetn_i]

# Keep the complete PCM control/DMA path on the Base 100 MHz FCLK3 domain;
# HP2 and its existing memory arbiter already use this same clock.
set clk3 [get_bd_pins /ps7_0/FCLK_CLK3]
connect_bd_net $clk3 \
    [get_bd_pins /ps7_0_axi_periph/M08_ACLK] \
    [get_bd_pins $lite_connect/aclk] \
    [get_bd_pins $control/aclk] \
    [get_bd_pins $dma/s_axi_lite_aclk] \
    [get_bd_pins $dma/m_axi_s2mm_aclk] \
    [get_bd_pins $dma/m_axi_sg_aclk] \
    [get_bd_pins /axi_mem_intercon/S02_ACLK] \
    [get_bd_pins /axi_mem_intercon/S03_ACLK]

set reset3 [get_bd_pins /rst_ps7_0_fclk3/peripheral_aresetn]
connect_bd_net $reset3 \
    [get_bd_pins /ps7_0_axi_periph/M08_ARESETN] \
    [get_bd_pins $lite_connect/aresetn] \
    [get_bd_pins $control/aresetn] \
    [get_bd_pins $dma/axi_resetn] \
    [get_bd_pins /axi_mem_intercon/S02_ARESETN] \
    [get_bd_pins /axi_mem_intercon/S03_ARESETN]

set dma_params [list \
    c_include_sg 1 c_include_mm2s 0 c_include_s2mm 1 \
    c_sg_length_width 23 c_m_axi_s2mm_data_width 32 \
    c_s_axis_s2mm_tdata_width 32 c_sg_include_stscntrl_strm 0]
foreach {key expected} $dma_params {
    if {[get_property CONFIG.$key $dma] != $expected} {
        error "Unexpected AXI DMA property $key"
    }
}

set control_reg [get_bd_addr_segs -quiet $control/s_axi/reg0]
if {[llength $control_reg] != 1} {error "PCM control register segment is missing"}
assign_bd_address -offset 0x43C80000 -range 64K $control_reg -force
assign_bd_address -offset 0x40400000 -range 64K \
    [get_bd_addr_segs $dma/S_AXI_LITE/Reg] -force

# PCM uses HP2; video VDMA remains isolated on HP0. Map both the payload and
# descriptor fetch address spaces onto the same PS DDR window behind HP2.
foreach space [list $dma/Data_S2MM $dma/Data_SG] {
    assign_bd_address -offset 0x10000000 -range 0x10000000 \
        -target_address_space [get_bd_addr_spaces $space] \
        [get_bd_addr_segs /ps7_0/S_AXI_HP2/HP2_DDR_LOWOCM] -force
}

validate_bd_design
save_bd_design
write_bd_tcl -force [file join [file dirname $project_path] phase11_base_pcm_replay.tcl]

# Add the accepted pin map and scoped PCM timing/CDC constraints. The external
# build harness must first remove the original Base Pmod B package constraints.
add_files -fileset constrs_1 -norecurse [list \
    [file join $hw_repo src con pynq_z2_pcm.xdc] \
    [file join $hw_repo src con pynq_z2_pcm_continuous_timing.xdc]]
set_property USED_IN_SYNTHESIS false \
    [get_files pynq_z2_pcm_continuous_timing.xdc]

close_project
exit
