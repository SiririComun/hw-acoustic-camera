# The AXI GPIO is clocked by PS FCLK3 and its stable config word is sampled
# into the PL pixel-clock domain by the two ASYNC_REG stages in
# acoustic_video_marker. The asynchronous source-to-first-stage setup path is
# intentionally excluded; paths after marker_cfg_meta remain timed normally.
set marker_cfg_source_clock [get_clocks -quiet clk_fpga_3]
set marker_cfg_first_d [get_pins -quiet -hierarchical \
    -filter {NAME =~ *acoustic_video_marker*/marker_cfg_meta_reg*/D}]

# Only FCLK3 feeds this first-stage marker register bank. The source and
# destination are clocked; cutting this one clock-to-first-stage crossing keeps
# all paths after the synchronizer under normal timing analysis.
set_false_path -from $marker_cfg_source_clock -to $marker_cfg_first_d
