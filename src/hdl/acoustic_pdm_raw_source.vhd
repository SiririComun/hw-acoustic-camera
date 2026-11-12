-- Phase-3 RAW sampling stage, entirely in the free-running 24 MHz domain.
-- Inputs block_start/capture_enable/source must already belong to this domain.
-- This is a registered FIFO-write interface, NOT an AXI Stream interface:
-- frame_valid is consumed on the next rising edge; there is no backpressure.
-- The block controller (step 3.3) must reserve FIFO capacity BEFORE admitting
-- a sample and supply the finite-block length, errors and command CDC.
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity acoustic_pdm_raw_source is
    port (
        clk_24m_i          : in  std_logic;
        resetn_24m_i       : in  std_logic;
        sample_ce_i        : in  std_logic;
        block_start_i      : in  std_logic;
        capture_enable_i   : in  std_logic;
        source_pattern_i   : in  std_logic;
        pdm_data_i         : in  std_logic_vector(3 downto 0);
        frame_valid_o      : out std_logic;
        frame_data_o       : out std_logic_vector(31 downto 0)
    );
end acoustic_pdm_raw_source;

architecture rtl of acoustic_pdm_raw_source is
    signal pattern_selected : std_logic := '0';
    signal pattern_index    : unsigned(31 downto 0) := (others => '0');
    signal frame_valid      : std_logic := '0';
    signal frame_data       : std_logic_vector(31 downto 0) := (others => '0');
begin
    frame_valid_o <= frame_valid;
    frame_data_o <= frame_data;

    process (clk_24m_i, resetn_24m_i)
    begin
        if resetn_24m_i = '0' then
            pattern_selected <= '0';
            pattern_index <= (others => '0');
            frame_valid <= '0';
            frame_data <= (others => '0');
        elsif rising_edge(clk_24m_i) then
            frame_valid <= '0';
            if block_start_i = '1' then
                -- START takes effect before the next eligible sample. If it
                -- coincides with a CE, this edge starts the block but does not
                -- capture it. Only START resets the diagnostic index.
                pattern_selected <= source_pattern_i;
                pattern_index <= (others => '0');
            elsif capture_enable_i = '1' and sample_ce_i = '1' then
                -- All four physical bits enter the SAME vector register on
                -- this edge. No per-channel synchronizers or sequential reads.
                if pattern_selected = '1' then
                    frame_data <= std_logic_vector(pattern_index);
                else
                    frame_data <= x"0000000" & pdm_data_i;
                end if;
                pattern_index <= pattern_index + 1;
                frame_valid <= '1';
            end if;
            -- Dropping capture_enable stops future samples; it does not alter
            -- the registered word already being consumed on this edge.
        end if;
    end process;
end rtl;
