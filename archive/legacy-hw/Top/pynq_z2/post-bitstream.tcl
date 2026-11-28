# Hog calls this while write_bitstream is still finishing. Do not export hardware
# here or copy an HWH from sources. build_reference.py exports the completed
# implemented design in a separate Vivado process, then packages its BIT/HWH.
send_msg_id "AcousticCamera-1" "INFO" \
    "Bitstream hook finished; paired PYNQ export follows Hog WORK via scripts/build_reference.py."
