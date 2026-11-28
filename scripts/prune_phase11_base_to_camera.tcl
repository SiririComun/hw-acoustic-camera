# Reduce the isolated PYNQ-Z2 Base-derived BD to the Phase 11 camera paths.
# Run after add_phase11_pcm_to_pynq_base.tcl and before synthesis.
# Usage: vivado -mode batch -source this_file -tclargs BASE.xpr

if {$argc != 1} {error "Expected one isolated Base project path"}
set project_path [file normalize [lindex $argv 0]]
if {![file isfile $project_path]} {error "Project does not exist: $project_path"}

open_project $project_path
set bd_files [get_files -quiet */base.bd]
if {[llength $bd_files] != 1} {error "Expected one Base Block Design; found $bd_files"}
open_bd_design $bd_files
current_bd_design base

proc require_cell {path} {
    set cells [get_bd_cells -quiet $path]
    if {[llength $cells] != 1} {error "Expected one Block Design cell $path; found $cells"}
    return [lindex $cells 0]
}
proc delete_cell_if_present {path} {
    set cells [get_bd_cells -quiet $path]
    if {[llength $cells] == 1} {delete_bd_objs [lindex $cells 0]}
    if {[llength $cells] > 1} {error "Ambiguous Block Design cell $path"}
}
proc disconnect_pin_if_connected {pin_path} {
    set pins [get_bd_intf_pins -quiet $pin_path]
    if {[llength $pins] != 1} {error "Expected one interface pin $pin_path"}
    set nets [get_bd_intf_nets -quiet -of_objects $pins]
    if {[llength $nets] == 1} {disconnect_bd_intf_net [lindex $nets 0] $pins}
}
proc disconnect_scalar_pin_if_connected {pin_path} {
    set pins [get_bd_pins -quiet $pin_path]
    if {[llength $pins] != 1} {error "Expected one scalar pin $pin_path"}
    set nets [get_bd_nets -quiet -of_objects $pins]
    if {[llength $nets] == 1} {disconnect_bd_net [lindex $nets 0] $pins}
}
proc delete_port_if_present {path} {
    set ports [get_bd_ports -quiet $path]
    if {[llength $ports] == 1} {delete_bd_objs [lindex $ports 0]}
}
proc delete_intf_port_if_present {path} {
    set ports [get_bd_intf_ports -quiet $path]
    if {[llength $ports] == 1} {delete_bd_objs [lindex $ports 0]}
}

# The Phase 11 software uses HDMI OUT and the four-channel PCM DMA only.
# HDMI IN and its VDMA write channel are not part of this candidate.
set video_vdma [require_cell /video/axi_vdma]
set video_mem [require_cell /video/axi_mem_intercon]
set video_ctl [require_cell /video/axi_interconnect_0]
set_property CONFIG.c_include_s2mm 0 $video_vdma
delete_cell_if_present /video/hdmi_in
delete_cell_if_present /video/proc_sys_reset_pixelclk

# Put the point composition after pixel_unpack, where each 24-bit AXI beat is
# exactly one pixel. UVC frames still come from the PS framebuffer; a
# frame-latched GPIO word carries the most recent AoA projection.
current_bd_instance /video/hdmi_out
set marker [create_bd_cell -type module -reference acoustic_video_marker acoustic_video_marker]
current_bd_instance /
connect_bd_net [get_bd_pins /video/hdmi_out/clk_142M] \
    [get_bd_pins /video/hdmi_out/acoustic_video_marker/aclk]
connect_bd_net [get_bd_pins /video/hdmi_out/periph_resetn_clk142M] \
    [get_bd_pins /video/hdmi_out/acoustic_video_marker/aresetn]
disconnect_pin_if_connected /video/hdmi_out/pixel_unpack/stream_out_24
disconnect_pin_if_connected /video/hdmi_out/axis_register_slice_0/S_AXIS
connect_bd_intf_net [get_bd_intf_pins /video/hdmi_out/pixel_unpack/stream_out_24] \
    [get_bd_intf_pins /video/hdmi_out/acoustic_video_marker/S_AXIS]
connect_bd_intf_net [get_bd_intf_pins /video/hdmi_out/acoustic_video_marker/M_AXIS] \
    [get_bd_intf_pins /video/hdmi_out/axis_register_slice_0/S_AXIS]

# Keep the VDMA MM2S read path to HDMI OUT; drop its unused write-side slot.
disconnect_pin_if_connected /video/axi_mem_intercon/S00_AXI
disconnect_pin_if_connected /video/axi_mem_intercon/S01_AXI
set_property CONFIG.NUM_SI 1 $video_mem
connect_bd_intf_net [get_bd_intf_pins /video/axi_mem_intercon/S00_AXI] \
    [get_bd_intf_pins /video/axi_vdma/M_AXI_MM2S]

