# Reapply explicit interface strengths: a BD-only clone does not preserve the
# VALUE_MODE metadata stored in generated XCI files. Preserve the audited widths
# and sample remaps rather than letting the subset IP propagate pass-through.
set reference_bd [get_files -quiet xadc.bd]
if {[llength $reference_bd] != 1} { error "Expected one reference xadc.bd" }
open_bd_design $reference_bd
foreach {name slave_bytes master_bytes remap} {
    axis_subset_converter_0 2 4 {16'b0000000000000000, ~tdata[15], tdata[14:0]}
    axis_subset_converter_1 4 2 {tdata[15:0]}
    axis_subset_converter_2 4 4 {tdata[31:0]}
    axis_subset_converter_3 4 2 {~tdata[15], tdata[14:0]}
    axis_subset_converter_cfg 2 2 {7'b0000000, 1'b0, tdata[7:0]}
} {
    set cell [get_bd_cells $name]
    foreach param {S_TDATA_NUM_BYTES M_TDATA_NUM_BYTES S_HAS_TREADY M_HAS_TREADY} {
        set_property CONFIG.${param}.VALUE_MODE MANUAL $cell
    }
    set_property -dict [list CONFIG.S_TDATA_NUM_BYTES $slave_bytes \
        CONFIG.M_TDATA_NUM_BYTES $master_bytes CONFIG.S_HAS_TREADY 1 \
        CONFIG.M_HAS_TREADY 1] $cell
    set_property CONFIG.TDATA_REMAP $remap $cell
}
validate_bd_design
save_bd_design
generate_target all $reference_bd
foreach {name slave_bytes master_bytes} {
    axis_subset_converter_0 2 4
    axis_subset_converter_1 4 2
    axis_subset_converter_2 4 4
    axis_subset_converter_3 4 2
    axis_subset_converter_cfg 2 2
} {
    set cell [get_bd_cells $name]
    if {[get_property CONFIG.S_TDATA_NUM_BYTES $cell] != $slave_bytes ||
            [get_property CONFIG.M_TDATA_NUM_BYTES $cell] != $master_bytes} {
        error "Reference width did not survive regeneration: $name"
    }
}
