-- =============================================================================
-- File: axis_decimator.vhd
-- Description: Runtime-Configurable Dual-Channel AXI4-Stream Decimator
--              Supports dynamic switching between:
--                • "00": M = 1  (Bypass: 500 kSPS Wideband Lab Scope)
--                • "01": M = 10 (50 kSPS Full Audio)
--                • "10": M = 20 (25 kSPS Speech / Acoustic)
--                • "11": M = 50 (10 kSPS Deep Bass Zoom, Δf = 4.88 Hz)
--              Phase-locked to physical XADC channel_id (0x11 = A0, 0x19 = A1).
--              Includes synchronous accumulator flush on dynamic decim_sel changes.
-- =============================================================================
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity axis_decimator is
    port (
        aclk          : in  std_logic;
        aresetn       : in  std_logic;

        -- =====================================================================
        -- Runtime Decimation Selector (from axis_trigger_unit register 0x14)
        -- =====================================================================
        decim_sel     : in  std_logic_vector(1 downto 0);

        -- =====================================================================
        -- Hardware Channel Identifier from XADC (0x11 = Vaux1/A0, 0x19 = Vaux9/A1)
        -- =====================================================================
        channel_id    : in  std_logic_vector(4 downto 0);

        -- =====================================================================
        -- AXI4-Stream Slave Interface (Raw 500 kSPS Interleaved Stream)
        -- =====================================================================
        s_axis_tdata  : in  std_logic_vector(15 downto 0);
        s_axis_tvalid : in  std_logic;
        s_axis_tready : out std_logic;

        -- =====================================================================
        -- AXI4-Stream Master Interface (Decimated Interleaved Stream)
        -- =====================================================================
        m_axis_tdata  : out std_logic_vector(15 downto 0);
        m_axis_tvalid : out std_logic;
        m_axis_tready : in  std_logic
    );
end axis_decimator;

architecture Behavioral of axis_decimator is

    -- Constant Channel Addresses in 7-Series XADC
    constant CH_VAUX1          : std_logic_vector(4 downto 0) := "10001"; -- 0x11 (Channel 1 / A0)
    constant CH_VAUX9          : std_logic_vector(4 downto 0) := "11001"; -- 0x19 (Channel 2 / A1)

    -- Independent 24-bit Accumulators (Prevent overflow for up to M=50 sums)
    signal acc_ch1             : unsigned(23 downto 0) := (others => '0');
    signal acc_ch2             : unsigned(23 downto 0) := (others => '0');
    signal count_ch1           : integer range 0 to 50 := 0;
    signal count_ch2           : integer range 0 to 50 := 0;

    -- Edge detection for runtime profile switching
    signal decim_sel_prev      : std_logic_vector(1 downto 0) := "01";

    -- Output Emission Registers
    signal avg_ch1_reg         : std_logic_vector(15 downto 0) := (others => '0');
    signal avg_ch2_reg         : std_logic_vector(15 downto 0) := (others => '0');

    -- Output State Machine (Emits decimated Ch1 then Ch2 sequentially)
    -- Exact unsigned division, pipelined to avoid a long combinational divider.
    -- M=10/20: shift by 1/2 then divide by 5; M=50: shift by 1
    -- then divide by 25. Reciprocal underestimation is at most one unit.
    signal total_ch1, total_ch2 : unsigned(21 downto 0) := (others => '0');
    signal numerator_ch1, numerator_ch2 : unsigned(20 downto 0) := (others => '0');
    signal product_ch1, product_ch2 : unsigned(37 downto 0) := (others => '0');
    signal quotient_ch1, quotient_ch2 : unsigned(15 downto 0) := (others => '0');
    signal remainder_ch1, remainder_ch2 : unsigned(20 downto 0) := (others => '0');
    attribute use_dsp : string;
    attribute use_dsp of product_ch1, product_ch2 : signal is "yes";
    type t_out_state is (ST_ACCUMULATING, ST_DIV_MULTIPLY,
                        ST_DIV_REMAINDER, ST_DIV_CORRECT, ST_EMIT_CH1, ST_EMIT_CH2);
    signal out_state           : t_out_state := ST_ACCUMULATING;

