library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use std.env.ALL;

entity tb_acoustic_video_marker is
end entity;

architecture test of tb_acoustic_video_marker is
    constant C_PERIOD : time := 10 ns;
    signal clk : std_logic := '0';
    signal resetn : std_logic := '0';
    signal cfg_red, cfg_cyan : std_logic_vector(31 downto 0) := (others => '0');
    signal sdata, mdata : std_logic_vector(23 downto 0) := x"123456";
    signal skeep, sstrb, mkeep, mstrb : std_logic_vector(2 downto 0) := "111";
    signal suser, muser : std_logic_vector(0 downto 0) := "0";
    signal slast, svalid, sready, mlast, mvalid : std_logic := '0';
    signal mready : std_logic := '1';
    signal observed_count : natural range 0 to 8 := 0;
begin
    clk <= not clk after C_PERIOD/2;

    dut : entity work.acoustic_video_marker
        port map (
            aclk => clk, aresetn => resetn,
            marker_cfg_i => cfg_red, marker_cfg2_i => cfg_cyan,
            s_axis_tdata => sdata, s_axis_tkeep => skeep, s_axis_tstrb => sstrb,
            s_axis_tuser => suser, s_axis_tlast => slast,
            s_axis_tvalid => svalid, s_axis_tready => sready,
            m_axis_tdata => mdata, m_axis_tkeep => mkeep, m_axis_tstrb => mstrb,
            m_axis_tuser => muser, m_axis_tlast => mlast,
            m_axis_tvalid => mvalid, m_axis_tready => mready);

    observe : process(clk)
    begin
        if rising_edge(clk) and mvalid = '1' and mready = '1' then
            if observed_count = 0 then
                assert mdata = x"FF1800" report "PDoA center should be bright red" severity failure;
            elsif observed_count = 4 then
                assert mdata = x"00FFFF" report "TDoA center should be bright cyan" severity failure;
            end if;
            observed_count <= observed_count + 1;
        end if;
    end process;

    stimulus : process
    begin
        wait for 8*C_PERIOD;
        wait until falling_edge(clk);
        resetn <= '1';
        cfg_red <= x"80400000";  -- enable, radius 4, center (0,0)
        cfg_cyan <= x"80400004"; -- enable, radius 4, center (4,0)
        wait for 6*C_PERIOD;
        for pixel_index in 0 to 4 loop
            wait until falling_edge(clk);
            svalid <= '1';
            if pixel_index = 0 then suser <= "1"; else suser <= "0"; end if;
            if pixel_index = 4 then slast <= '1'; else slast <= '0'; end if;
        end loop;
        wait until falling_edge(clk);
        svalid <= '0'; suser <= "0"; slast <= '0';
        -- The registered overlay pipeline has seven elastic stages.
        wait for 12*C_PERIOD;
        assert observed_count = 5 report "Expected five HDMI pixels through overlay" severity failure;
        report "PASS: two independently positioned radial markers have distinct center colors" severity note;
        stop;
        wait;
    end process;
end architecture;
