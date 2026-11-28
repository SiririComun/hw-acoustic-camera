# PCM/RAW shared input vector timing; used with pynq_z2_pcm.xdc.
# Conditional engineering envelope, NOT a measured or guaranteed microphone delay:
# FPGA clock output path <=10 ns, external CLK-pad -> DATA-pad <=90 ns,
# DATA input path/setup <=10 ns. Third 24 MHz edge after falling PDM is 125 ns.
# The routed report must check these assumptions and the actual edge pair.
# Anchor the generated clock through the actual divider register C->Q. The
# reset clamp is another clocked cone into the output AND and is not its source.
create_generated_clock -name pdm_clk_o \
    -source [get_pins -hier -filter {NAME =~ */pdm_clk_reg_reg/C}] \
    -divide_by 10 [get_ports pdm_clk_o]
set raw_data [get_ports {pdm_data_i[*]}]
set raw_samples [get_cells -hier -regexp {.*capture_i/sampled_pdm_reg\[[0-3]\]$}]
set_input_delay -clock [get_clocks pdm_clk_o] -clock_fall -max 90.000 $raw_data
# Zero min is conservative; this is not a claim that the sensor enables at 0 ns.
set_input_delay -clock [get_clocks pdm_clk_o] -clock_fall -min 0.000 $raw_data
# Default STA picks the first 24 MHz edge following PDM fall. The actual shared
# CE selects the third. Scope both setup/hold adjustments to DATA endpoints only.
set_multicycle_path -setup 3 -end -from $raw_data -to $raw_samples
set_multicycle_path -hold 2 -end -from $raw_data -to $raw_samples
# Only the first stage of each explicit two-flop level/toggle synchronizer is
# asynchronous. Keep stages 1->2 and all other paths timed; never group clocks.
set raw_cdc_first [get_pins -hier -regexp {.*capture_i/(start_pipe|clear_pipe|stop_pipe|recover_pipe|recover_ack_pipe|read_busy_pipe|snapshot_req_pipe|snapshot_ack_pipe|filter_ready_pipe)_reg\[0\]/D$}]
set_false_path -to $raw_cdc_first
# Held buses use the separately synchronized request toggle, NOT per-bit flops.
# Snapshot is consumed no earlier than the third 100 MHz edge (>=20 ns from
# source update); bound data+logic to 15 ns. START config has >=2*41.667 ns
# to settle before the 24 MHz consumer; constrain it to one 24 MHz period.
set raw_snapshot [get_cells -hier -regexp {.*capture_i/snapshot_data_reg\[[0-9]+\]$}]
set raw_config [get_cells -hier -regexp {.*capture_i/(block_length_reg\[[0-9]+\]|block_pattern_reg|block_pcm_reg)$}]
set_max_delay -datapath_only 15.000 -from $raw_snapshot -to [get_clocks clk_fpga_0]
set_max_delay -datapath_only 41.667 -from $raw_config -to [get_clocks clk24_mmcm]
# XPM supplies its own internal FIFO pointer/reset constraints. DATA paths above
# remain fully analysed. No blanket exceptions cover status, FIFO or reset logic.
