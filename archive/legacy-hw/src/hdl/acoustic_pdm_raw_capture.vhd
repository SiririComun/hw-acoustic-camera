-- RAW block producer, asynchronous FIFO and AXI Stream output.
-- Command ports are synchronous pulses in clk_100m_i; this is not AXI-Lite.
-- Integration with the register bank and DMA belongs to step 3.4.
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
library XPM;
use XPM.VCOMPONENTS.ALL;

entity acoustic_pdm_raw_capture is
    generic (G_FIFO_DEPTH : positive := 8192);
    port (
        clk_24m_i, resetn_24m_i : in std_logic;
        clk_100m_i, resetn_100m_i : in std_logic;
        sample_ce_i : in std_logic;
        pdm_data_i : in std_logic_vector(3 downto 0);
        clock_ready_i : in std_logic;
        start_i, abort_i, clear_i, config_error_i : in std_logic;
        n_frames_i : in std_logic_vector(31 downto 0);
        source_pattern_i : in std_logic;
        -- Connect to the DMA primary stream reset in the following step.
        -- Local recovery preserves configuration outside this core and errors.
        stream_resetn_i : in std_logic;
        busy_o, done_o : out std_logic;
        error_flags_o : out std_logic_vector(2 downto 0);
        frames_produced_o, words_sent_o, overflow_count_o : out std_logic_vector(31 downto 0);
        m_axis_tdata : out std_logic_vector(31 downto 0);
        m_axis_tkeep : out std_logic_vector(3 downto 0);
        m_axis_tlast, m_axis_tvalid : out std_logic;
        m_axis_tready : in std_logic
    );
end acoustic_pdm_raw_capture;

architecture rtl of acoustic_pdm_raw_capture is
    type state_type is (IDLE, ACTIVE, RECOVERY, CLEAR_WAIT);
    signal state : state_type := RECOVERY;
    signal errors : std_logic_vector(2 downto 0) := "000";
    signal done, final_sent, producer_finished : std_logic := '0';
    signal frames_visible, words_sent : unsigned(31 downto 0) := (others => '0');
    signal overflow_visible : std_logic := '0';
    signal block_length : std_logic_vector(31 downto 0) := (others => '0');
    signal block_pattern, start_req, clear_req : std_logic := '0';
    signal recover_req : std_logic := '1';
    signal recover_dropping : std_logic := '0';
    signal stop_level : std_logic;

    signal start_pipe, clear_pipe, stop_pipe, recover_pipe : std_logic_vector(1 downto 0) := "00";
    signal start_seen, clear_seen, start_pulse : std_logic := '0';
    signal recover_ack : std_logic := '0';
    signal recover_ack_pipe, read_busy_pipe : std_logic_vector(1 downto 0) := "00";
    signal recover_seen : std_logic := '0';
    signal reset_count : natural range 0 to 8 := 8;
    signal fifo_reset : std_logic := '1';
    signal active_24, overflow_24, pending_last, admit : std_logic := '0';
    signal admitted, produced, length_24 : unsigned(31 downto 0) := (others => '0');
    signal source_resetn, source_valid : std_logic;
    signal source_word : std_logic_vector(31 downto 0);

    signal fifo_in, fifo_out : std_logic_vector(32 downto 0);
    signal fifo_full, fifo_empty, write_busy, read_busy, fifo_write, fifo_read : std_logic;
    signal axis_valid : std_logic;

    -- Held coherent snapshot: frames[31:0], overflow, stopped, start epoch,
    -- clear epoch. Source holds this bus until the returned toggle is observed.
    signal snapshot_now, snapshot_data : std_logic_vector(35 downto 0) := (others => '0');
    signal snapshot_last : std_logic_vector(35 downto 0) := (others => '1');
    signal snapshot_req, snapshot_ack : std_logic := '0';
    signal snapshot_req_pipe, snapshot_ack_pipe : std_logic_vector(1 downto 0) := "00";
    attribute ASYNC_REG : string;
    attribute ASYNC_REG of start_pipe, clear_pipe, stop_pipe, recover_pipe,
        recover_ack_pipe, read_busy_pipe, snapshot_req_pipe, snapshot_ack_pipe : signal is "TRUE";