begin

    s_axis_tready <= '1' when (out_state = ST_ACCUMULATING) else '0';

    m_axis_tdata <= avg_ch1_reg when (out_state = ST_EMIT_CH1) else
                    avg_ch2_reg when (out_state = ST_EMIT_CH2) else
                    (others => '0');

    m_axis_tvalid <= '1' when (out_state = ST_EMIT_CH1 or out_state = ST_EMIT_CH2) else '0';

    process(aclk)
        variable sample_val : unsigned(15 downto 0);
        variable n1, n2, q1, q2, scaled1, scaled2 : unsigned(20 downto 0);
        variable reciprocal : unsigned(16 downto 0);
        variable divisor : natural range 5 to 25;
        variable is_ch1     : boolean;
        variable is_ch2     : boolean;
        variable m_target   : integer range 1 to 50;
    begin
        if rising_edge(aclk) then
            if aresetn = '0' then
                acc_ch1        <= (others => '0');
                acc_ch2        <= (others => '0');
                count_ch1      <= 0;
                count_ch2      <= 0;
                avg_ch1_reg    <= (others => '0');
                avg_ch2_reg    <= (others => '0');
                decim_sel_prev <= decim_sel;
                out_state      <= ST_ACCUMULATING;
            else
                decim_sel_prev <= decim_sel;

                -- Synchronous flush on dynamic decimation mode switch
                if decim_sel /= decim_sel_prev then
                    acc_ch1     <= (others => '0');
                    acc_ch2     <= (others => '0');
                    count_ch1   <= 0;
                    count_ch2   <= 0;
                    out_state   <= ST_ACCUMULATING;
                else
                    -- Resolve active decimation target factor M
                    case decim_sel is
                        when "00"   => m_target := 1;   -- Bypass Mode (500 kSPS)
                        when "01"   => m_target := 10;  -- Full Audio (50 kSPS)
                        when "10"   => m_target := 20;  -- Speech / Vocal (25 kSPS)
                        when "11"   => m_target := 50;  -- Deep Bass Zoom (10 kSPS)
                        when others => m_target := 10;
                    end case;

                    case out_state is
                        -- ---------------------------------------------------------
                        -- 1. ACCUMULATE SAMPLES ACCORDING TO RUNTIME DECIM_SEL
                        -- ---------------------------------------------------------
                        when ST_ACCUMULATING =>
                            if s_axis_tvalid = '1' then
                                sample_val := unsigned(s_axis_tdata);
                                is_ch1     := (channel_id = CH_VAUX1);
                                is_ch2     := (channel_id = CH_VAUX9);

                                if is_ch1 then
                                    if count_ch1 < m_target then
                                        acc_ch1   <= acc_ch1 + sample_val;
                                        count_ch1 <= count_ch1 + 1;
                                    end if;
                                elsif is_ch2 then
                                    if count_ch2 < m_target then
                                        acc_ch2   <= acc_ch2 + sample_val;
                                        count_ch2 <= count_ch2 + 1;
                                    end if;
                                end if;

                                -- When both channels reach M samples, normalize and emit
                                if (is_ch2 and count_ch1 = m_target and count_ch2 = m_target - 1) or
                                   (count_ch1 = m_target and count_ch2 = m_target) then
                                    
                                    case decim_sel is
                                        when "00" => -- M = 1 (Bypass)
                                            avg_ch1_reg <= std_logic_vector(resize(acc_ch1, 16));
                                            if is_ch2 then
                                                avg_ch2_reg <= std_logic_vector(resize(sample_val, 16));
                                            else
                                                avg_ch2_reg <= std_logic_vector(resize(acc_ch2, 16));
                                            end if;

                                        when others => -- M=10,20,50: capture before normalization
                                            total_ch1 <= resize(acc_ch1, 22);
                                            if is_ch2 then
                                                total_ch2 <= resize(acc_ch2 + sample_val, 22);
                                            else
                                                total_ch2 <= resize(acc_ch2, 22);
                                            end if;
                                    end case;

                                    -- Reset accumulators
                                    acc_ch1     <= (others => '0');
                                    acc_ch2     <= (others => '0');
                                    count_ch1   <= 0;
                                    count_ch2   <= 0;

                                    if decim_sel = "00" then
                                        out_state <= ST_EMIT_CH1;
                                    else
                                        out_state <= ST_DIV_MULTIPLY;
                                    end if;
                                end if;
                            end if;

                        when ST_DIV_MULTIPLY =>
                            if decim_sel = "10" then
                                n1 := resize(shift_right(total_ch1, 2), 21);
                                n2 := resize(shift_right(total_ch2, 2), 21);
                            else
                                n1 := resize(shift_right(total_ch1, 1), 21);
                                n2 := resize(shift_right(total_ch2, 1), 21);
                            end if;
                            if decim_sel = "11" then
                                reciprocal := to_unsigned(83886, 17); -- floor(2**21/25)
                            else
                                reciprocal := to_unsigned(104857, 17); -- floor(2**19/5)
                            end if;
                            numerator_ch1 <= n1;
                            numerator_ch2 <= n2;
                            product_ch1 <= n1 * reciprocal;
                            product_ch2 <= n2 * reciprocal;
                            out_state <= ST_DIV_REMAINDER;

                        when ST_DIV_REMAINDER =>
                            if decim_sel = "11" then
                                q1 := resize(product_ch1(36 downto 21), 21);
                                q2 := resize(product_ch2(36 downto 21), 21);
                                scaled1 := shift_left(q1, 4) + shift_left(q1, 3) + q1;
                                scaled2 := shift_left(q2, 4) + shift_left(q2, 3) + q2;
                            else
                                q1 := resize(product_ch1(34 downto 19), 21);
                                q2 := resize(product_ch2(34 downto 19), 21);
                                scaled1 := shift_left(q1, 2) + q1;
                                scaled2 := shift_left(q2, 2) + q2;
                            end if;
                            quotient_ch1 <= resize(q1, 16);
                            quotient_ch2 <= resize(q2, 16);
                            remainder_ch1 <= numerator_ch1 - scaled1;
                            remainder_ch2 <= numerator_ch2 - scaled2;
                            out_state <= ST_DIV_CORRECT;

                        when ST_DIV_CORRECT =>
                            if decim_sel = "11" then divisor := 25;
                            else divisor := 5;
                            end if;
                            if remainder_ch1 >= divisor then
                                avg_ch1_reg <= std_logic_vector(quotient_ch1 + 1);
                            else
                                avg_ch1_reg <= std_logic_vector(quotient_ch1);
                            end if;
                            if remainder_ch2 >= divisor then
                                avg_ch2_reg <= std_logic_vector(quotient_ch2 + 1);
                            else
                                avg_ch2_reg <= std_logic_vector(quotient_ch2);
                            end if;
                            out_state <= ST_EMIT_CH1;

                        -- ---------------------------------------------------------
                        -- 2. EMIT CHANNEL 1 (A0) FIRST (GUARANTEED PHASE ORDER)
                        -- ---------------------------------------------------------
                        when ST_EMIT_CH1 =>
                            if m_axis_tready = '1' then
                                out_state <= ST_EMIT_CH2;
                            end if;

                        -- ---------------------------------------------------------
                        -- 3. EMIT CHANNEL 2 (A1) SECOND
                        -- ---------------------------------------------------------
                        when ST_EMIT_CH2 =>
                            if m_axis_tready = '1' then
                                out_state <= ST_ACCUMULATING;
                            end if;

                    end case;
                end if;
            end if;
        end if;
    end process;

end Behavioral;