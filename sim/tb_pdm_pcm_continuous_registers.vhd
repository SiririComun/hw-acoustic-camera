library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use STD.ENV.ALL;

entity tb_pdm_pcm_continuous_registers is end;

architecture test of tb_pdm_pcm_continuous_registers is
    signal clk, resetn : std_logic := '0';
    signal awaddr, araddr : std_logic_vector(6 downto 0) := (others => '0');
    signal awvalid, wvalid, bready, arvalid, rready : std_logic := '0';
    signal awready, wready, bvalid, arready, rvalid : std_logic;
    signal wdata, rdata : std_logic_vector(31 downto 0) := (others => '0');
    signal wstrb : std_logic_vector(3 downto 0) := "1111";
    signal bresp, rresp : std_logic_vector(1 downto 0);
    signal clock_ready, filter_ready, busy, done : std_logic := '0';
    signal error_flags : std_logic_vector(2 downto 0) := "000";
    signal clip_count, frames, words, overflows : std_logic_vector(31 downto 0) := (others => '0');
    signal total_frames, total_words : std_logic_vector(63 downto 0) := (others => '0');
    signal snapshot_valid, clock_enable, format_pcm, source_pattern, continuous : std_logic;
    signal n_frames : std_logic_vector(31 downto 0);
    signal start_cmd, abort_cmd, clear_cmd, stop_cmd, config_error : std_logic;
begin
    clk <= not clk after 5 ns;
    dut : entity work.acoustic_pdm_pcm_continuous_registers
        port map (
            aclk => clk, aresetn => resetn,
            s_axi_awaddr => awaddr, s_axi_awprot => "000", s_axi_awvalid => awvalid, s_axi_awready => awready,
            s_axi_wdata => wdata, s_axi_wstrb => wstrb, s_axi_wvalid => wvalid, s_axi_wready => wready,
            s_axi_bresp => bresp, s_axi_bvalid => bvalid, s_axi_bready => bready,
            s_axi_araddr => araddr, s_axi_arprot => "000", s_axi_arvalid => arvalid, s_axi_arready => arready,
            s_axi_rdata => rdata, s_axi_rresp => rresp, s_axi_rvalid => rvalid, s_axi_rready => rready,
            clock_ready_i => clock_ready, filter_ready_i => filter_ready, busy_i => busy, done_i => done,
            error_flags_i => error_flags, clip_count_i => clip_count, frames_produced_i => frames,
            words_sent_i => words, overflow_count_i => overflows,
            total_frames_i => total_frames, total_words_i => total_words, snapshot_valid_o => snapshot_valid,
            clock_enable_o => clock_enable, format_pcm_o => format_pcm, source_pattern_o => source_pattern,
            continuous_o => continuous, n_frames_o => n_frames,
            start_o => start_cmd, abort_o => abort_cmd, clear_o => clear_cmd,
            stop_o => stop_cmd, config_error_o => config_error);

    process
        procedure ticks(count : positive := 1) is
        begin
            for i in 1 to count loop wait until rising_edge(clk); end loop;
            wait for 1 ns;
        end procedure;
        procedure wr(address : natural; value : std_logic_vector(31 downto 0);
                     response : std_logic_vector(1 downto 0) := "00") is
        begin
            awaddr <= std_logic_vector(to_unsigned(address, 7)); awvalid <= '1';
            loop wait until rising_edge(clk); exit when awready = '1'; end loop;
            awvalid <= '0';
            wdata <= value; wvalid <= '1'; wstrb <= "1111";
            loop wait until rising_edge(clk); exit when wready = '1'; end loop;
            wvalid <= '0'; bready <= '0';
            loop wait until rising_edge(clk); exit when bvalid = '1'; end loop;
            assert bresp = response report "Write response mismatch" severity failure;
            if address = 16#24# then
                case value is
                    when x"00000001" => assert start_cmd = '1' and snapshot_valid = '0' severity failure;
                    when x"00000004" => assert clear_cmd = '1' and snapshot_valid = '0' severity failure;
                    when x"00000008" => assert stop_cmd = '1' severity failure;
                    when others => null;
                end case;
            elsif address = 16#64# and busy = '1' then
                assert config_error = '1' report "Live mode write did not set CONFIG_ERROR" severity failure;
            end if;
            ticks(1); bready <= '1'; ticks; bready <= '0';
        end;
        procedure rd(address : natural; expected : std_logic_vector(31 downto 0);
                     response : std_logic_vector(1 downto 0) := "00") is
            variable value : std_logic_vector(31 downto 0);
        begin
            araddr <= std_logic_vector(to_unsigned(address, 7)); arvalid <= '1';
            loop wait until rising_edge(clk); exit when arready = '1'; end loop;
            arvalid <= '0'; rready <= '0';
            loop wait until rising_edge(clk); exit when rvalid = '1'; end loop;
            value := rdata;
            assert rresp = response report "Read response mismatch" severity failure;
            assert value = expected report "Read value mismatch addr=" & integer'image(address) & " got=" & to_hstring(value) severity failure;
            ticks(1); rready <= '1'; ticks; rready <= '0';
        end;
        procedure read_build_word(index : natural; expected : std_logic_vector(127 downto 0)) is
            variable value : std_logic_vector(31 downto 0);
        begin
            araddr <= std_logic_vector(to_unsigned(16#10# + index*4, 7)); arvalid <= '1';
            loop wait until rising_edge(clk); exit when arready = '1'; end loop;
            arvalid <= '0'; rready <= '0';
            loop wait until rising_edge(clk); exit when rvalid = '1'; end loop;
            value := rdata;
            assert value = expected(index*32+31 downto index*32) report "BUILD_ID word mismatch" severity failure;
            rready <= '1'; ticks; rready <= '0';
        end;
        constant build_id : std_logic_vector(127 downto 0) := x"7A2C7F017A2C4E7D8F70070100000001";
    begin
        ticks(4); resetn <= '1'; ticks(2);
        rd(0, x"4143414D"); rd(4, x"00010001"); rd(8, x"0000001F"); rd(12, x"00000004");
        for i in 0 to 3 loop read_build_word(i, build_id); end loop;
        rd(16#64#, x"00000000"); rd(16#7C#, x"00000000");
        wr(16#64#, x"00000001");
        assert continuous = '1' report "Continuous mode write failed" severity failure;
        rd(16#64#, x"00000001");
        busy <= '1'; wr(16#64#, x"00000000");
        assert continuous = '1' report "Live mode change was accepted" severity failure;
        busy <= '0'; ticks(2);

        wr(16#38#, x"00001000");
        assert unsigned(n_frames) = 4096 severity failure;
        wr(16#24#, x"00000008");
        wr(16#24#, x"00000001");
        wr(16#24#, x"00000004");

        total_frames <= x"1122334455667788";
        total_words <= x"99AABBCCDDEEFF00";
        wr(16#78#, x"00000001");
        assert snapshot_valid = '1' report "Snapshot command did not set valid" severity failure;
        rd(16#68#, x"55667788"); rd(16#6C#, x"11223344");
        rd(16#70#, x"DDEEFF00"); rd(16#74#, x"99AABBCC");
        rd(16#7C#, x"00000001");
        wr(16#78#, x"00000000"); rd(16#7C#, x"00000000");
        rd(16#78#, x"00000000", "10");
        wr(16#68#, x"00000000", "10");
        report "PDM_PCM_CONTINUOUS_REGISTERS_ALL_PASS" severity note;
        finish;
    end process;
    process begin wait for 1 ms; assert false report "Register test deadline" severity failure; end process;
end test;
