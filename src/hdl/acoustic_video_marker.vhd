-- Low-cost point overlay on the HDMI OUT AXI4-Stream.
-- Pixel coordinates are supplied by the PS; pixel composition stays in PL.
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity acoustic_video_marker is
    port (
        aclk       : in std_logic;
        aresetn    : in std_logic;
        marker_cfg_i : in std_logic_vector(31 downto 0);

        s_axis_tdata  : in  std_logic_vector(23 downto 0);
        s_axis_tkeep  : in  std_logic_vector(2 downto 0);
        s_axis_tstrb  : in  std_logic_vector(2 downto 0);
        s_axis_tuser  : in  std_logic_vector(0 downto 0);
        s_axis_tlast  : in  std_logic;
        s_axis_tvalid : in  std_logic;
        s_axis_tready : out std_logic;

        m_axis_tdata  : out std_logic_vector(23 downto 0);
        m_axis_tkeep  : out std_logic_vector(2 downto 0);
        m_axis_tstrb  : out std_logic_vector(2 downto 0);
        m_axis_tuser  : out std_logic_vector(0 downto 0);
        m_axis_tlast  : out std_logic;
        m_axis_tvalid : out std_logic;
        m_axis_tready : in  std_logic
    );
    attribute X_INTERFACE_INFO : string;
    attribute X_INTERFACE_PARAMETER : string;
    attribute X_INTERFACE_INFO of aclk : signal is "xilinx.com:signal:clock:1.0 aclk CLK";
    attribute X_INTERFACE_PARAMETER of aclk : signal is
        "XIL_INTERFACENAME aclk, ASSOCIATED_BUSIF S_AXIS:M_AXIS, ASSOCIATED_RESET aresetn, FREQ_HZ 142857132";
    attribute X_INTERFACE_INFO of aresetn : signal is "xilinx.com:signal:reset:1.0 aresetn RST";
    attribute X_INTERFACE_PARAMETER of aresetn : signal is
        "XIL_INTERFACENAME aresetn, POLARITY ACTIVE_LOW";

    attribute X_INTERFACE_INFO of s_axis_tdata : signal is "xilinx.com:interface:axis:1.0 S_AXIS TDATA";
    attribute X_INTERFACE_INFO of s_axis_tkeep : signal is "xilinx.com:interface:axis:1.0 S_AXIS TKEEP";
    attribute X_INTERFACE_INFO of s_axis_tstrb : signal is "xilinx.com:interface:axis:1.0 S_AXIS TSTRB";
    attribute X_INTERFACE_INFO of s_axis_tuser : signal is "xilinx.com:interface:axis:1.0 S_AXIS TUSER";
    attribute X_INTERFACE_INFO of s_axis_tlast : signal is "xilinx.com:interface:axis:1.0 S_AXIS TLAST";
    attribute X_INTERFACE_INFO of s_axis_tvalid : signal is "xilinx.com:interface:axis:1.0 S_AXIS TVALID";
    attribute X_INTERFACE_INFO of s_axis_tready : signal is "xilinx.com:interface:axis:1.0 S_AXIS TREADY";
    attribute X_INTERFACE_INFO of m_axis_tdata : signal is "xilinx.com:interface:axis:1.0 M_AXIS TDATA";
    attribute X_INTERFACE_INFO of m_axis_tkeep : signal is "xilinx.com:interface:axis:1.0 M_AXIS TKEEP";
    attribute X_INTERFACE_INFO of m_axis_tstrb : signal is "xilinx.com:interface:axis:1.0 M_AXIS TSTRB";
    attribute X_INTERFACE_INFO of m_axis_tuser : signal is "xilinx.com:interface:axis:1.0 M_AXIS TUSER";
    attribute X_INTERFACE_INFO of m_axis_tlast : signal is "xilinx.com:interface:axis:1.0 M_AXIS TLAST";
    attribute X_INTERFACE_INFO of m_axis_tvalid : signal is "xilinx.com:interface:axis:1.0 M_AXIS TVALID";
    attribute X_INTERFACE_INFO of m_axis_tready : signal is "xilinx.com:interface:axis:1.0 M_AXIS TREADY";
