library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;
use std.env.all;
use work.acoustic_pcm_filter_pkg.all;

entity tb_pdm_pcm_filter is end;
architecture test of tb_pdm_pcm_filter is
    signal clk : std_logic := '0';
    signal resetn, ce : std_logic := '0';
    signal pdm : std_logic_vector(3 downto 0) := (others => '0');
    signal strobe, valid, ready, overrun : std_logic;
    signal data : std_logic_vector(127 downto 0);
    signal clips : std_logic_vector(3 downto 0);
    signal case_id : integer := 0;
    signal checking : boolean := true;
begin
    -- Nominal 24 MHz; the functional assertions use clock counts.
    clk <= not clk after 20.833333 ns;
    dut : entity work.acoustic_pdm_pcm_filter port map (
        clk, resetn, ce, pdm, strobe, valid, ready, data, clips, overrun);

    monitor : process
        file trace : text open write_mode is "pcm-trace.csv";
        variable row : line;
        variable sample_count, cycle, due, frame_index : integer := 0;
        variable sample_now, reset_now : std_logic;
    begin
        write(row, string'("case_id,index,valid,ready,clips,mic0,mic1,mic2,mic3")); writeline(trace, row);
        loop
            wait until rising_edge(clk);
            sample_now := ce; reset_now := resetn;
            if reset_now = '0' then
                sample_count := 0; cycle := 0; due := -1; frame_index := 0;
            else
                cycle := cycle + 1;
                if sample_now = '1' then
                    sample_count := sample_count + 1;
                    if sample_count mod 50 = 0 then due := cycle + 244; end if;
                end if;
            end if;
            wait for 1 ns;
            if checking and reset_now = '1' then
                assert overrun = '0' report "unexpected MAC overrun" severity failure;
                if cycle = due then
                    assert strobe = '1' report "missing output at MAC latency 244" severity failure;
                else
                    assert strobe = '0' report "unexpected output phase" severity failure;
                end if;
                if strobe = '1' then
                    write(row, case_id); write(row, string'(",")); write(row, frame_index);
                    write(row, string'(","));
                    if valid = '1' then write(row, 1); else write(row, 0); end if;
                    write(row, string'(","));
                    if ready = '1' then write(row, 1); else write(row, 0); end if;
                    write(row, string'(",")); write(row, to_integer(unsigned(clips)));
                    for c in 0 to 3 loop
                        write(row, string'(",")); write(row, to_integer(signed(data(c*32+31 downto c*32))));
                    end loop;
                    writeline(trace, row);
                    frame_index := frame_index + 1;
                end if;
                if strobe = '0' then
                    assert valid = '0' report "valid must be a one-clock pulse" severity failure;
                end if;
            end if;
        end loop;
    end process;

    stimulus : process
        file vectors : text open read_mode is "vectors/inputs.txt";
        file rounding : text open read_mode is "vectors/rounding.txt";
        variable row : line;
        variable cid, gap, mask, previous_case : integer := 0;
        variable acc, rounded, saturated, clip : integer;
        procedure ticks(n : natural) is
        begin
            for i in 1 to n loop wait until falling_edge(clk); end loop;
        end;
        procedure reset_filter is
        begin
            resetn <= '0'; ce <= '0'; ticks(3);
            resetn <= '1'; ticks(2);
        end;
    begin
        while not endfile(rounding) loop
            readline(rounding, row); read(row, acc); read(row, rounded); read(row, saturated); read(row, clip);
            assert rounded_pcm(to_signed(acc,32)) = to_signed(rounded,32)
                report "rounding mismatch" severity failure;
            assert saturated_pcm(to_signed(acc,32)) = to_signed(saturated,32)
                report "saturation mismatch" severity failure;
            assert clipped_pcm(to_signed(acc,32)) = std_logic(to_unsigned(clip,1)(0))
                report "clip flag mismatch" severity failure;
        end loop;
        while not endfile(vectors) loop
            readline(vectors, row); read(row, cid); read(row, gap); read(row, mask);
            if cid /= previous_case then
                ce <= '0'; ticks(300);
                case_id <= cid; reset_filter;
                previous_case := cid;
            end if;
            pdm <= std_logic_vector(to_unsigned(mask,4)); ce <= '1';
            ticks(1); ce <= '0'; ticks(gap-1);
        end loop;
        ce <= '0'; ticks(300);
        -- Reset in the middle of a MAC: no stale result may escape.
        checking <= false; reset_filter;
        ce <= '1'; pdm <= "1111";
        for i in 1 to 50 loop ticks(1); ce <= '0'; ticks(9); ce <= '1'; end loop;
        ce <= '0'; ticks(20); reset_filter;
        for i in 1 to 300 loop
            ticks(1); wait for 1 ns;
            assert strobe = '0' and valid = '0' and ready = '0'
                report "stale output after mid-MAC reset" severity failure;
        end loop;
        -- Invalid faster-than-budget CE must fail closed and latch overrun.
        reset_filter; ce <= '1'; ticks(400); ce <= '0'; ticks(300);
        assert overrun = '1' and ready = '0' and valid = '0'
            report "overrun did not fail closed" severity failure;
        reset_filter; wait for 1 ns;
        assert overrun = '0' and ready = '0' report "reset did not recover overrun" severity failure;
        report "PDM_PCM_FILTER_ALL_PASS" severity note;
        finish;
        wait;
    end process;
end architecture;
