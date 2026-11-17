library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use STD.ENV.ALL;

entity tb_pdm_pcm_continuous_capture is end;

architecture test of tb_pdm_pcm_continuous_capture is
    signal clk24 : std_logic := '0';
    signal clk100 : std_logic := '0';
    signal resetn, stream_resetn, ready_clock : std_logic := '0';
    signal ce, start_cmd, stop_cmd, abort_cmd, clear_cmd, config_cmd : std_logic := '0';
    signal continuous, source_pattern, format_pcm : std_logic := '1';
    signal n_frames : std_logic_vector(31 downto 0) := (others => '0');
    signal busy, done, valid, last, ready : std_logic;
    signal errors : std_logic_vector(2 downto 0);
    signal produced, sent, overflows, data : std_logic_vector(31 downto 0);
    signal total_frames, total_words : std_logic_vector(63 downto 0);
    signal keep : std_logic_vector(3 downto 0);
    signal filter_ready : std_logic;
    signal clip_count : std_logic_vector(31 downto 0);
    signal read_cycle : natural := 0;
    signal ready_mode : natural range 0 to 2 := 0;
    signal monitor_enable, monitor_continuous : std_logic := '0';
    signal monitor_epoch : std_logic := '0';
    signal packet_frames : positive := 4;
    signal finite_frames : positive := 1;
    signal seen_words, seen_frames, seen_packets : natural := 0;

    function expected_pattern(frame_index, channel : natural) return std_logic_vector is
        variable payload : signed(23 downto 0);
    begin
        payload := signed(std_logic_vector(to_unsigned(frame_index mod 1048576, 20) & to_unsigned(channel, 4)));
        return std_logic_vector(resize(payload, 32));
    end function;

    procedure pulse(signal command : out std_logic; signal clk : in std_logic) is
    begin
        wait until falling_edge(clk); command <= '1';
        wait until falling_edge(clk); command <= '0';
    end procedure;
