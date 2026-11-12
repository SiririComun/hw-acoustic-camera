library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use STD.TEXTIO.ALL;
use STD.ENV.ALL;

entity tb_pdm_raw_capture is end;
architecture test of tb_pdm_raw_capture is
    signal clk24, clk100 : std_logic := '0';
    signal resetn, stream_resetn, ready_clock : std_logic := '0';
    signal ce, start_cmd, abort_cmd, clear_cmd, config_cmd : std_logic := '0';
    signal n_frames : std_logic_vector(31 downto 0) := (others => '0');
    signal source_pattern : std_logic := '1';
    signal busy, done, valid, last, ready : std_logic;
    signal errors : std_logic_vector(2 downto 0);
    signal produced, sent, overflows, data : std_logic_vector(31 downto 0);
    signal keep : std_logic_vector(3 downto 0);
    signal read_cycle, case_id, expected_n, received : natural := 0;
    signal expected_pattern : boolean := true;
    signal ready_mode : natural range 0 to 2 := 0;
    signal hold_last : boolean := false;

    procedure pulse(signal command : out std_logic; signal clk : in std_logic) is
    begin
        wait until falling_edge(clk); command <= '1';
        wait until falling_edge(clk); command <= '0';
    end procedure;
begin
    clk24 <= not clk24 after 20833 ps;
    clk100 <= not clk100 after 5 ns;
    dut : entity work.acoustic_pdm_raw_capture
        generic map (G_FIFO_DEPTH => 8192)
        port map (
            clk_24m_i => clk24, resetn_24m_i => resetn,
            clk_100m_i => clk100, resetn_100m_i => resetn,
            sample_ce_i => ce, pdm_data_i => "1010", clock_ready_i => ready_clock,
            start_i => start_cmd, abort_i => abort_cmd, clear_i => clear_cmd,
            config_error_i => config_cmd, n_frames_i => n_frames,
            source_pattern_i => source_pattern, stream_resetn_i => stream_resetn,
            busy_o => busy, done_o => done, error_flags_o => errors,
            frames_produced_o => produced, words_sent_o => sent, overflow_count_o => overflows,
            m_axis_tdata => data, m_axis_tkeep => keep, m_axis_tlast => last,
            m_axis_tvalid => valid, m_axis_tready => ready);

    process (clk24)
        variable phase : natural range 0 to 9 := 0;
    begin
        if rising_edge(clk24) then
            if resetn = '0' then phase := 0; ce <= '0';
            else
                if phase = 9 then phase := 0; else phase := phase + 1; end if;
                if phase = 2 then ce <= '1'; else ce <= '0'; end if;
            end if;
        end if;
    end process;
    process (clk100)
    begin
        if rising_edge(clk100) then read_cycle <= read_cycle + 1; end if;
    end process;
    ready <= '0' when ready_mode = 0 or (hold_last and valid = '1' and last = '1')
        else '1' when ready_mode = 2 or read_cycle mod 7 >= 2 else '0';

    -- Always checks AXI stability, including errored blocks. Content/count
    -- checking applies to the explicitly identified successful capture cases.
    process
        file trace : text open write_mode is "stream-trace.csv";
        variable row : line;
        variable previous_case, index : natural := 0;
        variable held : boolean := false;
        variable held_data : std_logic_vector(31 downto 0);
        variable held_last : std_logic;
        variable expected : unsigned(31 downto 0);
    begin
        write(row, string'("case_id,index,word,last,keep")); writeline(trace, row);
        loop
            wait until rising_edge(clk100);
            if resetn = '0' or stream_resetn = '0' then held := false;
            else
                if held then
                    assert valid = '1' and data = held_data and last = held_last and keep = "1111"
                        report "AXI word withdrawn/changed under backpressure" severity failure;
                end if;
                held := valid = '1' and ready = '0';
                held_data := data; held_last := last;
            end if;
            if case_id /= previous_case then
                index := 0; received <= 0; previous_case := case_id;
            end if;
            if resetn = '1' and stream_resetn = '1' and valid = '1' and ready = '1' and case_id /= 0 then
                assert index < expected_n report "Extra stream word" severity failure;
                if expected_pattern then expected := to_unsigned(index, 32);
                else expected := to_unsigned(10, 32); end if;
                assert unsigned(data) = expected report "RAW word lost, duplicated or reordered" severity failure;
                assert keep = "1111" report "Bad TKEEP" severity failure;
                if index = expected_n - 1 then
                    assert last = '1' report "Missing final TLAST" severity failure;
                else assert last = '0' report "Early TLAST" severity failure; end if;
                write(row, case_id); write(row, string'(",")); write(row, index);
                write(row, string'(",")); write(row, to_integer(unsigned(data)));
                write(row, string'(","));
                if last = '1' then write(row, 1); else write(row, 0); end if;
                write(row, string'(",15")); writeline(trace, row);
                index := index + 1; received <= index;
            end if;
        end loop;
    end process;

    process
        procedure idle_wait is
        begin
            for cycle in 1 to 1000 loop
                wait until rising_edge(clk100); wait for 1 ps;
                exit when busy = '0';
            end loop;
            assert busy = '0' report "Recovery/clear did not become idle" severity failure;
        end procedure;
        procedure clear_block is
        begin
            pulse(clear_cmd, clk100); idle_wait;
            assert errors = "000" and done = '0' and unsigned(produced) = 0
                and unsigned(sent) = 0 and unsigned(overflows) = 0
                report "CLEAR left stale errors/counters" severity failure;
        end procedure;
        procedure recover is
            variable saved_errors : std_logic_vector(2 downto 0);
        begin
            saved_errors := errors;
            wait until falling_edge(clk100); stream_resetn <= '0';
            for cycle in 1 to 20 loop wait until falling_edge(clk100); end loop;
            stream_resetn <= '1'; idle_wait;
            assert valid = '0' and done = '0' report "Recovery left a pending word" severity failure;
            assert (errors and saved_errors) = saved_errors
                report "Local stream reset erased sticky errors" severity failure;
            clear_block;
        end procedure;
        procedure capture(id, n : positive; pattern : boolean := true; stall_final : boolean := false) is
            variable sent_before : unsigned(31 downto 0);
        begin
            wait until falling_edge(clk100);
            case_id <= id; expected_n <= n; expected_pattern <= pattern;
            n_frames <= std_logic_vector(to_unsigned(n, 32));
            if pattern then source_pattern <= '1'; else source_pattern <= '0'; end if;
            ready_mode <= 1; hold_last <= stall_final;
            pulse(start_cmd, clk100);
            -- Upstream configuration must remain the accepted block's values,
            -- regardless of later values on the external command mailbox pins.
            n_frames <= (others => '0'); source_pattern <= not source_pattern;
            if stall_final then
                wait until valid = '1' and last = '1' for 5 ms;
                assert valid = '1' and last = '1' severity failure;
                sent_before := unsigned(sent);
                for cycle in 1 to 50 loop wait until rising_edge(clk100); end loop;
                wait for 1 ps;
                assert done = '0' and busy = '1' and unsigned(sent) = sent_before
                    report "DONE/WORDS_SENT advanced while final TLAST was stalled" severity failure;
                hold_last <= false;
            end if;
            wait until done = '1' for 40 ms;
            wait for 1 ps;
            assert done = '1' and busy = '0' and errors = "000" and unsigned(overflows) = 0
                report "Capture did not complete cleanly" severity failure;
            assert unsigned(produced) = n and unsigned(sent) = n and received = n
                report "Final frame/handshake counts differ from N" severity failure;
            report "STREAM_CASE_PASS " & integer'image(id) & " frames=" & integer'image(n);
            wait until falling_edge(clk100); ready_mode <= 0; case_id <= 0;
        end procedure;
    begin
        wait for 200 ns; resetn <= '1'; stream_resetn <= '1'; ready_clock <= '1';
        idle_wait;
        capture(1, 1); capture(2, 2); capture(3, 17, true, true);
        capture(4, 4096); capture(5, 65536); capture(6, 17, false);
        clear_block;

        -- Forced FIFO exhaustion at the real configured depth. The receiver
        -- holds word zero; overflow must not withdraw or mutate that word.
        n_frames <= std_logic_vector(to_unsigned(65536, 32)); source_pattern <= '1'; ready_mode <= 0;
        pulse(start_cmd, clk100);
        wait until errors(1) = '1' for 5 ms;
        assert errors(1) = '1' and unsigned(overflows) = 1 and done = '0' and busy = '1'
            report "FIFO overflow was not reported" severity failure;
        assert unsigned(produced) >= 8190 and unsigned(produced) <= 8194
            and unsigned(sent) = 0 and valid = '1' and unsigned(data) = 0
            report "FIFO capacity/accounting mismatch" severity failure;
        pulse(clear_cmd, clk100);
        assert errors(0) = '1' and errors(1) = '1' and valid = '1'
            report "Illegal CLEAR concealed active overflow" severity failure;
        recover;
        capture(7, 17);
        report "STREAM_OVERFLOW_RECOVERY_PASS";
        clear_block;

        n_frames <= std_logic_vector(to_unsigned(4096, 32)); source_pattern <= '1'; ready_mode <= 0;
        pulse(start_cmd, clk100);
        wait until valid = '1' for 10 us;
        assert valid = '1' severity failure;
        pulse(abort_cmd, clk100);
        for cycle in 1 to 30 loop wait until rising_edge(clk100); end loop;
        assert errors(2) = '1' and done = '0' and busy = '1' and valid = '1'
            report "ABORT did not preserve the offered AXI word" severity failure;
        recover; capture(8, 2);
        report "STREAM_ABORT_RECOVERY_PASS";
        clear_block;

        -- Invalid lengths and unavailable clock reject START explicitly.
        n_frames <= (others => '0'); pulse(start_cmd, clk100);
        assert errors(0) = '1' and busy = '0' and valid = '0' severity failure;
        clear_block;
        n_frames <= std_logic_vector(to_unsigned(65537, 32)); pulse(start_cmd, clk100);
        assert errors(0) = '1' and busy = '0' severity failure;
        clear_block;
        ready_clock <= '0'; n_frames <= std_logic_vector(to_unsigned(17, 32));
        pulse(start_cmd, clk100);
        assert errors(0) = '1' and busy = '0' severity failure;
        ready_clock <= '1'; clear_block;

        -- A forbidden register write will enter this port from the AXI-Lite
        -- adapter. It invalidates the entire active block without changing it.
        n_frames <= std_logic_vector(to_unsigned(4096, 32)); pulse(start_cmd, clk100);
        wait until valid = '1' for 10 us;
        assert valid = '1' severity failure;
        pulse(config_cmd, clk100);
        assert errors(0) = '1' and done = '0' and busy = '1' severity failure;
        recover; capture(9, 17);
        report "STREAM_CONFIG_RECOVERY_PASS";
        clear_block;

        n_frames <= std_logic_vector(to_unsigned(17, 32)); ready_mode <= 0;
        pulse(start_cmd, clk100); wait until valid = '1' for 10 us;
        pulse(start_cmd, clk100);
        assert errors(0) = '1' and busy = '1' report "START in BUSY was not rejected" severity failure;
        recover; capture(10, 1);
        clear_block;

        n_frames <= std_logic_vector(to_unsigned(17, 32)); ready_mode <= 0;
        pulse(start_cmd, clk100); wait until valid = '1' for 10 us;
        resetn <= '0'; wait for 200 ns; resetn <= '1'; idle_wait;
        assert errors = "000" and done = '0' and valid = '0' severity failure;
        capture(11, 1);
        report "STREAM_GLOBAL_RESET_PASS";
        report "PDM_RAW_STREAM_ALL_PASS";
        finish;
    end process;
    process
    begin
        wait for 100 ms;
        assert false report "Stream simulation watchdog expired" severity failure;
    end process;
end test;