begin
    busy_o <= '0' when state = IDLE else '1';
    done_o <= done;
    error_flags_o <= errors;
    frames_produced_o <= std_logic_vector(frames_visible);
    words_sent_o <= std_logic_vector(words_sent);
    overflow_count_o <= x"00000001" when overflow_visible = '1' else x"00000000";
    stop_level <= '1' when errors /= "000" or state = RECOVERY else '0';

    start_pulse <= start_pipe(1) xor start_seen;
    source_resetn <= resetn_24m_i and not recover_pipe(1);
    admit <= '1' when active_24 = '1' and stop_pipe(1) = '0'
        and recover_pipe(1) = '0' and write_busy = '0' and fifo_reset = '0'
        and fifo_full = '0' and admitted < length_24 else '0';
    source_i : entity work.acoustic_pdm_raw_source
        port map (clk_24m_i, source_resetn, sample_ce_i, start_pulse, admit,
                  block_pattern, pdm_data_i, source_valid, source_word);
    fifo_in <= pending_last & source_word;
    fifo_write <= source_valid and not write_busy and not fifo_reset;
    axis_valid <= '1' when fifo_empty = '0' and read_busy = '0'
        and resetn_100m_i = '1' and stream_resetn_i = '1' and state /= RECOVERY else '0';
    m_axis_tvalid <= axis_valid;
    m_axis_tdata <= fifo_out(31 downto 0);
    m_axis_tlast <= fifo_out(32);
    m_axis_tkeep <= "1111";
    fifo_read <= axis_valid and m_axis_tready;

    fifo_i : xpm_fifo_async
        generic map (
            FIFO_MEMORY_TYPE => "block", ECC_MODE => "no_ecc",
            RELATED_CLOCKS => 0, SIM_ASSERT_CHK => 1,
            FIFO_WRITE_DEPTH => G_FIFO_DEPTH, WRITE_DATA_WIDTH => 33, READ_DATA_WIDTH => 33,
            READ_MODE => "fwft", FIFO_READ_LATENCY => 0,
            CDC_SYNC_STAGES => 2, USE_ADV_FEATURES => "0000")
        port map (
            rst => fifo_reset, wr_clk => clk_24m_i, rd_clk => clk_100m_i,
            din => fifo_in, wr_en => fifo_write, rd_en => fifo_read,
            full => fifo_full, empty => fifo_empty, dout => fifo_out,
            wr_rst_busy => write_busy, rd_rst_busy => read_busy,
            sleep => '0', injectsbiterr => '0', injectdbiterr => '0',
            almost_empty => open, almost_full => open, data_valid => open,
            dbiterr => open, sbiterr => open, overflow => open, underflow => open,
            prog_empty => open, prog_full => open, rd_data_count => open,
            wr_data_count => open, wr_ack => open);

    process (clk_24m_i, resetn_24m_i)
    begin
        if resetn_24m_i = '0' then
            start_pipe <= "00"; clear_pipe <= "00"; stop_pipe <= "11";
            recover_pipe <= "00"; snapshot_ack_pipe <= "00"; read_busy_pipe <= "11";
        elsif rising_edge(clk_24m_i) then
            start_pipe <= start_pipe(0) & start_req;
            clear_pipe <= clear_pipe(0) & clear_req;
            stop_pipe <= stop_pipe(0) & stop_level;
            recover_pipe <= recover_pipe(0) & recover_req;
            snapshot_ack_pipe <= snapshot_ack_pipe(0) & snapshot_ack;
            read_busy_pipe <= read_busy_pipe(0) & read_busy;
        end if;
    end process;

    -- Reset is held across eight stable write-clock cycles, then released so
    -- both XPM reset-busy outputs can fall before acknowledging recovery.
    process (clk_24m_i)
    begin
        if rising_edge(clk_24m_i) then
            if resetn_24m_i = '0' then
                reset_count <= 8; fifo_reset <= '1'; recover_seen <= '0'; recover_ack <= '0';
            else
                if recover_pipe(1) = '0' then recover_seen <= '0'; recover_ack <= '0'; end if;
                if recover_pipe(1) = '1' and recover_seen = '0' then
                    recover_seen <= '1'; reset_count <= 8; fifo_reset <= '1';
                elsif reset_count /= 0 then
                    reset_count <= reset_count - 1; fifo_reset <= '1';
                else
                    fifo_reset <= '0';
                    if recover_pipe(1) = '1' and write_busy = '0' and read_busy_pipe(1) = '0' then
                        recover_ack <= '1';
                    end if;
                end if;
            end if;
        end if;
    end process;

    process (clk_24m_i, resetn_24m_i)
    begin
        if resetn_24m_i = '0' then
            start_seen <= '0'; clear_seen <= '0'; active_24 <= '0'; overflow_24 <= '0';
            admitted <= (others => '0'); produced <= (others => '0');
            length_24 <= (others => '0'); pending_last <= '0';
        elsif rising_edge(clk_24m_i) then
            if fifo_write = '1' then
                assert fifo_full = '0' report "Reserved RAW FIFO slot unavailable" severity failure;
                produced <= produced + 1;
            end if;
            if stop_pipe(1) = '1' or recover_pipe(1) = '1' then active_24 <= '0'; end if;
            if start_pulse = '1' then
                -- Configuration is held in the 100 MHz mailbox for this entire
                -- block. A stop may overtake START; acknowledge its epoch anyway.
                start_seen <= start_pipe(1);
                length_24 <= unsigned(block_length);
                admitted <= (others => '0'); produced <= (others => '0');
                overflow_24 <= '0'; pending_last <= '0';
                active_24 <= not (stop_pipe(1) or recover_pipe(1));
            elsif clear_pipe(1) /= clear_seen then
                clear_seen <= clear_pipe(1); active_24 <= '0';
                admitted <= (others => '0'); produced <= (others => '0');
                overflow_24 <= '0'; pending_last <= '0';
            elsif active_24 = '1' and stop_pipe(1) = '0' and recover_pipe(1) = '0'
                and sample_ce_i = '1' then
                if fifo_full = '1' then
                    overflow_24 <= '1'; active_24 <= '0';
                elsif admit = '1' then
                    admitted <= admitted + 1;
                    pending_last <= '0';
                    if admitted + 1 = length_24 then
                        pending_last <= '1'; active_24 <= '0';
                    end if;
                end if;
            end if;
        end if;
    end process;

    snapshot_now <= clear_seen & start_seen & (not active_24 and not source_valid)
        & overflow_24 & std_logic_vector(produced);
    process (clk_24m_i, resetn_24m_i)
    begin
        if resetn_24m_i = '0' then
            snapshot_data <= (others => '0'); snapshot_last <= (others => '1'); snapshot_req <= '0';
        elsif rising_edge(clk_24m_i) then
            if snapshot_ack_pipe(1) = snapshot_req and snapshot_now /= snapshot_last then
                snapshot_data <= snapshot_now; snapshot_last <= snapshot_now;
                snapshot_req <= not snapshot_req;
            end if;
        end if;
    end process;

    process (clk_100m_i, resetn_100m_i)
        variable next_errors : std_logic_vector(2 downto 0);
        variable conflicting : boolean;
    begin
        if resetn_100m_i = '0' then
            state <= RECOVERY; errors <= "000"; done <= '0';
            final_sent <= '0'; producer_finished <= '0';
            frames_visible <= (others => '0'); words_sent <= (others => '0'); overflow_visible <= '0';
            block_length <= (others => '0'); block_pattern <= '0'; start_req <= '0'; clear_req <= '0';
            recover_req <= '1'; recover_dropping <= '0'; recover_ack_pipe <= "00";
            snapshot_req_pipe <= "00"; snapshot_ack <= '0';
        elsif rising_edge(clk_100m_i) then
            recover_ack_pipe <= recover_ack_pipe(0) & recover_ack;
            snapshot_req_pipe <= snapshot_req_pipe(0) & snapshot_req;
            next_errors := errors;
            if fifo_read = '1' then
                words_sent <= words_sent + 1;
                if fifo_out(32) = '1' then final_sent <= '1'; end if;
            end if;

            if snapshot_req_pipe(1) /= snapshot_ack then
                snapshot_ack <= snapshot_req_pipe(1);
                if snapshot_data(34) = start_req and snapshot_data(35) = clear_req then
                    frames_visible <= unsigned(snapshot_data(31 downto 0));
                    overflow_visible <= snapshot_data(32);
                    if state = CLEAR_WAIT then
                        if snapshot_data(33) = '1' and snapshot_data(32) = '0'
                            and unsigned(snapshot_data(31 downto 0)) = 0 then state <= IDLE; end if;
                    else
                        if snapshot_data(32) = '1' then next_errors(1) := '1'; end if;
                        if state = ACTIVE and snapshot_data(33) = '1'
                            and unsigned(snapshot_data(31 downto 0)) = unsigned(block_length) then
                            producer_finished <= '1';
                        end if;
                    end if;
                end if;
            end if;

            if state = RECOVERY then
                if recover_dropping = '0' then
                    if stream_resetn_i = '1' and recover_ack_pipe(1) = '1' and read_busy = '0' then
                        recover_req <= '0'; recover_dropping <= '1';
                    end if;
                elsif recover_ack_pipe(1) = '0' and read_busy = '0' then
                    state <= IDLE; recover_dropping <= '0';
                end if;
            elsif stream_resetn_i = '0' then
                if state = ACTIVE then next_errors(2) := '1'; end if;
                state <= RECOVERY; recover_req <= '1'; recover_dropping <= '0'; done <= '0';
            elsif state = ACTIVE and producer_finished = '1' and final_sent = '1'
                and next_errors = "000" then
                state <= IDLE; done <= '1';
            end if;

            conflicting := (start_i = '1' and (abort_i = '1' or clear_i = '1'))
                or (abort_i = '1' and clear_i = '1');
            if config_error_i = '1' or conflicting then
                next_errors(0) := '1';
            elsif abort_i = '1' then
                next_errors(2) := '1';
            elsif clear_i = '1' then
                if state = IDLE and fifo_empty = '1' and stream_resetn_i = '1' then
                    clear_req <= not clear_req; state <= CLEAR_WAIT; next_errors := "000";
                    done <= '0'; frames_visible <= (others => '0'); words_sent <= (others => '0');
                    overflow_visible <= '0'; final_sent <= '0'; producer_finished <= '0';
                else next_errors(0) := '1'; end if;
            elsif start_i = '1' then
                if state = IDLE and next_errors = "000" and clock_ready_i = '1'
                    and unsigned(n_frames_i) >= 1 and unsigned(n_frames_i) <= 65536
                    and fifo_empty = '1' and read_busy = '0' and stream_resetn_i = '1' then
                    block_length <= n_frames_i; block_pattern <= source_pattern_i;
                    start_req <= not start_req; state <= ACTIVE; done <= '0';
                    frames_visible <= (others => '0'); words_sent <= (others => '0'); overflow_visible <= '0';
                    final_sent <= '0'; producer_finished <= '0';
                else next_errors(0) := '1'; end if;
            end if;
            if state = ACTIVE and clock_ready_i = '0' then next_errors(0) := '1'; end if;
            if next_errors /= "000" then done <= '0'; end if;
            errors <= next_errors;
        end if;
    end process;
end rtl;
