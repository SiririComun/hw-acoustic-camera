-- RAW/PCM integration top; DMA stream reset never resets AXI-Lite or the clock.
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity acoustic_pdm_pcm_control is
    port (
        aclk             : in  std_logic;
        aresetn          : in  std_logic;

        s_axi_awaddr     : in  std_logic_vector(6 downto 0);
        s_axi_awprot     : in  std_logic_vector(2 downto 0);
        s_axi_awvalid    : in  std_logic;
        s_axi_awready    : out std_logic;
        s_axi_wdata      : in  std_logic_vector(31 downto 0);
        s_axi_wstrb      : in  std_logic_vector(3 downto 0);
        s_axi_wvalid     : in  std_logic;
        s_axi_wready     : out std_logic;
        s_axi_bresp      : out std_logic_vector(1 downto 0);
        s_axi_bvalid     : out std_logic;
        s_axi_bready     : in  std_logic;
        s_axi_araddr     : in  std_logic_vector(6 downto 0);
        s_axi_arprot     : in  std_logic_vector(2 downto 0);
        s_axi_arvalid    : in  std_logic;
        s_axi_arready    : out std_logic;
        s_axi_rdata      : out std_logic_vector(31 downto 0);
        s_axi_rresp      : out std_logic_vector(1 downto 0);
        s_axi_rvalid     : out std_logic;
        s_axi_rready     : in  std_logic;

        pdm_clk_o : out std_logic;
        pdm_data_i : in std_logic_vector(3 downto 0);
        stream_resetn_i : in std_logic;
        m_axis_tdata : out std_logic_vector(31 downto 0);
        m_axis_tkeep : out std_logic_vector(3 downto 0);
        m_axis_tlast, m_axis_tvalid : out std_logic;
        m_axis_tready : in std_logic
    );
    attribute X_INTERFACE_PARAMETER : string;
    attribute X_INTERFACE_PARAMETER of aclk : signal is
        "XIL_INTERFACENAME aclk, ASSOCIATED_BUSIF s_axi:m_axis, ASSOCIATED_RESET aresetn, FREQ_HZ 100000000";
end acoustic_pdm_pcm_control;

architecture rtl of acoustic_pdm_pcm_control is
    signal clk24, resetn24, sample_ce, enable, ready24, locked : std_logic;
    signal ready_meta, ready_sync, locked_meta, locked_sync : std_logic := '0';
    signal ready, busy, done, source_pattern, start, abort_cmd, clear_cmd, config_error : std_logic;
    signal format_pcm, filter_ready : std_logic;
    signal clips : std_logic_vector(31 downto 0);
    signal n_frames, frames, words, overflows : std_logic_vector(31 downto 0);
    signal errors : std_logic_vector(2 downto 0);
    attribute ASYNC_REG : string;
    attribute ASYNC_REG of ready_meta, ready_sync, locked_meta, locked_sync : signal is "TRUE";
begin
    ready <= ready_sync and locked_sync and enable;
    process(aclk)
    begin
        if rising_edge(aclk) then
            if aresetn = '0' then
                ready_meta <= '0'; ready_sync <= '0'; locked_meta <= '0'; locked_sync <= '0';
            else
                ready_meta <= ready24; ready_sync <= ready_meta;
                locked_meta <= locked; locked_sync <= locked_meta;
            end if;
        end if;
    end process;
    pdm_clock_i : entity work.acoustic_pdm_clock
        port map(aclk, aresetn, enable, pdm_clk_o, ready24, locked, clk24, resetn24, sample_ce);
    registers_i : entity work.acoustic_pdm_pcm_registers
        port map(
            aclk => aclk,
            aresetn => aresetn,
            s_axi_awaddr => s_axi_awaddr,
            s_axi_awprot => s_axi_awprot,
            s_axi_awvalid => s_axi_awvalid,
            s_axi_awready => s_axi_awready,
            s_axi_wdata => s_axi_wdata,
            s_axi_wstrb => s_axi_wstrb,
            s_axi_wvalid => s_axi_wvalid,
            s_axi_wready => s_axi_wready,
            s_axi_bresp => s_axi_bresp,
            s_axi_bvalid => s_axi_bvalid,
            s_axi_bready => s_axi_bready,
            s_axi_araddr => s_axi_araddr,
            s_axi_arprot => s_axi_arprot,
            s_axi_arvalid => s_axi_arvalid,
            s_axi_arready => s_axi_arready,
            s_axi_rdata => s_axi_rdata,
            s_axi_rresp => s_axi_rresp,
            s_axi_rvalid => s_axi_rvalid,
            s_axi_rready => s_axi_rready,
            clock_ready_i => ready, filter_ready_i => filter_ready, busy_i => busy, done_i => done,
            error_flags_i => errors, frames_produced_i => frames, words_sent_i => words,
            overflow_count_i => overflows, clip_count_i => clips, clock_enable_o => enable,
            format_pcm_o => format_pcm, source_pattern_o => source_pattern, n_frames_o => n_frames,
            start_o => start, abort_o => abort_cmd, clear_o => clear_cmd, config_error_o => config_error);
    capture_i : entity work.acoustic_pdm_pcm_capture
        port map(clk24, resetn24, aclk, aresetn, sample_ce, pdm_data_i, ready, ready24, format_pcm,
            start, abort_cmd, clear_cmd, config_error, n_frames, source_pattern,
            stream_resetn_i, busy, done, errors, filter_ready, clips, frames, words, overflows,
            m_axis_tdata, m_axis_tkeep, m_axis_tlast, m_axis_tvalid, m_axis_tready);
end rtl;
