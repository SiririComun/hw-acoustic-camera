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
        marker_cfg2_i : in std_logic_vector(31 downto 0);

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
    type axis_meta_t is record
        data : std_logic_vector(23 downto 0);
        keep : std_logic_vector(2 downto 0);
        strb : std_logic_vector(2 downto 0);
        user : std_logic_vector(0 downto 0);
        last : std_logic;
    end record;
    type coordinate_stage_t is record
        meta : axis_meta_t;
        x_value, y_value : unsigned(9 downto 0);
        cfg1, cfg2 : std_logic_vector(31 downto 0);
    end record;
    type signed_delta_stage_t is record
        meta : axis_meta_t;
        dx1, dy1, dx2, dy2 : signed(10 downto 0);
        radius1, radius2 : unsigned(5 downto 0);
        enabled1, enabled2 : std_logic;
    end record;
    type magnitude_stage_t is record
        meta : axis_meta_t;
        dx1, dy1, dx2, dy2 : unsigned(10 downto 0);
        radius1, radius2 : unsigned(5 downto 0);
        enabled1, enabled2 : std_logic;
    end record;
    type delta_stage_t is record
        meta : axis_meta_t;
        dx1, dy1, dx2, dy2 : unsigned(5 downto 0);
        radius1, radius2 : unsigned(5 downto 0);
        enabled1, enabled2 : std_logic;
    end record;
    type major_stage_t is record
        meta : axis_meta_t;
        major1, minor1, major2, minor2 : unsigned(5 downto 0);
        radius1, radius2 : unsigned(5 downto 0);
        enabled1, enabled2 : std_logic;
    end record;
    type distance_stage_t is record
        meta : axis_meta_t;
        distance1, distance2 : unsigned(6 downto 0);
        radius1, radius2 : unsigned(5 downto 0);
        enabled1, enabled2 : std_logic;
    end record;
    type color_stage_t is record
        meta : axis_meta_t;
        red_level, cyan_level : unsigned(2 downto 0);
    end record;

    signal x_count, y_count : unsigned(9 downto 0) := (others => '0');
    signal marker_cfg_meta, marker_cfg_sync : std_logic_vector(31 downto 0) := (others => '0');
    signal marker_cfg2_meta, marker_cfg2_sync : std_logic_vector(31 downto 0) := (others => '0');
    signal target_cfg1, frame_cfg1, target_cfg2, frame_cfg2 : std_logic_vector(31 downto 0) := (others => '0');
    signal coordinate_in, coordinate_stage : coordinate_stage_t;
    signal signed_delta_in, signed_delta_stage : signed_delta_stage_t;
    signal magnitude_in, magnitude_stage : magnitude_stage_t;
    signal delta_in, delta_stage : delta_stage_t;
    signal major_in, major_stage : major_stage_t;
    signal distance_in, distance_stage : distance_stage_t;
    signal color_in, color_stage : color_stage_t;
    signal coordinate_valid, signed_delta_valid, magnitude_valid,
           delta_valid, major_valid, distance_valid, color_valid,
           output_valid : std_logic := '0';
    signal coordinate_ready, signed_delta_ready, magnitude_ready,
           delta_ready, major_ready, distance_ready, color_ready,
           output_ready : std_logic;
    signal output_meta : axis_meta_t;
    attribute ASYNC_REG : string;
    attribute ASYNC_REG of marker_cfg_meta : signal is "TRUE";
    attribute ASYNC_REG of marker_cfg_sync : signal is "TRUE";
    attribute ASYNC_REG of marker_cfg2_meta : signal is "TRUE";
    attribute ASYNC_REG of marker_cfg2_sync : signal is "TRUE";

    function abs_difference(a, b : unsigned(9 downto 0)) return unsigned is
    begin
        if a >= b then return a - b;
        else return b - a; end if;
    end function;

    function glow_level(enabled : std_logic; distance_value : unsigned(6 downto 0);
                        radius : unsigned(5 downto 0)) return natural is
        variable inner_limit, middle_limit, outer_limit : unsigned(5 downto 0);
    begin
        if enabled = '0' or radius = 0 then return 0; end if;
        inner_limit := shift_right(radius, 2);
        middle_limit := shift_right(radius, 1);
        outer_limit := middle_limit + inner_limit;
        if distance_value <= resize(inner_limit, 7) then return 4;
        elsif distance_value <= resize(middle_limit, 7) then return 3;
        elsif distance_value <= resize(outer_limit, 7) then return 2;
        elsif distance_value <= resize(radius, 7) then return 1;
        else return 0; end if;
    end function;

    function marker_color(pixel : std_logic_vector(23 downto 0);
                          red_level, cyan_level : natural) return std_logic_vector is
    begin
        if red_level = 0 and cyan_level = 0 then return pixel;
        elsif red_level = 4 and cyan_level = 4 then return x"FFFFFF";
        elsif red_level >= cyan_level then
            case red_level is
                when 4 => return x"FF1800";
                when 3 => return x"D01400";
                when 2 => return x"920D00";
                when others => return x"500700";
            end case;
        else
            case cyan_level is
                when 4 => return x"00FFFF";
                when 3 => return x"00C8D0";
                when 2 => return x"008A98";
                when others => return x"004A58";
            end case;
        end if;
    end function;