# The video AXI-Lite crossbar has one VDMA plus five HDMI OUT targets.
set_property CONFIG.NUM_MI 6 $video_ctl

# Remove the optional Base shell: MicroBlaze IOPs, trace analyzers, shared
# GPIO routing, board GPIO/audio blocks, and their AXI interconnects.
foreach path {
    /trace_analyzer_pi /trace_analyzer_pmodb
    /iop_arduino /iop_pmoda /iop_pmodb /iop_rpi
    /mdm_1 /wire_distribution_network
    /axi_interconnect_0 /address_remap_0 /axi_protocol_convert_0
    /ps7_0_axi_periph1 /ps7_0_axi_periph_1
    /audio_codec_ctrl_0 /btns_gpio /leds_gpio /rgbleds_gpio /switches_gpio
    /clk_wiz_10MHz /slice_pmodb_gpio /iop_interrupts
    /concat_pmodb /concat_rp /constant_8bit_0 /logic_1
    /mb_iop_arduino_intr_ack /mb_iop_arduino_reset
    /mb_iop_pmoda_intr_ack /mb_iop_pmoda_reset
    /mb_iop_pmodb_intr_ack /mb_iop_pmodb_reset
    /mb_iop_rpi_intr_ack /mb_iop_rpi_reset /pmoda_rp_pin_sel
} {delete_cell_if_present $path}

# Repack the surviving PCM DMA paths into the two remaining HP2 slots.
set memory_interconnect [require_cell /axi_mem_intercon]
disconnect_pin_if_connected /axi_mem_intercon/S02_AXI
disconnect_pin_if_connected /axi_mem_intercon/S03_AXI
set_property CONFIG.NUM_SI 2 $memory_interconnect
connect_bd_intf_net [get_bd_intf_pins /axi_mem_intercon/S00_AXI] \
    [get_bd_intf_pins /axi_dma_audio/M_AXI_S2MM]
connect_bd_intf_net [get_bd_intf_pins /axi_mem_intercon/S01_AXI] \
    [get_bd_intf_pins /axi_dma_audio/M_AXI_SG]

# Keep only the interrupt fan-in used by the HDMI/VDMA output hierarchy.
foreach {path count} {
    /concat_interrupts 1
    /xlconcat_0 1
} {
    set cell [get_bd_cells -quiet $path]
    if {[llength $cell] == 1} {set_property CONFIG.NUM_PORTS $count $cell}
}

# Retain the PS->video/interrupt/PCM AXI-Lite endpoints. Move PCM from M08
# to M02 so the primary PS interconnect contains exactly three masters.
set ps_lite [require_cell /ps7_0_axi_periph]
disconnect_pin_if_connected /ps7_0_axi_periph/M08_AXI
set_property CONFIG.NUM_MI 3 $ps_lite
connect_bd_intf_net [get_bd_intf_pins /ps7_0_axi_periph/M02_AXI] \
    [get_bd_intf_pins /axi_smc_pcm_lite/S00_AXI]
disconnect_scalar_pin_if_connected /ps7_0_axi_periph/M02_ACLK
disconnect_scalar_pin_if_connected /ps7_0_axi_periph/M02_ARESETN
connect_bd_net [get_bd_pins /ps7_0/FCLK_CLK3] \
    [get_bd_pins /ps7_0_axi_periph/M02_ACLK]
connect_bd_net [get_bd_pins /rst_ps7_0_fclk3/peripheral_aresetn] \
    [get_bd_pins /ps7_0_axi_periph/M02_ARESETN]

# Disable PS ports that existed only for removed analyzers, IOP access, and
# pin-selection GPIO. Keep the board DDR/MIO preset and HDMI output interface.
set ps [require_cell /ps7_0]
set_property -dict [list \
    CONFIG.PCW_USE_M_AXI_GP1 0 \
    CONFIG.PCW_USE_S_AXI_GP0 0 \
    CONFIG.PCW_GPIO_EMIO_GPIO_ENABLE 0 \
    CONFIG.PCW_I2C1_PERIPHERAL_ENABLE 0] $ps

# Dual-channel GPIO carries one atomic 32-bit PS configuration word per marker.
current_bd_instance /video
set marker_gpio [create_bd_cell -type ip -vlnv xilinx.com:ip:axi_gpio:2.0 acoustic_marker_gpio]
set_property -dict [list \
    CONFIG.C_IS_DUAL 1 \
    CONFIG.C_ALL_OUTPUTS 1 CONFIG.C_GPIO_WIDTH 32 \
    CONFIG.C_ALL_OUTPUTS_2 1 CONFIG.C_GPIO2_WIDTH 32] $marker_gpio