begin
    clk24 <= not clk24 after 6 ns;
    clk100 <= not clk100 after 1 ns;
    dut : entity work.acoustic_pdm_pcm_continuous_capture
        generic map (G_FIFO_DEPTH => 2048, G_PATTERN_DECIMATION => 2)
        port map (
            clk_24m_i => clk24, resetn_24m_i => resetn,
            clk_100m_i => clk100, resetn_100m_i => resetn,
            sample_ce_i => ce, pdm_data_i => "1010",
            clock_ready_i => ready_clock, clock_ready_24m_i => ready_clock, format_pcm_i => format_pcm,
            start_i => start_cmd, abort_i => abort_cmd, clear_i => clear_cmd,
            stop_i => stop_cmd, continuous_i => continuous, config_error_i => config_cmd,
            n_frames_i => n_frames, source_pattern_i => source_pattern,
            stream_resetn_i => stream_resetn, busy_o => busy, done_o => done,
            error_flags_o => errors, filter_ready_o => filter_ready, clip_count_o => clip_count,
            frames_produced_o => produced, words_sent_o => sent, overflow_count_o => overflows,
            total_frames_o => total_frames, total_words_o => total_words,
            m_axis_tdata => data, m_axis_tkeep => keep, m_axis_tlast => last,
            m_axis_tvalid => valid, m_axis_tready => ready);

    process (clk24)
    begin
        if rising_edge(clk24) then
            if resetn = '0' then ce <= '0';
            else ce <= '1'; end if;
        end if;
    end process;

    process (clk100)
    begin
        if rising_edge(clk100) then read_cycle <= read_cycle + 1; end if;
    end process;
    ready <= '0' when ready_mode = 0
        else '1' when ready_mode = 2 or read_cycle mod 5 /= 0 else '0';

    -- Verifies the stream continuously, including packet boundaries and stalls.
    process
        variable epoch_seen : std_logic := '0';
        variable held : boolean := false;
        variable held_data : std_logic_vector(31 downto 0);
        variable held_last : std_logic;
        variable word_index, frame_index, packet_index : natural := 0;
        variable expected : std_logic_vector(31 downto 0);
        variable expected_last : std_logic;
    begin
        loop
            wait until rising_edge(clk100);
            if resetn = '0' or stream_resetn = '0' then held := false;
            else
                if held then
                    assert valid = '1' and data = held_data and last = held_last and keep = "1111"
                        report "AXI word changed or withdrew while stalled" severity failure;
                end if;
                held := valid = '1' and ready = '0';
                held_data := data; held_last := last;
            end if;

            if monitor_epoch /= epoch_seen then
                epoch_seen := monitor_epoch;
                word_index := 0; frame_index := 0; packet_index := 0;
                seen_words <= 0; seen_frames <= 0; seen_packets <= 0;
            elsif monitor_enable = '1' and resetn = '1' and stream_resetn = '1'
                and valid = '1' and ready = '1' then
                if monitor_continuous = '1' then
                    expected := expected_pattern(frame_index, word_index mod 4);
                    if (word_index mod 4) = 3 and ((frame_index + 1) mod packet_frames) = 0 then expected_last := '1';
                    else expected_last := '0'; end if;
                else
                    expected := std_logic_vector(to_unsigned(frame_index * 16 + (word_index mod 4), 32));
                    if (word_index mod 4) = 3 and frame_index + 1 = finite_frames then expected_last := '1';
                    else expected_last := '0'; end if;
                end if;
                assert data = expected report "PCM pattern lost, reordered, or not sign-extended" severity failure;
                assert keep = "1111" report "Bad TKEEP" severity failure;
                assert last = expected_last report "TLAST is not on the configured complete-frame boundary" severity failure;
                word_index := word_index + 1;
                seen_words <= word_index;
                if word_index mod 4 = 0 then
                    frame_index := frame_index + 1;
                    seen_frames <= frame_index;
                end if;
                if last = '1' then
                    packet_index := packet_index + 1;
                    seen_packets <= packet_index;
                end if;
            end if;
        end loop;
    end process;

    process
        procedure wait_idle is
        begin
            for cycle in 1 to 10000 loop
                wait until rising_edge(clk100); wait for 1 ps;
                exit when busy = '0';
            end loop;
            assert busy = '0' report "Core did not become idle" severity failure;
        end procedure;
        procedure begin_monitor(is_continuous : boolean; packet_length : positive; block_length : positive) is
        begin
            monitor_continuous <= '1' when is_continuous else '0';
            packet_frames <= packet_length;
            finite_frames <= block_length;
            monitor_enable <= '1';
            monitor_epoch <= not monitor_epoch;
            wait until rising_edge(clk100); wait for 1 ps;
        end procedure;
        procedure start_capture(is_continuous : boolean; packet_length : positive; block_length : positive; mode : natural) is
        begin
            continuous <= '1' when is_continuous else '0';
            n_frames <= std_logic_vector(to_unsigned(packet_length, 32));
            ready_mode <= mode;
            begin_monitor(is_continuous, packet_length, block_length);
            pulse(start_cmd, clk100);
            wait for 1 ps;
            assert busy = '1' and errors = "000"
                report "START rejected: busy=" & std_logic'image(busy) & " errors=" & to_hstring(errors) severity failure;
        end procedure;
        variable received_before : natural;
    begin
        wait for 200 ns; resetn <= '1'; stream_resetn <= '1'; ready_clock <= '1';
        wait_idle;

        -- Three packets with intermittent AXIS backpressure, followed by STOP.
        start_capture(true, 4, 0, 1);
        wait until seen_packets >= 3 for 10 ms;
        assert seen_packets >= 3
            report "Continuous mode did not emit three packets: packets=" & integer'image(seen_packets)
                & " frames=" & integer'image(seen_frames) & " produced=" & integer'image(to_integer(unsigned(produced)))
                & " errors=" & to_hstring(errors) & " input_mode=" & std_logic'image(continuous)
            severity failure;
        pulse(stop_cmd, clk100);
        wait until done = '1' for 20 ms;
        wait for 1 ps;
        assert done = '1' and busy = '0' and errors = "000" severity failure;
        assert seen_frames > 0 and seen_frames mod 4 = 0 and seen_words = seen_frames * 4
            report "STOP did not drain at a complete packet boundary" severity failure;
        assert unsigned(total_frames) = to_unsigned(seen_frames, 64)
            and unsigned(total_words) = to_unsigned(seen_words, 64)
            report "Continuous 64-bit totals differ from AXI handshakes" severity failure;
        report "CONTINUOUS_STALL_STOP_PASS frames=" & integer'image(seen_frames);
        monitor_enable <= '0'; ready_mode <= 0;

        -- Run through the complete 20-bit frame-index period and check the wrap.
        start_capture(true, 4096, 0, 2);
        wait until seen_frames >= 1048577 for 100 ms;
        assert seen_frames >= 1048577 report "Did not exercise a full synthetic pattern period" severity failure;
        pulse(stop_cmd, clk100);
        wait until done = '1' for 100 ms;
        wait for 1 ps;
        assert done = '1' and errors = "000" and seen_frames mod 4096 = 0
            report "Full-period run did not close on a packet boundary" severity failure;
        assert seen_words = seen_frames * 4 and unsigned(total_frames) = to_unsigned(seen_frames,64)
            and unsigned(total_words) = to_unsigned(seen_words,64)
            report "Full-period frame/word counters disagree" severity failure;
        report "CONTINUOUS_PATTERN_WRAP_PASS frames=" & integer'image(seen_frames);
        monitor_enable <= '0'; ready_mode <= 0;

        -- Exhaust the complete-frame FIFO while the receiver holds its first word.
        start_capture(true, 4, 0, 0);
        wait until errors(1) = '1' for 10 ms;
        assert errors(1) = '1' and unsigned(overflows) = 1 and done = '0' and busy = '1'
            report "Continuous FIFO overflow was not reported" severity failure;
        assert valid = '1' and unsigned(sent) = 0 report "Overflow changed or consumed the held stream word" severity failure;
        report "CONTINUOUS_OVERFLOW_PASS frames=" & integer'image(to_integer(unsigned(produced)));
        wait until falling_edge(clk100); stream_resetn <= '0';
        for cycle in 1 to 30 loop wait until falling_edge(clk100); end loop;
        stream_resetn <= '1'; wait_idle;
        assert valid = '0' and errors(1) = '1' report "Recovery lost its sticky overflow or left data pending" severity failure;
        pulse(clear_cmd, clk100); wait_idle;
        assert errors = "000" and unsigned(total_frames) = 0 and unsigned(total_words) = 0
            report "CLEAR did not reset continuous totals" severity failure;

        -- Finite PCM remains available from the separate phase-7 candidate.
        start_capture(false, 17, 17, 2);
        wait until done = '1' for 10 ms;
        wait for 1 ps;
        assert done = '1' and busy = '0' and errors = "000" and seen_frames = 17 and seen_words = 68
            report "Finite PCM compatibility failed" severity failure;
        assert unsigned(total_frames) = 17 and unsigned(total_words) = 68
            report "Finite total counters mismatch" severity failure;
        report "CONTINUOUS_PCM_ALL_PASS";
        stop;
        wait;
    end process;
end test;