end acoustic_video_marker;

architecture rtl of acoustic_video_marker is
    signal x_count : unsigned(9 downto 0) := (others => '0');
    signal y_count : unsigned(9 downto 0) := (others => '0');
    signal frame_cfg : std_logic_vector(31 downto 0) := (others => '0');
    signal stage_valid : std_logic := '0';
    signal stage_data : std_logic_vector(23 downto 0) := (others => '0');
    signal stage_keep : std_logic_vector(2 downto 0) := (others => '0');
    signal stage_strb : std_logic_vector(2 downto 0) := (others => '0');
    signal stage_user : std_logic_vector(0 downto 0) := (others => '0');
    signal stage_last : std_logic := '0';
    signal pixel_data : std_logic_vector(23 downto 0);
begin
    -- One-beat elastic stage breaks the coordinate/color path before HDMI and
    -- propagates backpressure without dropping or duplicating pixels.
    s_axis_tready <= (not stage_valid) or m_axis_tready;
    m_axis_tvalid <= stage_valid;
    m_axis_tdata <= stage_data;
    m_axis_tkeep <= stage_keep;
    m_axis_tstrb <= stage_strb;
    m_axis_tuser <= stage_user;
    m_axis_tlast <= stage_last;

    process(all)
        variable cfg : std_logic_vector(31 downto 0);
        variable x_now, y_now : integer range 0 to 1023;
        variable center_x, center_y, radius : integer range 0 to 1023;
        variable dx, dy : integer range -1023 to 1023;
        variable pixel : std_logic_vector(23 downto 0);
        variable abs_dx, abs_dy : integer range 0 to 1023;
    begin
        cfg := frame_cfg;
        if s_axis_tuser(0) = '1' then
            cfg := marker_cfg_i;
            x_now := 0;
            y_now := 0;
        else
            x_now := to_integer(x_count);
            y_now := to_integer(y_count);
        end if;

        center_x := to_integer(unsigned(cfg(9 downto 0)));
        center_y := to_integer(unsigned(cfg(19 downto 10)));
        radius := to_integer(unsigned(cfg(25 downto 20)));
        dx := x_now - center_x;
        dy := y_now - center_y;
        abs_dx := abs(dx);
        abs_dy := abs(dy);

        pixel := s_axis_tdata;
        -- An octagonal, multiplier-free approximation of a circular marker.
        if cfg(31) = '1' and abs_dx <= radius and abs_dy <= radius
            and abs_dx + abs_dy <= radius + radius / 2 then
            -- BGR byte layout matches the C920/OpenCV framebuffer path.
            pixel := x"FF0000";
        end if;
        pixel_data <= pixel;
    end process;

    process(aclk)
    begin
        if rising_edge(aclk) then
            if aresetn = '0' then
                x_count <= (others => '0');
                y_count <= (others => '0');
                frame_cfg <= (others => '0');
                stage_valid <= '0';
                stage_data <= (others => '0');
                stage_keep <= (others => '0');
                stage_strb <= (others => '0');
                stage_user <= (others => '0');
                stage_last <= '0';
            else
                if s_axis_tready = '1' then
                    stage_valid <= s_axis_tvalid;
                    if s_axis_tvalid = '1' then
                        stage_data <= pixel_data;
                        stage_keep <= s_axis_tkeep;
                        stage_strb <= s_axis_tstrb;
                        stage_user <= s_axis_tuser;
                        stage_last <= s_axis_tlast;
                    end if;
                end if;

                if s_axis_tvalid = '1' and s_axis_tready = '1' then
                    if s_axis_tuser(0) = '1' then
                        frame_cfg <= marker_cfg_i;
                        if s_axis_tlast = '1' then
                            x_count <= (others => '0');
                            y_count <= to_unsigned(1, y_count'length);
                        else
                            x_count <= to_unsigned(1, x_count'length);
                            y_count <= (others => '0');
                        end if;
                    elsif s_axis_tlast = '1' then
                        x_count <= (others => '0');
                        y_count <= y_count + 1;
                    else
                        x_count <= x_count + 1;
                    end if;
                end if;
            end if;
        end if;
    end process;
end rtl;
