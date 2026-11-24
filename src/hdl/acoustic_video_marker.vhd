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
    signal marker_cfg_meta : std_logic_vector(31 downto 0) := (others => '0');
    signal marker_cfg_sync : std_logic_vector(31 downto 0) := (others => '0');
    signal target_x_min : unsigned(9 downto 0) := (others => '0');
    signal target_x_max : unsigned(9 downto 0) := (others => '0');
    signal target_y_min : unsigned(9 downto 0) := (others => '0');
    signal target_y_max : unsigned(9 downto 0) := (others => '0');
    signal target_enable : std_logic := '0';
    signal frame_x_min : unsigned(9 downto 0) := (others => '0');
    signal frame_x_max : unsigned(9 downto 0) := (others => '0');
    signal frame_y_min : unsigned(9 downto 0) := (others => '0');
    signal frame_y_max : unsigned(9 downto 0) := (others => '0');
    signal frame_enable : std_logic := '0';
    signal stage_valid : std_logic := '0';
    signal stage_data : std_logic_vector(23 downto 0) := (others => '0');
    signal stage_keep : std_logic_vector(2 downto 0) := (others => '0');
    signal stage_strb : std_logic_vector(2 downto 0) := (others => '0');
    signal stage_user : std_logic_vector(0 downto 0) := (others => '0');
    signal stage_last : std_logic := '0';
    signal pixel_data : std_logic_vector(23 downto 0);
    signal s_axis_ready_int : std_logic;
    attribute ASYNC_REG : string;
    attribute ASYNC_REG of marker_cfg_meta : signal is "TRUE";
    attribute ASYNC_REG of marker_cfg_sync : signal is "TRUE";
begin
    -- One-beat elastic stage breaks the coordinate/color path before HDMI and
    -- propagates backpressure without dropping or duplicating pixels.
    s_axis_ready_int <= (not stage_valid) or m_axis_tready;
    s_axis_tready <= s_axis_ready_int;
    m_axis_tvalid <= stage_valid;
    m_axis_tdata <= stage_data;
    m_axis_tkeep <= stage_keep;
    m_axis_tstrb <= stage_strb;
    m_axis_tuser <= stage_user;
    m_axis_tlast <= stage_last;

    process(s_axis_tuser, x_count, y_count, frame_enable, frame_x_min,
            frame_x_max, frame_y_min, frame_y_max, s_axis_tdata)
        variable x_now, y_now : unsigned(9 downto 0);
        variable pixel : std_logic_vector(23 downto 0);
    begin
        if s_axis_tuser(0) = '1' then
            x_now := (others => '0');
            y_now := (others => '0');
        else
            x_now := x_count;
            y_now := y_count;
        end if;

        pixel := s_axis_tdata;
        -- A small square marker keeps the per-pixel path to two parallel
        -- coordinate range checks instead of subtract/abs/add arithmetic.
        if frame_enable = '1' and x_now >= frame_x_min and x_now <= frame_x_max
            and y_now >= frame_y_min and y_now <= frame_y_max then
            -- BGR byte layout matches the C920/OpenCV framebuffer path.
            pixel := x"FF0000";
        end if;
        pixel_data <= pixel;
    end process;

    process(aclk)
        variable center_x, center_y, radius : integer range 0 to 1023;
    begin
        if rising_edge(aclk) then
            if aresetn = '0' then
                x_count <= (others => '0');
                y_count <= (others => '0');
                marker_cfg_meta <= (others => '0');
                marker_cfg_sync <= (others => '0');
                target_x_min <= (others => '0');
                target_x_max <= (others => '0');
                target_y_min <= (others => '0');
                target_y_max <= (others => '0');
                target_enable <= '0';
                frame_x_min <= (others => '0');
                frame_x_max <= (others => '0');
                frame_y_min <= (others => '0');
                frame_y_max <= (others => '0');
                frame_enable <= '0';
                stage_valid <= '0';
                stage_data <= (others => '0');
                stage_keep <= (others => '0');
                stage_strb <= (others => '0');
                stage_user <= (others => '0');
                stage_last <= '0';
            else
                -- AXI GPIO is clocked by FCLK3; synchronize its static
                -- configuration word into the 142.9 MHz pixel domain.
                marker_cfg_meta <= marker_cfg_i;
                marker_cfg_sync <= marker_cfg_meta;

                center_x := to_integer(unsigned(marker_cfg_sync(9 downto 0)));
                center_y := to_integer(unsigned(marker_cfg_sync(19 downto 10)));
                radius := to_integer(unsigned(marker_cfg_sync(25 downto 20)));
                if center_x > radius then
                    target_x_min <= to_unsigned(center_x - radius, target_x_min'length);
                else
                    target_x_min <= (others => '0');
                end if;
                if center_x + radius > 1023 then
                    target_x_max <= (others => '1');
                else
                    target_x_max <= to_unsigned(center_x + radius, target_x_max'length);
                end if;
                if center_y > radius then
                    target_y_min <= to_unsigned(center_y - radius, target_y_min'length);
                else
                    target_y_min <= (others => '0');
                end if;
                if center_y + radius > 1023 then
                    target_y_max <= (others => '1');
                else
                    target_y_max <= to_unsigned(center_y + radius, target_y_max'length);
                end if;
                target_enable <= marker_cfg_sync(31);

                if s_axis_ready_int = '1' then
                    stage_valid <= s_axis_tvalid;
                    if s_axis_tvalid = '1' then
                        stage_data <= pixel_data;
                        stage_keep <= s_axis_tkeep;
                        stage_strb <= s_axis_tstrb;
                        stage_user <= s_axis_tuser;
                        stage_last <= s_axis_tlast;
                    end if;
                end if;

                if s_axis_tvalid = '1' and s_axis_ready_int = '1' then
                    if s_axis_tuser(0) = '1' then
                        frame_x_min <= target_x_min;
                        frame_x_max <= target_x_max;
                        frame_y_min <= target_y_min;
                        frame_y_max <= target_y_max;
                        frame_enable <= target_enable;
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
