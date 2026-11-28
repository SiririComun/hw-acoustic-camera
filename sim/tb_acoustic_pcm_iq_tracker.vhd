library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use IEEE.MATH_REAL.ALL;
use std.env.ALL;

entity tb_acoustic_pcm_iq_tracker is
end entity;

architecture test of tb_acoustic_pcm_iq_tracker is
    constant C_PERIOD : time := 10 ns;
    constant C_FS : real := 48000.0;
    constant C_FREQ : real := 2500.0;
    constant C_FRAMES : natural := 4096;
    signal clk : std_logic := '0';
    signal resetn : std_logic := '0';
    signal awaddr : std_logic_vector(7 downto 0) := (others => '0');
    signal awprot : std_logic_vector(2 downto 0) := (others => '0');
    signal awvalid : std_logic := '0';
    signal awready : std_logic;
    signal wdata : std_logic_vector(31 downto 0) := (others => '0');
    signal wstrb : std_logic_vector(3 downto 0) := (others => '1');
    signal wvalid : std_logic := '0';
    signal wready : std_logic;
    signal bresp : std_logic_vector(1 downto 0);
    signal bvalid : std_logic;
    signal bready : std_logic := '0';
    signal araddr : std_logic_vector(7 downto 0) := (others => '0');
    signal arprot : std_logic_vector(2 downto 0) := (others => '0');
    signal arvalid : std_logic := '0';
    signal arready : std_logic;
    signal rdata : std_logic_vector(31 downto 0);
    signal rresp : std_logic_vector(1 downto 0);
    signal rvalid : std_logic;
    signal rready : std_logic := '0';
    signal tdata : std_logic_vector(31 downto 0) := (others => '0');
    signal tkeep : std_logic_vector(3 downto 0) := "1111";
    signal tlast : std_logic := '0';
    signal tvalid : std_logic := '0';
    signal tready : std_logic;
    signal pulse_start : std_logic := '0';
    type int_array_t is array (0 to 7) of integer;
    type dc_offset_array_t is array (0 to 3) of integer;
    constant C_DC_OFFSETS : dc_offset_array_t := (1200000, -900000, 1800000, -1500000);
    signal observed : int_array_t := (others => 0);

    procedure axi_write(signal c : in std_logic; signal addr : out std_logic_vector(7 downto 0);
                        signal av : out std_logic; signal ar : in std_logic;
                        signal wd : out std_logic_vector(31 downto 0);
                        signal wv : out std_logic; signal wr : in std_logic;
                        signal bv : in std_logic; signal br : out std_logic;
                        constant a : in natural; constant d : in std_logic_vector(31 downto 0)) is
    begin
        wait until falling_edge(c);
        addr <= std_logic_vector(to_unsigned(a, addr'length));
        wd <= d; av <= '1'; wv <= '1'; br <= '0';
        loop
            wait until rising_edge(c);
            exit when ar = '1' and wr = '1';
        end loop;
        wait until falling_edge(c);
        av <= '0'; wv <= '0';
        loop
            wait until rising_edge(c);
            wait for 1 ns;
            exit when bv = '1';
        end loop;
        br <= '1';
        wait until rising_edge(c);
        wait until falling_edge(c);
        br <= '0';
    end procedure;

    procedure axi_read(signal c : in std_logic; signal addr : out std_logic_vector(7 downto 0);
                       signal av : out std_logic; signal ar : in std_logic;
                       signal rd : in std_logic_vector(31 downto 0);
                       signal rv : in std_logic; signal rr : out std_logic;
                       constant a : in natural; variable d : out std_logic_vector(31 downto 0)) is
    begin
        wait until falling_edge(c);
        addr <= std_logic_vector(to_unsigned(a, addr'length)); av <= '1'; rr <= '0';
        loop
            wait until rising_edge(c);
            exit when ar = '1';
        end loop;
        wait until falling_edge(c);
        av <= '0';
        loop
            wait until rising_edge(c);
            wait for 1 ns;
            exit when rv = '1';
        end loop;
        d := rd; rr <= '1';
        wait until rising_edge(c);
        wait until falling_edge(c);
        rr <= '0';
    end procedure;
begin
    clk <= not clk after C_PERIOD/2;

    dut : entity work.acoustic_pcm_iq_tracker
        port map (
            aclk => clk, aresetn => resetn,
            s_axi_awaddr => awaddr, s_axi_awprot => awprot,
            s_axi_awvalid => awvalid, s_axi_awready => awready,
            s_axi_wdata => wdata, s_axi_wstrb => wstrb,
            s_axi_wvalid => wvalid, s_axi_wready => wready,
            s_axi_bresp => bresp, s_axi_bvalid => bvalid, s_axi_bready => bready,
            s_axi_araddr => araddr, s_axi_arprot => arprot,
            s_axi_arvalid => arvalid, s_axi_arready => arready,
            s_axi_rdata => rdata, s_axi_rresp => rresp,
            s_axi_rvalid => rvalid, s_axi_rready => rready,
            s_axis_tdata => tdata, s_axis_tkeep => tkeep,
            s_axis_tlast => tlast, s_axis_tvalid => tvalid,
            s_axis_tready => tready, pulse_start_i => pulse_start);

    stimulus : process
        variable increment : natural;
        variable address : natural;
        variable sample_value : integer;
        variable sample_phase, channel_phase : real;
        variable data_word : std_logic_vector(31 downto 0);
        variable raw_result : std_logic_vector(31 downto 0);
        variable status_word : std_logic_vector(31 downto 0);
        variable pdoa_status, pdoa_pixel, tdoa_status, tdoa_pixel : std_logic_vector(31 downto 0);
        variable tdoa_dx, tdoa_dy : std_logic_vector(31 downto 0);
        variable tdoa_dir_x, tdoa_dir_y : std_logic_vector(31 downto 0);
        variable pcm_frame_count : std_logic_vector(31 downto 0);
        variable arrival_0, arrival_1, arrival_2, arrival_3 : std_logic_vector(31 downto 0);
        variable i_values, q_values : int_array_t;
        variable cross : real;
        type real_array_t is array (0 to 3) of real;
        constant phases : real_array_t := (0.0, 0.3, -0.4, 0.7);
        type natural_array_t is array (0 to 7) of natural;
        constant addrs : natural_array_t := (16#10#,16#14#,16#18#,16#1C#,
                                             16#20#,16#24#,16#28#,16#2C#);
    begin
        wait for 8*C_PERIOD;
        wait until falling_edge(clk); resetn <= '1';
        increment := integer(C_FREQ/C_FS * 4294967296.0);
        axi_write(clk, awaddr, awvalid, awready, wdata, wvalid, wready,
                  bvalid, bready, 16#04#, std_logic_vector(to_unsigned(increment,32)));
        axi_write(clk, awaddr, awvalid, awready, wdata, wvalid, wready,
                  bvalid, bready, 16#0C#, std_logic_vector(to_unsigned(C_FRAMES,32)));
        axi_write(clk, awaddr, awvalid, awready, wdata, wvalid, wready,
                  bvalid, bready, 16#00#, x"0000000F");

        wait until falling_edge(clk); tvalid <= '1';
        for n in 0 to C_FRAMES-1 loop
            sample_phase := 2.0 * MATH_PI * C_FREQ * real(n) / C_FS;
            for channel in 0 to 3 loop
                channel_phase := sample_phase + phases(channel);
                sample_value := integer(2000000.0 * cos(channel_phase)) + C_DC_OFFSETS(channel);
                tdata <= std_logic_vector(to_signed(sample_value,32));
                if n = C_FRAMES-1 and channel = 3 then tlast <= '1'; else tlast <= '0'; end if;
                wait until rising_edge(clk);
                assert tready = '1' report "I/Q tracker stalled its stream" severity failure;
                wait until falling_edge(clk);
            end loop;
        end loop;
        tvalid <= '0'; tlast <= '0';
        -- The PL datapath now registers reference lookup, product, accumulation
        -- and result scaling; let the final TLAST sample drain before AXI reads.
        wait for 12*C_PERIOD;

        axi_read(clk, araddr, arvalid, arready, rdata, rvalid, rready, 16#08#, status_word);
        assert status_word(1) = '1' report "I/Q result_valid was not set" severity failure;
        assert unsigned(status_word(31 downto 8)) = 32 report "Expected 32 I/Q windows in one 4096-frame DMA descriptor" severity failure;
        assert status_word(2) = '0' report "AXI stream channel sequence error" severity failure;
        axi_read(clk, araddr, arvalid, arready, rdata, rvalid, rready, 16#30#, pcm_frame_count);
        assert unsigned(pcm_frame_count) = C_FRAMES
            report "PCM frame counter must advance once per four-word sample frame, not once per TLAST" severity failure;
        for index in 0 to 7 loop
            axi_read(clk, araddr, arvalid, arready, rdata, rvalid, rready,
                     addrs(index), raw_result);
            observed(index) <= to_integer(signed(raw_result));
        end loop;
        wait for C_PERIOD;
        for ch in 0 to 3 loop
            i_values(ch) := observed(2*ch);
            q_values(ch) := observed(2*ch+1);
            assert abs(i_values(ch)) + abs(q_values(ch)) > 100000
                report "Channel I/Q magnitude too small" severity failure;
        end loop;
        wait for 500*C_PERIOD;
        axi_read(clk, araddr, arvalid, arready, rdata, rvalid, rready, 16#8C#, pdoa_status);
        axi_read(clk, araddr, arvalid, arready, rdata, rvalid, rready, 16#98#, pdoa_pixel);
        assert pdoa_status(0) = '1' report "PDoA direction was not marked valid" severity failure;
        assert unsigned(pdoa_pixel(9 downto 0)) > 200 and
               unsigned(pdoa_pixel(9 downto 0)) < 270
            report "PDoA x projection did not respond to phase gradient" severity failure;
        assert unsigned(pdoa_pixel(19 downto 10)) > 220 and
               unsigned(pdoa_pixel(19 downto 10)) < 260
            report "PDoA y projection did not remain near center" severity failure;

        for i in 0 to 2 loop
            for j in i+1 to 3 loop
                cross := real(i_values(i))*real(q_values(j)) - real(q_values(i))*real(i_values(j));
                if phases(j) > phases(i) then
                    assert cross > 0.0 report "Pair phase sign disagrees with the generated tone" severity failure;
                else
                    assert cross < 0.0 report "Pair phase sign disagrees with the generated tone" severity failure;
                end if;
            end loop;
        end loop;

        -- Hold four large DC offsets without a tone, then start the tone at
        -- the electrical pulse edge. Absolute PCM magnitude alone would
        -- falsely mark all four channels before this event.
        wait until falling_edge(clk); tvalid <= '1';
        for n in 0 to 2047 loop
            for channel in 0 to 3 loop
                sample_value := C_DC_OFFSETS(channel);
                tdata <= std_logic_vector(to_signed(sample_value,32));
                tlast <= '0';
                wait until rising_edge(clk);
                wait until falling_edge(clk);
            end loop;
        end loop;
        tvalid <= '0'; tlast <= '0';
        wait until falling_edge(clk); pulse_start <= '1';
        wait until falling_edge(clk); pulse_start <= '0'; tvalid <= '1';
        for n in 0 to 255 loop
            sample_phase := 2.0 * MATH_PI * C_FREQ * real(C_FRAMES+2048+n) / C_FS;
            for channel in 0 to 3 loop
                sample_value := integer(2000000.0 * cos(sample_phase)) + C_DC_OFFSETS(channel);
                tdata <= std_logic_vector(to_signed(sample_value,32));
                wait until rising_edge(clk);
                wait until falling_edge(clk);
            end loop;
        end loop;
        tvalid <= '0'; tlast <= '0';
        wait for 500*C_PERIOD;
        axi_read(clk, araddr, arvalid, arready, rdata, rvalid, rready, 16#9C#, tdoa_status);
        axi_read(clk, araddr, arvalid, arready, rdata, rvalid, rready, 16#BC#, tdoa_dx);
        axi_read(clk, araddr, arvalid, arready, rdata, rvalid, rready, 16#C0#, tdoa_dy);
        axi_read(clk, araddr, arvalid, arready, rdata, rvalid, rready, 16#A8#, tdoa_pixel);
        assert tdoa_status(0) = '1' report "DC-rejected equal onsets did not produce a TDoA event" severity failure;
        assert abs(to_integer(signed(tdoa_dx))) <= 1 and
               abs(to_integer(signed(tdoa_dy))) <= 1
            report "Equal onset times should remain within one PCM frame of center" severity failure;
        assert abs(to_integer(unsigned(tdoa_pixel(9 downto 0))) - 320) <= 40 and
               abs(to_integer(unsigned(tdoa_pixel(19 downto 10))) - 240) <= 40
            report "Equal onset pixels should remain close to image center" severity failure;

        -- Repeat after silence, delaying the two left-side channels by six
        -- frames. The onset filter adds common latency; only the direction
        -- and a coarse frame bound are asserted.
        wait until falling_edge(clk); tvalid <= '1';
        for n in 0 to 2047 loop
            for channel in 0 to 3 loop
                sample_value := C_DC_OFFSETS(channel);
                tdata <= std_logic_vector(to_signed(sample_value,32));
                tlast <= '0';
                wait until rising_edge(clk);
                wait until falling_edge(clk);
            end loop;
        end loop;
        tvalid <= '0'; tlast <= '0';
        wait until falling_edge(clk); pulse_start <= '1';
        wait until falling_edge(clk); pulse_start <= '0'; tvalid <= '1';
        for n in 0 to 255 loop
            sample_phase := 2.0 * MATH_PI * C_FREQ * real(C_FRAMES+4352+n) / C_FS;
            for channel in 0 to 3 loop
                if n < 6 and (channel = 0 or channel = 3) then
                    sample_value := C_DC_OFFSETS(channel);
                else
                    sample_value := integer(2000000.0 * cos(sample_phase)) + C_DC_OFFSETS(channel);
                end if;
                tdata <= std_logic_vector(to_signed(sample_value,32));
                wait until rising_edge(clk);
                wait until falling_edge(clk);
            end loop;
        end loop;
        tvalid <= '0'; tlast <= '0';
        wait for 500*C_PERIOD;
        axi_read(clk, araddr, arvalid, arready, rdata, rvalid, rready, 16#9C#, tdoa_status);
        axi_read(clk, araddr, arvalid, arready, rdata, rvalid, rready, 16#AC#, arrival_0);
        axi_read(clk, araddr, arvalid, arready, rdata, rvalid, rready, 16#B0#, arrival_1);
        axi_read(clk, araddr, arvalid, arready, rdata, rvalid, rready, 16#B4#, arrival_2);
        axi_read(clk, araddr, arvalid, arready, rdata, rvalid, rready, 16#B8#, arrival_3);
        axi_read(clk, araddr, arvalid, arready, rdata, rvalid, rready, 16#BC#, tdoa_dx);
        axi_read(clk, araddr, arvalid, arready, rdata, rvalid, rready, 16#C0#, tdoa_dy);
        axi_read(clk, araddr, arvalid, arready, rdata, rvalid, rready, 16#A8#, tdoa_pixel);
        assert tdoa_status(0) = '1' report "Delayed onset did not produce a TDoA event" severity failure;
        assert to_integer(unsigned(arrival_0)) - to_integer(unsigned(arrival_1)) = 6 and
               to_integer(unsigned(arrival_3)) - to_integer(unsigned(arrival_2)) = 6
            report "The two delayed channels should retain their six-frame offset" severity failure;
        assert signed(tdoa_dx) = 6 and signed(tdoa_dy) = 0
            report "Symmetric delayed channels should produce +6 horizontal and zero vertical TDoA" severity failure;
        assert unsigned(tdoa_pixel(9 downto 0)) > 320 and
               unsigned(tdoa_pixel(9 downto 0)) < 640
            report "TDoA horizontal pixel did not follow the delayed left channels" severity failure;
        assert unsigned(tdoa_pixel(19 downto 10)) > 200 and
               unsigned(tdoa_pixel(19 downto 10)) < 280
            report "Symmetric TDoA should remain on the vertical centerline" severity failure;

        -- Exercise the signed low-32-bit TDoA scale product with nonzero high
        -- and low scale halves. For dx=2 and scale=-16384, the exact result is
        -- -32768 modulo 2^32; no high product bits are observable at this API.
        axi_write(clk, awaddr, awvalid, awready, wdata, wvalid, wready,
                  bvalid, bready, 16#74#, x"FFFFC000");
        wait until falling_edge(clk); tvalid <= '1';
        for n in 0 to 2047 loop
            for channel in 0 to 3 loop
                sample_value := C_DC_OFFSETS(channel);
                tdata <= std_logic_vector(to_signed(sample_value,32));
                tlast <= '0';
                wait until rising_edge(clk);
                wait until falling_edge(clk);
            end loop;
        end loop;
        tvalid <= '0'; tlast <= '0';
        wait until falling_edge(clk); pulse_start <= '1';
        wait until falling_edge(clk); pulse_start <= '0'; tvalid <= '1';
        for n in 0 to 255 loop
            sample_phase := 2.0 * MATH_PI * C_FREQ * real(C_FRAMES+6656+n) / C_FS;
            for channel in 0 to 3 loop
                if n < 6 and (channel = 0 or channel = 3) then
                    sample_value := C_DC_OFFSETS(channel);
                else
                    sample_value := integer(2000000.0 * cos(sample_phase)) + C_DC_OFFSETS(channel);
                end if;
                tdata <= std_logic_vector(to_signed(sample_value,32));
                wait until rising_edge(clk);
                wait until falling_edge(clk);
            end loop;
        end loop;
        tvalid <= '0'; tlast <= '0';
        wait for 20*C_PERIOD;
        axi_read(clk, araddr, arvalid, arready, rdata, rvalid, rready, 16#A0#, tdoa_dir_x);
        axi_read(clk, araddr, arvalid, arready, rdata, rvalid, rready, 16#A4#, tdoa_dir_y);
        axi_read(clk, araddr, arvalid, arready, rdata, rvalid, rready, 16#BC#, tdoa_dx);
        assert signed(tdoa_dir_x) = to_signed(
            -16384 * to_integer(signed(tdoa_dx)), 32)
            report "TDoA split signed scale product must preserve the low 32 bits" severity failure;
        assert signed(tdoa_dir_y) = 0 report "Zero vertical delta should remain zero after scaling" severity failure;
        report "PASS: descriptor-frame counting, DC-rejected PDoA, and pulse-synchronous TDoA verified" severity note;
        stop;
        wait;
    end process;
end architecture;
