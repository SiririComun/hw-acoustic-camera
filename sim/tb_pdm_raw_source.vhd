-- Digital step-3.2 checks. Timing probes deliberately change DATA around the
-- sampling edge; they are not a model or measurement of the physical sensor.
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use IEEE.STD_LOGIC_TEXTIO.ALL;
use STD.TEXTIO.ALL;
use STD.ENV.ALL;

entity tb_pdm_raw_source is
end tb_pdm_raw_source;

architecture test of tb_pdm_raw_source is
    constant C_BASE_PERIOD : time := 1 sec / 24_000_000;
    signal unit_clk : std_logic := '0';
    signal unit_resetn, unit_local_resetn, unit_source_resetn : std_logic := '0';
    signal unit_ce, unit_start, unit_gate, unit_select : std_logic := '0';
    signal unit_data : std_logic_vector(3 downto 0) := (others => '0');
    signal unit_valid : std_logic;
    signal unit_word : std_logic_vector(31 downto 0);
    signal unit_cycle : natural := 0;
    signal unit_done : boolean := false;

    signal clk100 : std_logic := '0';
    signal global_resetn, clock_enable : std_logic := '0';
    signal base_clk, base_resetn, base_ce, pdm_clk, clock_ready, mmcm_locked : std_logic;
    signal clock_local_resetn, clock_source_resetn : std_logic := '0';
    signal clock_start, clock_gate, clock_select : std_logic := '0';
    signal clock_data : std_logic_vector(3 downto 0) := (others => '0');
    signal clock_valid : std_logic;
    signal clock_word : std_logic_vector(31 downto 0);
    signal clock_cycle, pdm_rises, fall_cycle, phase_checks : natural := 0;
    signal last_fall : time := 0 ns;
    signal clock_done : boolean := false;

    procedure trace_word(file trace : text; case_id, index : natural;
                         word : std_logic_vector(31 downto 0);
                         sampled, enqueued : natural) is
        variable row : line;
    begin
        write(row, case_id); write(row, string'(","));
        write(row, index); write(row, string'(","));
        write(row, to_integer(unsigned(word))); write(row, string'(","));
        write(row, sampled); write(row, string'(",")); write(row, enqueued);
        writeline(trace, row);
    end procedure;

    procedure exercise_case(
        constant case_id : positive; constant use_pattern : boolean;
        constant n_frames : positive; constant start_on_ce : boolean;
        signal clk, ce : in std_logic; signal cycle : in natural;
        signal start, gate, selection : out std_logic;
        signal data : out std_logic_vector(3 downto 0);
        signal valid : in std_logic; signal word : in std_logic_vector(31 downto 0);
        file trace : text
    ) is
        file vectors : text open read_mode is "vectors/physical_words.hex";
        variable row : line;
        variable expected : std_logic_vector(31 downto 0);
        variable sampled, enqueued : natural;
    begin
        gate <= '0'; start <= '0';
        if use_pattern then selection <= '1'; else selection <= '0'; end if;
        if start_on_ce then
            if ce /= '1' then wait until ce = '1'; end if;
            wait for 2 ns;
            start <= '1';
        else
            wait until falling_edge(clk);
            start <= '1';
        end if;
        wait until rising_edge(clk);
        wait for 1 ps;
        assert valid = '0' report "START must not emit a sample, including START at CE" severity failure;
        wait until falling_edge(clk);
        start <= '0'; gate <= '1';
        -- Change the external selection after START: the block source must be
        -- latched, rather than changing the interpretation of an active block.
        if use_pattern then selection <= '0'; else selection <= '1'; end if;

        for index in 0 to n_frames - 1 loop
            if use_pattern then
                expected := std_logic_vector(to_unsigned(index, 32));
                data <= (others => 'X');
            else
                assert not endfile(vectors) report "Physical stimulus exhausted" severity failure;
                readline(vectors, row); hread(row, expected);
                data <= not expected(3 downto 0);
            end if;
            if ce /= '1' then wait until ce = '1'; end if;
            -- Poison before this aperture catches early capture or a stale
            -- per-channel pipeline. Poison after it catches late/live reads.
            wait for 2 ns;
            if not use_pattern then data <= expected(3 downto 0); end if;
            wait until rising_edge(clk);
            assert ce = '1' report "Stimulus missed the sampling CE" severity failure;
            sampled := cycle + 1;
            wait for 1 ps;
            assert valid = '1' report "Missing registered sample" severity failure;
            assert word = expected report "Wrong word at sampling edge" severity failure;
            if use_pattern then data <= (others => 'Z');
            else data <= not expected(3 downto 0); end if;
            -- Admission can stop while the final registered word is pending.
            if index = n_frames - 1 then gate <= '0'; end if;
            wait until rising_edge(clk);
            enqueued := cycle + 1;
            assert valid = '1' report "Pending word lost when admission stopped" severity failure;
            assert word = expected report "Word changed before FIFO enqueue edge" severity failure;
            assert enqueued = sampled + 1 report "Wrong common pipeline latency" severity failure;
            trace_word(trace, case_id, index, word, sampled, enqueued);
            wait for 1 ps;
            assert valid = '0' report "Duplicated output strobe" severity failure;
        end loop;
        for idle in 1 to 12 loop
            wait until rising_edge(clk); wait for 1 ps;
            assert valid = '0' report "Frame produced while capture admission disabled" severity failure;
        end loop;
        report "RAW_CASE_PASS " & integer'image(case_id) & " frames=" & integer'image(n_frames);
    end procedure;
begin
    unit_clk <= not unit_clk after C_BASE_PERIOD / 2;
    clk100 <= not clk100 after 5 ns when not clock_done else '0';
    unit_source_resetn <= unit_resetn and unit_local_resetn;
    clock_source_resetn <= base_resetn and clock_local_resetn;

    unit_dut : entity work.acoustic_pdm_raw_source
        port map (unit_clk, unit_source_resetn, unit_ce, unit_start, unit_gate,
                  unit_select, unit_data, unit_valid, unit_word);
    clock_dut : entity work.acoustic_pdm_clock
        port map (clk_100m_i => clk100, resetn_100m_i => global_resetn,
                  clock_enable_async_i => clock_enable, pdm_clk_o => pdm_clk,
                  clock_ready_24m_o => clock_ready, mmcm_locked_o => mmcm_locked,
                  clk_24m_o => base_clk, resetn_24m_o => base_resetn,
                  sample_ce_24m_o => base_ce);
    clock_source_dut : entity work.acoustic_pdm_raw_source
        port map (base_clk, clock_source_resetn, base_ce, clock_start, clock_gate,
                  clock_select, clock_data, clock_valid, clock_word);

    -- Independent CE fixture for the long source-only cases. The actual MMCM
    -- and divider are exercised concurrently below, through their real ports.
    process (unit_clk)
        variable phase : natural range 0 to 9 := 0;
    begin
        if rising_edge(unit_clk) then
            unit_cycle <= unit_cycle + 1;
            if unit_resetn = '0' then phase := 0; unit_ce <= '0';
            else
                if phase = 9 then phase := 0; else phase := phase + 1; end if;
                if phase = 2 then unit_ce <= '1'; else unit_ce <= '0'; end if;
            end if;
        end if;
    end process;
    process (base_clk)
    begin
        if rising_edge(base_clk) then clock_cycle <= clock_cycle + 1; end if;
    end process;

    -- Check the forwarded high half-period and timestamp the real falling
    -- edge, without consulting the divider's private counter or decode.
    process (pdm_clk, global_resetn)
        variable last_rise_cycle : natural := 0;
        variable seen_rise : boolean := false;
    begin
        if global_resetn = '0' then
            pdm_rises <= 0; seen_rise := false;
        elsif rising_edge(pdm_clk) then
            pdm_rises <= pdm_rises + 1;
            last_rise_cycle := clock_cycle;
            seen_rise := true;
        elsif falling_edge(pdm_clk) and base_resetn = '1' then
            if seen_rise then
                assert clock_cycle - last_rise_cycle = 5
                    report "PDM high phase was truncated or changed" severity failure;
            end if;
            fall_cycle <= clock_cycle;
            last_fall <= now;
        end if;
    end process;

    process
        file trace : text open write_mode is "clock-phase.csv";
        variable row : line;
        variable sampled_at : time;
        variable previous_sample : natural := 0;
        variable seen_sample : boolean := false;
    begin
        write(row, string'("sample_cycle,fall_cycle,offset_ps")); writeline(trace, row);
        loop
            wait until rising_edge(base_clk);
            if base_ce = '1' then
                sampled_at := now;
                assert clock_ready = '1' and pdm_clk = '0'
                    report "CE outside ready/low phase" severity failure;
                wait for 1 ps;
                assert clock_cycle - fall_cycle = 3
                    report "Sampling edge is not third base edge after real PDM fall" severity failure;
                assert abs((sampled_at - last_fall) - 125 ns) <= 10 ps
                    report "Sampling offset is not nominally 125 ns" severity failure;
                if seen_sample then
                    assert clock_cycle - previous_sample = 10
                        report "Sampling cadence differs from ten base cycles" severity failure;
                end if;
                previous_sample := clock_cycle; seen_sample := true;
                phase_checks <= phase_checks + 1;
                write(row, clock_cycle); write(row, string'(","));
                write(row, fall_cycle); write(row, string'(","));
                write(row, integer((sampled_at - last_fall) / 1 ps)); writeline(trace, row);
            elsif clock_ready = '0' then
                assert base_ce = '0' report "CE asserted during warmup/reset/disable" severity failure;
                if clock_gate = '1' then
                    assert clock_valid = '0' report "Capture occurred before clock readiness" severity failure;
                end if;
            end if;
        end loop;
    end process;

    process
        file trace : text open write_mode is "unit-trace.csv";
        variable row : line;
        procedure check(case_id : positive; pattern : boolean; n : positive;
                        coincident : boolean := false) is
        begin
            exercise_case(case_id, pattern, n, coincident, unit_clk, unit_ce, unit_cycle,
                          unit_start, unit_gate, unit_select, unit_data,
                          unit_valid, unit_word, trace);
        end procedure;
    begin
        write(row, string'("case_id,index,word,sample_cycle,enqueue_cycle")); writeline(trace, row);
        unit_local_resetn <= '1';
        wait for 200 ns;
        unit_resetn <= '1';
        check(1, false, 4096);
        check(2, true, 1); check(3, true, 2); check(4, true, 17);
        check(5, true, 4096); check(6, true, 65536);
        check(7, true, 17); check(8, false, 257);

        -- Local reset destroys an unconsumed internal word, without stopping
        -- the clock/CE fixture. The next START must restart the pattern at 0.
        wait until falling_edge(unit_clk);
        unit_select <= '1'; unit_start <= '1';
        wait until falling_edge(unit_clk); unit_start <= '0'; unit_gate <= '1';
        if unit_ce /= '1' then wait until unit_ce = '1'; end if;
        wait until rising_edge(unit_clk); wait for 1 ps;
        assert unit_valid = '1' and unsigned(unit_word) = 0 severity failure;
        unit_local_resetn <= '0'; unit_gate <= '0';
        wait for 1 ps;
        assert unit_valid = '0' and unsigned(unit_word) = 0
            report "Local source reset did not clear pending frame asynchronously" severity failure;
        wait until falling_edge(unit_clk); unit_local_resetn <= '1';
        check(9, true, 2); check(10, false, 1); check(11, true, 1, true);
        report "PDM_RAW_SOURCE_UNIT_PASS";
        unit_done <= true;
        wait;
    end process;

    process
        file trace : text open write_mode is "clock-trace.csv";
        variable row : line;
        variable rises_before_reset : natural;
        procedure check(case_id : positive; pattern : boolean; n : positive) is
        begin
            exercise_case(case_id, pattern, n, false, base_clk, base_ce, clock_cycle,
                          clock_start, clock_gate, clock_select, clock_data,
                          clock_valid, clock_word, trace);
        end procedure;
    begin
        write(row, string'("case_id,index,word,sample_cycle,enqueue_cycle")); writeline(trace, row);
        clock_local_resetn <= '1'; clock_gate <= '1';
        wait for 200 ns; global_resetn <= '1'; clock_enable <= '1';
        wait until clock_ready = '1'; wait for 1 ps;
        assert mmcm_locked = '1' and pdm_rises = 48000
            report "CLOCK_READY warmup differs from accepted 48000-edge behavior" severity failure;
        clock_gate <= '0';
        check(101, false, 257); check(102, true, 17); check(103, false, 17);
        rises_before_reset := pdm_rises;
        clock_local_resetn <= '0';
        for idle in 1 to 16 loop wait until rising_edge(base_clk); end loop;
        assert clock_ready = '1' and base_resetn = '1' and pdm_rises > rises_before_reset
            report "Source-local reset stopped or restarted PDM clock" severity failure;
        clock_local_resetn <= '1';
        check(104, true, 2);
        assert phase_checks >= 293 report "Too few real-clock phase checks" severity failure;

        clock_enable <= '0';
        for idle in 1 to 20 loop wait until rising_edge(base_clk); end loop;
        wait for 1 ps;
        assert pdm_clk = '0' and clock_ready = '0' and base_ce = '0'
            report "Clock disable left a clock/sample event active" severity failure;
        global_resetn <= '0'; wait for 1 ns;
        assert base_resetn = '0' and base_ce = '0' and clock_valid = '0'
            report "Global reset did not clamp source and CE" severity failure;
        report "PDM_RAW_SOURCE_CLOCK_PASS phase_checks=" & integer'image(phase_checks);
        clock_done <= true;
        wait;
    end process;

    process
    begin
        wait until unit_done and clock_done;
        report "PDM_RAW_SOURCE_ALL_PASS";
        finish;
    end process;
    process
    begin
        wait for 60 ms;
        assert false report "Simulation watchdog expired" severity failure;
    end process;
end test;