begin
    -- Eight elastic stages keep coordinate subtraction, magnitude, radius
    -- classification, distance, glow classification and color composition
    -- on separate cycles.
    output_ready <= (not output_valid) or m_axis_tready;
    color_ready <= (not color_valid) or output_ready;
    distance_ready <= (not distance_valid) or color_ready;
    major_ready <= (not major_valid) or distance_ready;
    delta_ready <= (not delta_valid) or major_ready;
    magnitude_ready <= (not magnitude_valid) or delta_ready;
    signed_delta_ready <= (not signed_delta_valid) or magnitude_ready;
    coordinate_ready <= (not coordinate_valid) or signed_delta_ready;
    s_axis_tready <= coordinate_ready;
    m_axis_tvalid <= output_valid;
    m_axis_tdata <= output_meta.data;
    m_axis_tkeep <= output_meta.keep;
    m_axis_tstrb <= output_meta.strb;
    m_axis_tuser <= output_meta.user;
    m_axis_tlast <= output_meta.last;

    process(s_axis_tuser, x_count, y_count, frame_cfg1, frame_cfg2,
            target_cfg1, target_cfg2, s_axis_tdata, s_axis_tkeep,
            s_axis_tstrb, s_axis_tlast)
        variable value : coordinate_stage_t;
    begin
        value.meta.data := s_axis_tdata;
        value.meta.keep := s_axis_tkeep;
        value.meta.strb := s_axis_tstrb;
        value.meta.user := s_axis_tuser;
        value.meta.last := s_axis_tlast;
        if s_axis_tuser(0) = '1' then
            value.x_value := (others => '0');
            value.y_value := (others => '0');
            value.cfg1 := target_cfg1;
            value.cfg2 := target_cfg2;
        else
            value.x_value := x_count;
            value.y_value := y_count;
            value.cfg1 := frame_cfg1;
            value.cfg2 := frame_cfg2;
        end if;
        coordinate_in <= value;
    end process;

    process(coordinate_stage)
        variable value : signed_delta_stage_t;
    begin
        value.meta := coordinate_stage.meta;
        value.radius1 := unsigned(coordinate_stage.cfg1(25 downto 20));
        value.radius2 := unsigned(coordinate_stage.cfg2(25 downto 20));
        value.enabled1 := coordinate_stage.cfg1(31);
        value.enabled2 := coordinate_stage.cfg2(31);
        value.dx1 := signed('0' & std_logic_vector(coordinate_stage.x_value)) -
                     signed('0' & coordinate_stage.cfg1(9 downto 0));
        value.dy1 := signed('0' & std_logic_vector(coordinate_stage.y_value)) -
                     signed('0' & coordinate_stage.cfg1(19 downto 10));
        value.dx2 := signed('0' & std_logic_vector(coordinate_stage.x_value)) -
                     signed('0' & coordinate_stage.cfg2(9 downto 0));
        value.dy2 := signed('0' & std_logic_vector(coordinate_stage.y_value)) -
                     signed('0' & coordinate_stage.cfg2(19 downto 10));
        signed_delta_in <= value;
    end process;

    process(signed_delta_stage)
        variable value : magnitude_stage_t;
    begin
        value.meta := signed_delta_stage.meta;
        value.radius1 := signed_delta_stage.radius1;
        value.radius2 := signed_delta_stage.radius2;
        value.enabled1 := signed_delta_stage.enabled1;
        value.enabled2 := signed_delta_stage.enabled2;
        if signed_delta_stage.dx1(10) = '1' then
            value.dx1 := unsigned(-signed_delta_stage.dx1);
        else value.dx1 := unsigned(signed_delta_stage.dx1); end if;
        if signed_delta_stage.dy1(10) = '1' then
            value.dy1 := unsigned(-signed_delta_stage.dy1);
        else value.dy1 := unsigned(signed_delta_stage.dy1); end if;
        if signed_delta_stage.dx2(10) = '1' then
            value.dx2 := unsigned(-signed_delta_stage.dx2);
        else value.dx2 := unsigned(signed_delta_stage.dx2); end if;
        if signed_delta_stage.dy2(10) = '1' then
            value.dy2 := unsigned(-signed_delta_stage.dy2);
        else value.dy2 := unsigned(signed_delta_stage.dy2); end if;
        magnitude_in <= value;
    end process;

    process(magnitude_stage)
        variable value : delta_stage_t;
    begin
        value.meta := magnitude_stage.meta;
        value.radius1 := magnitude_stage.radius1;
        value.radius2 := magnitude_stage.radius2;
        value.enabled1 := '0'; value.enabled2 := '0';
        value.dx1 := (others => '0'); value.dy1 := (others => '0');
        value.dx2 := (others => '0'); value.dy2 := (others => '0');
        if magnitude_stage.enabled1 = '1' and magnitude_stage.radius1 /= 0 and
           magnitude_stage.dx1 <= resize(magnitude_stage.radius1, 11) and
           magnitude_stage.dy1 <= resize(magnitude_stage.radius1, 11) then
            value.enabled1 := '1';
            value.dx1 := magnitude_stage.dx1(5 downto 0);
            value.dy1 := magnitude_stage.dy1(5 downto 0);
        end if;
        if magnitude_stage.enabled2 = '1' and magnitude_stage.radius2 /= 0 and
           magnitude_stage.dx2 <= resize(magnitude_stage.radius2, 11) and
           magnitude_stage.dy2 <= resize(magnitude_stage.radius2, 11) then
            value.enabled2 := '1';
            value.dx2 := magnitude_stage.dx2(5 downto 0);
            value.dy2 := magnitude_stage.dy2(5 downto 0);
        end if;
        delta_in <= value;
    end process;

    process(delta_stage)
        variable value : major_stage_t;
    begin
        value.meta := delta_stage.meta;
        value.radius1 := delta_stage.radius1; value.radius2 := delta_stage.radius2;
        value.enabled1 := delta_stage.enabled1; value.enabled2 := delta_stage.enabled2;
        if delta_stage.dx1 >= delta_stage.dy1 then
            value.major1 := delta_stage.dx1; value.minor1 := delta_stage.dy1;
        else value.major1 := delta_stage.dy1; value.minor1 := delta_stage.dx1; end if;
        if delta_stage.dx2 >= delta_stage.dy2 then
            value.major2 := delta_stage.dx2; value.minor2 := delta_stage.dy2;
        else value.major2 := delta_stage.dy2; value.minor2 := delta_stage.dx2; end if;
        major_in <= value;
    end process;

    process(major_stage)
        variable value : distance_stage_t;
        variable distance1, distance2 : unsigned(6 downto 0);
    begin
        value.meta := major_stage.meta;
        value.radius1 := major_stage.radius1; value.radius2 := major_stage.radius2;
        value.enabled1 := major_stage.enabled1; value.enabled2 := major_stage.enabled2;
        distance1 := resize(major_stage.major1, 7) +
                     resize(shift_right(major_stage.minor1, 2), 7) +
                     resize(shift_right(major_stage.minor1, 3), 7) +
                     resize(shift_right(major_stage.minor1, 5), 7);
        distance2 := resize(major_stage.major2, 7) +
                     resize(shift_right(major_stage.minor2, 2), 7) +
                     resize(shift_right(major_stage.minor2, 3), 7) +
                     resize(shift_right(major_stage.minor2, 5), 7);
        value.distance1 := distance1; value.distance2 := distance2;
        distance_in <= value;
    end process;

    process(distance_stage)
        variable value : color_stage_t;
    begin
        value.meta := distance_stage.meta;
        value.red_level := to_unsigned(
            glow_level(distance_stage.enabled1, distance_stage.distance1,
                       distance_stage.radius1), 3);
        value.cyan_level := to_unsigned(
            glow_level(distance_stage.enabled2, distance_stage.distance2,
                       distance_stage.radius2), 3);
        color_in <= value;
    end process;

    process(aclk)
        variable value : axis_meta_t;
    begin
        if rising_edge(aclk) then
            if aresetn = '0' then
                x_count <= (others => '0'); y_count <= (others => '0');
                marker_cfg_meta <= (others => '0'); marker_cfg_sync <= (others => '0');
                marker_cfg2_meta <= (others => '0'); marker_cfg2_sync <= (others => '0');
                target_cfg1 <= (others => '0'); frame_cfg1 <= (others => '0');
                target_cfg2 <= (others => '0'); frame_cfg2 <= (others => '0');
                coordinate_valid <= '0'; signed_delta_valid <= '0'; magnitude_valid <= '0';
                delta_valid <= '0'; major_valid <= '0';
                distance_valid <= '0'; color_valid <= '0'; output_valid <= '0';
                output_meta <= (data => (others => '0'), keep => (others => '0'),
                                strb => (others => '0'), user => (others => '0'), last => '0');
            else
                -- AXI GPIO is clocked by FCLK3; synchronize both marker words
                -- into the 142.9 MHz pixel domain and latch them at frame start.
                marker_cfg_meta <= marker_cfg_i;
                marker_cfg_sync <= marker_cfg_meta;
                marker_cfg2_meta <= marker_cfg2_i;
                marker_cfg2_sync <= marker_cfg2_meta;
                target_cfg1 <= marker_cfg_sync;
                target_cfg2 <= marker_cfg2_sync;

                if output_ready = '1' then
                    output_valid <= color_valid;
                    if color_valid = '1' then
                        value := color_stage.meta;
                        value.data := marker_color(value.data,
                                                   to_integer(color_stage.red_level),
                                                   to_integer(color_stage.cyan_level));
                        output_meta <= value;
                    end if;
                end if;
                if color_ready = '1' then
                    color_valid <= distance_valid;
                    if distance_valid = '1' then color_stage <= color_in; end if;
                end if;
                if distance_ready = '1' then
                    distance_valid <= major_valid;
                    if major_valid = '1' then distance_stage <= distance_in; end if;
                end if;
                if major_ready = '1' then
                    major_valid <= delta_valid;
                    if delta_valid = '1' then major_stage <= major_in; end if;
                end if;
                if delta_ready = '1' then
                    delta_valid <= magnitude_valid;
                    if magnitude_valid = '1' then delta_stage <= delta_in; end if;
                end if;
                if magnitude_ready = '1' then
                    magnitude_valid <= signed_delta_valid;
                    if signed_delta_valid = '1' then magnitude_stage <= magnitude_in; end if;
                end if;
                if signed_delta_ready = '1' then
                    signed_delta_valid <= coordinate_valid;
                    if coordinate_valid = '1' then signed_delta_stage <= signed_delta_in; end if;
                end if;
                if coordinate_ready = '1' then
                    coordinate_valid <= s_axis_tvalid;
                    if s_axis_tvalid = '1' then coordinate_stage <= coordinate_in; end if;
                end if;

                if s_axis_tvalid = '1' and coordinate_ready = '1' then
                    if s_axis_tuser(0) = '1' then
                        frame_cfg1 <= target_cfg1;
                        frame_cfg2 <= target_cfg2;
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