current_bd_instance /
set marker_lite [require_cell /axi_smc_pcm_lite]
set_property CONFIG.NUM_MI 5 $marker_lite
connect_bd_intf_net -boundary_type both \
    [get_bd_intf_pins /axi_smc_pcm_lite/M04_AXI] \
    [get_bd_intf_pins $marker_gpio/S_AXI]
connect_bd_net -boundary_type both \
    [get_bd_pins $marker_gpio/gpio_io_o] \
    [get_bd_pins /video/hdmi_out/acoustic_video_marker/marker_cfg_i]
connect_bd_net -boundary_type both \
    [get_bd_pins $marker_gpio/gpio2_io_o] \
    [get_bd_pins /video/hdmi_out/acoustic_video_marker/marker_cfg2_i]
connect_bd_net [get_bd_pins /ps7_0/FCLK_CLK3] \
    [get_bd_pins $marker_gpio/s_axi_aclk]
connect_bd_net [get_bd_pins /rst_ps7_0_fclk3/peripheral_aresetn] \
    [get_bd_pins $marker_gpio/s_axi_aresetn]
assign_bd_address -offset 0x43C90000 -range 64K \
    [get_bd_addr_segs $marker_gpio/S_AXI/Reg] -force

# Drop HDMI IN hierarchy ports and all unneeded external Base interfaces.
foreach path {/video/TMDS_in /video/DDC} {
    set pins [get_bd_intf_pins -quiet $path]
    if {[llength $pins] == 1} {delete_bd_objs [lindex $pins 0]}
}
foreach path {/video/hdmi_in_hpd /video/hdmi_in_hpd_irq} {
    set pins [get_bd_pins -quiet $path]
    if {[llength $pins] == 1} {delete_bd_objs [lindex $pins 0]}
}
foreach name [get_bd_intf_ports -quiet] {
    if {[get_property NAME $name] ni {DDR FIXED_IO hdmi_out}} {
        delete_bd_objs $name
    }
}
foreach name [get_bd_ports -quiet] {
    set intf_parent [get_bd_intf_ports -quiet -of_objects $name]
    if {[llength $intf_parent] != 0} {continue}
    if {[get_property NAME $name] ni {pdm_clk_o pdm_data_i buzzer_pulse_o hdmi_out_hpd}} {
        delete_bd_objs $name
    }
}

# The returned image requires only output VDMA MM2S; its interrupt is already
# included in the HDMI hierarchy's surviving interrupt fan-in.
validate_bd_design
save_bd_design

set forbidden {/iop_arduino /iop_pmoda /iop_pmodb /iop_rpi \
    /trace_analyzer_pi /trace_analyzer_pmodb /video/hdmi_in /audio_codec_ctrl_0}
foreach path $forbidden {
    if {[llength [get_bd_cells -quiet $path]] != 0} {
        error "Unneeded Base component remains after pruning: $path"
    }
}
foreach required {/ps7_0 /video /video/hdmi_out /video/axi_vdma \
                 /video/hdmi_out/acoustic_video_marker /acoustic_capture_0 \
                 /video/acoustic_marker_gpio /acoustic_buzzer_pulse \
                 /acoustic_pcm_axis_tee /acoustic_pcm_iq_tracker \
                 /axi_dma_audio /axi_mem_intercon} {
    require_cell $required
}
if {[get_property CONFIG.NUM_MI $ps_lite] != 3 ||
    [get_property CONFIG.NUM_MI $marker_lite] != 5 ||
    [get_property CONFIG.NUM_SI $memory_interconnect] != 2 ||
    [get_property CONFIG.NUM_MI $video_ctl] != 6 ||
    [get_property CONFIG.NUM_SI $video_mem] != 1 ||
    [get_property CONFIG.c_include_s2mm $video_vdma] != 0} {
    error "The pruned AXI/video configuration does not match the buzzer-enabled candidate"
}

# The marker GPIO config is sampled through two ASYNC_REG stages in the pixel
# clock domain. Exclude only the asynchronous paths into the first stage.
set marker_cdc_xdc [file normalize [file join [file dirname [info script]] .. src con phase11_marker_cdc.xdc]]
if {![file isfile $marker_cdc_xdc]} {error "Missing marker CDC constraints: $marker_cdc_xdc"}
add_files -fileset constrs_1 -norecurse $marker_cdc_xdc
set marker_cdc_file [get_files -quiet $marker_cdc_xdc]
if {[llength $marker_cdc_file] != 1} {error "Expected one marker CDC constraints file"}
set_property USED_IN_SYNTHESIS false $marker_cdc_file

write_bd_tcl -force [file join [file dirname $project_path] phase11_camera_minimal.tcl]
close_project
exit
