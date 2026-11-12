-- Four synchronous PDM channels, CIC3/R5 and FIR61/R10, at clk_24m_i.
-- sample_ce_i normally occurs once per ten clocks. No downstream backpressure.
-- Reset when the PDM clock stops/restarts; block START must not reset the filter.
-- Each strobe carries four sign-extended signed-24 samples in 32-bit slots,
-- mic0 in bits 31:0. valid suppresses the first six results and any overrun.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.acoustic_pcm_filter_pkg.all;

entity acoustic_pdm_pcm_filter is
    port (
        clk_24m_i, resetn_24m_i : in std_logic;
        sample_ce_i : in std_logic;
        pdm_data_i : in std_logic_vector(3 downto 0);
        frame_strobe_o, frame_valid_o, filter_ready_o : out std_logic;
        frame_data_o : out std_logic_vector(127 downto 0);
        frame_clip_o : out std_logic_vector(3 downto 0);
        overrun_o : out std_logic
    );
end entity;

architecture rtl of acoustic_pdm_pcm_filter is
    type stages_t is array (0 to 2) of signed(31 downto 0);
    type channels_t is array (0 to 3) of stages_t;
    type ring_t is array (0 to 127) of signed(7 downto 0);
    type histories_t is array (0 to 3) of ring_t;
    -- History is not reset: the captured count masks all unwritten samples.
    -- A 128-slot ring preserves a 61-sample snapshot during the 244-cycle MAC
    -- while up to five further CIC samples arrive at the nominal input rate.
    signal history : histories_t;
    signal integrators, comb_delays : channels_t := (others => (others => (others => '0')));
    signal pdm_phase : natural range 0 to 4 := 0;
    signal fir_phase : natural range 0 to 9 := 0;
    signal write_index, snapshot_head : natural range 0 to 127 := 0;
    signal history_count, snapshot_count : natural range 0 to 61 := 0;
    signal mac_channel : natural range 0 to 3 := 0;
    signal mac_tap : natural range 0 to 60 := 0;
    signal accumulator : signed(31 downto 0) := (others => '0');
    signal mac_busy, scheduled_valid, overrun : std_logic := '0';
    signal settle_count : natural range 0 to 6 := 0;
    signal pending_data : std_logic_vector(127 downto 0) := (others => '0');
    signal pending_clips : std_logic_vector(3 downto 0) := (others => '0');
    signal frame_data : std_logic_vector(127 downto 0) := (others => '0');
    signal frame_clips : std_logic_vector(3 downto 0) := (others => '0');
begin
    frame_data_o <= frame_data;
    frame_clip_o <= frame_clips;
    overrun_o <= overrun;
    filter_ready_o <= '1' when settle_count = 6 and overrun = '0' else '0';
    process(clk_24m_i, resetn_24m_i)
        variable ints : stages_t;
        variable comb_value, comb_input : signed(31 downto 0);
        variable count_now : natural range 0 to 61;
        variable address : natural range 0 to 127;
        variable sample_value : signed(7 downto 0);
        variable product : signed(25 downto 0);
        variable total : signed(31 downto 0);
        variable vector_now : std_logic_vector(127 downto 0);
        variable clips_now : std_logic_vector(3 downto 0);
    begin
        if resetn_24m_i = '0' then
            integrators <= (others => (others => (others => '0')));
            comb_delays <= (others => (others => (others => '0')));
            pdm_phase <= 0; fir_phase <= 0; write_index <= 0;
            snapshot_head <= 0; history_count <= 0; snapshot_count <= 0;
            mac_channel <= 0; mac_tap <= 0; accumulator <= (others => '0');
            mac_busy <= '0'; scheduled_valid <= '0'; overrun <= '0';
            settle_count <= 0; pending_data <= (others => '0');
            pending_clips <= (others => '0'); frame_data <= (others => '0');
            frame_clips <= (others => '0'); frame_strobe_o <= '0'; frame_valid_o <= '0';
        elsif rising_edge(clk_24m_i) then
            frame_strobe_o <= '0'; frame_valid_o <= '0';
            if mac_busy = '1' then
                address := (snapshot_head + 128 - mac_tap) mod 128;
                sample_value := (others => '0');
                if mac_tap < snapshot_count then
                    sample_value := history(mac_channel)(address);
                end if;
                product := sample_value * C_COEFFICIENTS(mac_tap);
                total := accumulator + resize(product, 32);
                if mac_tap = 60 then
                    vector_now := pending_data; clips_now := pending_clips;
                    vector_now(32*mac_channel+31 downto 32*mac_channel) := std_logic_vector(saturated_pcm(total));
                    clips_now(mac_channel) := clipped_pcm(total);
                    pending_data <= vector_now; pending_clips <= clips_now;
                    accumulator <= (others => '0'); mac_tap <= 0;
                    if mac_channel = 3 then
                        mac_busy <= '0'; mac_channel <= 0;
                        frame_data <= vector_now;
                        frame_strobe_o <= '1';
                        frame_valid_o <= scheduled_valid and not overrun;
                        frame_clips <= (others => '0');
                        if scheduled_valid = '1' and overrun = '0' then
                            frame_clips <= clips_now;
                        end if;
                        if settle_count < 6 then settle_count <= settle_count + 1; end if;
                    else mac_channel <= mac_channel + 1;
                    end if;
                else
                    accumulator <= total; mac_tap <= mac_tap + 1;
                end if;
            end if;
            if sample_ce_i = '1' then
                for channel in 0 to 3 loop
                    ints := integrators(channel);
                    if pdm_data_i(channel) = '1' then ints(0) := ints(0) + 1;
                    else ints(0) := ints(0) - 1;
                    end if;
                    ints(1) := ints(1) + ints(0);
                    ints(2) := ints(2) + ints(1);
                    integrators(channel) <= ints;
                    if pdm_phase = 4 then
                        comb_value := ints(2);
                        for stage in 0 to 2 loop
                            comb_input := comb_value;
                            comb_value := comb_value - comb_delays(channel)(stage);
                            comb_delays(channel)(stage) <= comb_input;
                        end loop;
                        history(channel)(write_index) <= resize(comb_value, 8);
                    end if;
                end loop;
                if pdm_phase = 4 then
                    pdm_phase <= 0;
                    count_now := history_count;
                    if count_now < 61 then count_now := count_now + 1; end if;
                    history_count <= count_now;
                    write_index <= (write_index + 1) mod 128;
                    if fir_phase = 9 then
                        fir_phase <= 0;
                        if mac_busy = '1' then
                            -- Invalid input cadence or scheduler fault. Fail closed
                            -- until reset; integration must abort the current block.
                            overrun <= '1'; frame_valid_o <= '0';
                        elsif overrun = '0' then
                            snapshot_head <= write_index; snapshot_count <= count_now;
                            mac_channel <= 0; mac_tap <= 0; accumulator <= (others => '0');
                            mac_busy <= '1'; scheduled_valid <= '0';
                            if settle_count = 6 then scheduled_valid <= '1'; end if;
                        end if;
                    else fir_phase <= fir_phase + 1;
                    end if;
                else pdm_phase <= pdm_phase + 1;
                end if;
            end if;
        end if;
    end process;
end architecture;
