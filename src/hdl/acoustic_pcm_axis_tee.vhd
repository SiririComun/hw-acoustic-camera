-- Two-consumer PCM stream fork. The phase tracker is permanently ready; DMA
-- backpressure therefore remains the only condition that can stall the source.
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

entity acoustic_pcm_axis_tee is
    port (
        aclk : in std_logic;
        aresetn : in std_logic;
        s_axis_tdata : in std_logic_vector(31 downto 0);
        s_axis_tkeep : in std_logic_vector(3 downto 0);
        s_axis_tlast : in std_logic;
        s_axis_tvalid : in std_logic;
        s_axis_tready : out std_logic;
        m_dma_tdata : out std_logic_vector(31 downto 0);
        m_dma_tkeep : out std_logic_vector(3 downto 0);
        m_dma_tlast : out std_logic;
        m_dma_tvalid : out std_logic;
        m_dma_tready : in std_logic;
        m_iq_tdata : out std_logic_vector(31 downto 0);
        m_iq_tkeep : out std_logic_vector(3 downto 0);
        m_iq_tlast : out std_logic;
        m_iq_tvalid : out std_logic;
        m_iq_tready : in std_logic
    );
    attribute X_INTERFACE_INFO : string;
    attribute X_INTERFACE_PARAMETER : string;
    attribute X_INTERFACE_INFO of aclk : signal is "xilinx.com:signal:clock:1.0 aclk CLK";
    attribute X_INTERFACE_PARAMETER of aclk : signal is
        "XIL_INTERFACENAME aclk, ASSOCIATED_BUSIF S_AXIS:M_DMA:M_IQ, ASSOCIATED_RESET aresetn, FREQ_HZ 100000000";
    attribute X_INTERFACE_INFO of aresetn : signal is "xilinx.com:signal:reset:1.0 aresetn RST";
    attribute X_INTERFACE_PARAMETER of aresetn : signal is
        "XIL_INTERFACENAME aresetn, POLARITY ACTIVE_LOW";
    attribute X_INTERFACE_INFO of s_axis_tdata : signal is "xilinx.com:interface:axis:1.0 S_AXIS TDATA";
    attribute X_INTERFACE_INFO of s_axis_tkeep : signal is "xilinx.com:interface:axis:1.0 S_AXIS TKEEP";
    attribute X_INTERFACE_INFO of s_axis_tlast : signal is "xilinx.com:interface:axis:1.0 S_AXIS TLAST";
    attribute X_INTERFACE_INFO of s_axis_tvalid : signal is "xilinx.com:interface:axis:1.0 S_AXIS TVALID";
    attribute X_INTERFACE_INFO of s_axis_tready : signal is "xilinx.com:interface:axis:1.0 S_AXIS TREADY";
    attribute X_INTERFACE_INFO of m_dma_tdata : signal is "xilinx.com:interface:axis:1.0 M_DMA TDATA";
    attribute X_INTERFACE_INFO of m_dma_tkeep : signal is "xilinx.com:interface:axis:1.0 M_DMA TKEEP";
    attribute X_INTERFACE_INFO of m_dma_tlast : signal is "xilinx.com:interface:axis:1.0 M_DMA TLAST";
    attribute X_INTERFACE_INFO of m_dma_tvalid : signal is "xilinx.com:interface:axis:1.0 M_DMA TVALID";
    attribute X_INTERFACE_INFO of m_dma_tready : signal is "xilinx.com:interface:axis:1.0 M_DMA TREADY";
    attribute X_INTERFACE_INFO of m_iq_tdata : signal is "xilinx.com:interface:axis:1.0 M_IQ TDATA";
    attribute X_INTERFACE_INFO of m_iq_tkeep : signal is "xilinx.com:interface:axis:1.0 M_IQ TKEEP";
    attribute X_INTERFACE_INFO of m_iq_tlast : signal is "xilinx.com:interface:axis:1.0 M_IQ TLAST";
    attribute X_INTERFACE_INFO of m_iq_tvalid : signal is "xilinx.com:interface:axis:1.0 M_IQ TVALID";
    attribute X_INTERFACE_INFO of m_iq_tready : signal is "xilinx.com:interface:axis:1.0 M_IQ TREADY";
end entity;

architecture rtl of acoustic_pcm_axis_tee is
begin
    s_axis_tready <= m_dma_tready and m_iq_tready;
    m_dma_tdata <= s_axis_tdata;
    m_dma_tkeep <= s_axis_tkeep;
    m_dma_tlast <= s_axis_tlast;
    m_dma_tvalid <= s_axis_tvalid and m_iq_tready;
    m_iq_tdata <= s_axis_tdata;
    m_iq_tkeep <= s_axis_tkeep;
    m_iq_tlast <= s_axis_tlast;
    m_iq_tvalid <= s_axis_tvalid and m_dma_tready;
end architecture;
