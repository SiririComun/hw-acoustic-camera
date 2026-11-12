-- PDM clock source for the four-channel acoustic camera.
-- FCLK_CLK0 (100 MHz) -> MMCM (24 MHz) -> synchronous divide-by-ten (2.4 MHz).
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

library UNISIM;
use UNISIM.VCOMPONENTS.ALL;

entity acoustic_pdm_clock is
    port (
        clk_100m_i            : in  std_logic;
        resetn_100m_i         : in  std_logic;
        clock_enable_async_i  : in  std_logic;
        pdm_clk_o             : out std_logic;
        clock_ready_24m_o     : out std_logic;
        mmcm_locked_o         : out std_logic;
        clk_24m_o             : out std_logic;
        resetn_24m_o          : out std_logic;
        sample_ce_24m_o       : out std_logic
    );
end acoustic_pdm_clock;

architecture rtl of acoustic_pdm_clock is
    constant C_WARMUP_RISING_EDGES : natural := 48_000;

    signal clkfb_mmcm     : std_logic;
    signal clkfb          : std_logic;
    signal clk24_mmcm     : std_logic;
    signal clk24          : std_logic;
    signal mmcm_locked    : std_logic;
    signal mmcm_reset     : std_logic;
    signal reset24_async  : std_logic;
    signal reset24_pipe   : std_logic_vector(1 downto 0) := (others => '0');
    signal reset24n       : std_logic;

    signal enable_meta    : std_logic := '0';
    signal enable_sync    : std_logic := '0';
    signal pdm_clk_reg    : std_logic := '0';
    signal divide_count   : natural range 0 to 4 := 0;
    signal warmup_count   : natural range 0 to C_WARMUP_RISING_EDGES := 0;
    signal clock_ready_24 : std_logic := '0';

    attribute ASYNC_REG : string;
    attribute ASYNC_REG of reset24_pipe : signal is "TRUE";
    attribute ASYNC_REG of enable_meta : signal is "TRUE";
    attribute ASYNC_REG of enable_sync : signal is "TRUE";
begin
    mmcm_reset <= not resetn_100m_i;
    reset24_async <= (not resetn_100m_i) or (not mmcm_locked);
    reset24n <= reset24_pipe(1);

    -- The asynchronous assertion also clamps the external output low if MMCM
    -- lock is lost. Release is synchronized to the 24 MHz domain below.
    pdm_clk_o <= pdm_clk_reg and reset24n;
    clock_ready_24m_o <= clock_ready_24 and reset24n;
    mmcm_locked_o <= mmcm_locked;
    clk_24m_o <= clk24;
    resetn_24m_o <= reset24n;

    -- This is a synchronous enable, not a clock. Evaluate it BEFORE the
    -- sampling edge: falling PDM sets count=0; old count=2 selects the third
    -- following 24 MHz edge (125 ns nominal). Do not register this decode
    -- without anticipation, which would move the sample one base cycle late.
    -- No sample event is offered during reset, warmup or clock shutdown.
    sample_ce_24m_o <= '1' when reset24n = '1' and enable_sync = '1'
        and clock_ready_24 = '1' and pdm_clk_reg = '0' and divide_count = 2
        else '0';

    mmcm_i : MMCME2_BASE
        generic map (
            BANDWIDTH          => "OPTIMIZED",
            CLKFBOUT_MULT_F    => 36.0,
            CLKFBOUT_PHASE     => 0.0,
            CLKIN1_PERIOD      => 10.0,
            CLKOUT0_DIVIDE_F   => 30.0,
            CLKOUT0_DUTY_CYCLE => 0.5,
            CLKOUT0_PHASE      => 0.0,
            DIVCLK_DIVIDE      => 5,
            STARTUP_WAIT       => FALSE
        )
        port map (
            CLKIN1     => clk_100m_i,
            CLKFBIN    => clkfb,
            RST        => mmcm_reset,
            PWRDWN     => '0',
            CLKFBOUT   => clkfb_mmcm,
            CLKFBOUTB  => open,
            CLKOUT0    => clk24_mmcm,
            CLKOUT0B   => open,
            CLKOUT1    => open,
            CLKOUT1B   => open,
            CLKOUT2    => open,
            CLKOUT2B   => open,
            CLKOUT3    => open,
            CLKOUT3B   => open,
            CLKOUT4    => open,
            CLKOUT5    => open,
            CLKOUT6    => open,
            LOCKED     => mmcm_locked
        );

    feedback_bufg_i : BUFG
        port map (
            I => clkfb_mmcm,
            O => clkfb
        );

    clock24_bufg_i : BUFG
        port map (
            I => clk24_mmcm,
            O => clk24
        );

    -- Asynchronous assertion on reset or loss of lock, synchronous release.
    process (clk24, reset24_async)
    begin
        if reset24_async = '1' then
            reset24_pipe <= (others => '0');
        elsif rising_edge(clk24) then
            reset24_pipe <= reset24_pipe(0) & '1';
        end if;
    end process;

    -- CLOCK_ENABLE crosses as a stable level. The output clock is registered
    -- in this domain; stopping waits for the current high half-period to end.
    process (clk24)
    begin
        if rising_edge(clk24) then
            if reset24n = '0' then
                enable_meta <= '0';
                enable_sync <= '0';
            else
                enable_meta <= clock_enable_async_i;
                enable_sync <= enable_meta;
            end if;
        end if;
    end process;

    process (clk24)
    begin
        if rising_edge(clk24) then
            if reset24n = '0' then
                pdm_clk_reg <= '0';
                divide_count <= 0;
                warmup_count <= 0;
                clock_ready_24 <= '0';
            elsif enable_sync = '0' then
                clock_ready_24 <= '0';
                warmup_count <= 0;
                if pdm_clk_reg = '1' then
                    if divide_count = 4 then
                        pdm_clk_reg <= '0';
                        divide_count <= 0;
                    else
                        divide_count <= divide_count + 1;
                    end if;
                else
                    pdm_clk_reg <= '0';
                    divide_count <= 0;
                end if;
            elsif divide_count = 4 then
                divide_count <= 0;
                pdm_clk_reg <= not pdm_clk_reg;
                if pdm_clk_reg = '0' then
                    if warmup_count < C_WARMUP_RISING_EDGES then
                        warmup_count <= warmup_count + 1;
                        if warmup_count = C_WARMUP_RISING_EDGES - 1 then
                            clock_ready_24 <= '1';
                        end if;
                    else
                        clock_ready_24 <= '1';
                    end if;
                end if;
            else
                divide_count <= divide_count + 1;
            end if;
        end if;
    end process;
end rtl;
