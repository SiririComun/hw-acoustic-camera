-- Fixed-frequency four-channel I/Q tracker for signed-24 samples in 32-bit
-- PCM containers. FCLK3 is 100 MHz; the stream carries channels 0,1,2,3 with
-- TLAST on channel 3. PCM samples are observed without reordering or mutation.
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity acoustic_pcm_iq_tracker is
    generic (
        C_S_AXI_DATA_WIDTH : integer := 32;
        C_S_AXI_ADDR_WIDTH : integer := 8;
        G_WINDOW_FRAMES : positive := 2048
    );
    port (
        aclk : in std_logic;
        aresetn : in std_logic;
        s_axi_awaddr : in std_logic_vector(C_S_AXI_ADDR_WIDTH-1 downto 0);
        s_axi_awprot : in std_logic_vector(2 downto 0);
        s_axi_awvalid : in std_logic;
        s_axi_awready : out std_logic;
        s_axi_wdata : in std_logic_vector(C_S_AXI_DATA_WIDTH-1 downto 0);
        s_axi_wstrb : in std_logic_vector((C_S_AXI_DATA_WIDTH/8)-1 downto 0);
        s_axi_wvalid : in std_logic;
        s_axi_wready : out std_logic;
        s_axi_bresp : out std_logic_vector(1 downto 0);
        s_axi_bvalid : out std_logic;
        s_axi_bready : in std_logic;
        s_axi_araddr : in std_logic_vector(C_S_AXI_ADDR_WIDTH-1 downto 0);
        s_axi_arprot : in std_logic_vector(2 downto 0);
        s_axi_arvalid : in std_logic;
        s_axi_arready : out std_logic;
        s_axi_rdata : out std_logic_vector(C_S_AXI_DATA_WIDTH-1 downto 0);
        s_axi_rresp : out std_logic_vector(1 downto 0);
        s_axi_rvalid : out std_logic;
        s_axi_rready : in std_logic;
        s_axis_tdata : in std_logic_vector(31 downto 0);
        s_axis_tkeep : in std_logic_vector(3 downto 0);
        s_axis_tlast : in std_logic;
        s_axis_tvalid : in std_logic;
        s_axis_tready : out std_logic;
        pulse_start_i : in std_logic := '0'
    );
    attribute X_INTERFACE_INFO : string;
    attribute X_INTERFACE_PARAMETER : string;
    attribute X_INTERFACE_INFO of aclk : signal is "xilinx.com:signal:clock:1.0 aclk CLK";
    attribute X_INTERFACE_PARAMETER of aclk : signal is
        "XIL_INTERFACENAME aclk, ASSOCIATED_BUSIF S_AXI:S_AXIS, ASSOCIATED_RESET aresetn, FREQ_HZ 100000000";
    attribute X_INTERFACE_INFO of aresetn : signal is "xilinx.com:signal:reset:1.0 aresetn RST";
    attribute X_INTERFACE_PARAMETER of aresetn : signal is
        "XIL_INTERFACENAME aresetn, POLARITY ACTIVE_LOW";
    attribute X_INTERFACE_INFO of s_axis_tdata : signal is "xilinx.com:interface:axis:1.0 S_AXIS TDATA";
    attribute X_INTERFACE_INFO of s_axis_tkeep : signal is "xilinx.com:interface:axis:1.0 S_AXIS TKEEP";
    attribute X_INTERFACE_INFO of s_axis_tlast : signal is "xilinx.com:interface:axis:1.0 S_AXIS TLAST";
    attribute X_INTERFACE_INFO of s_axis_tvalid : signal is "xilinx.com:interface:axis:1.0 S_AXIS TVALID";
    attribute X_INTERFACE_INFO of s_axis_tready : signal is "xilinx.com:interface:axis:1.0 S_AXIS TREADY";
    attribute X_INTERFACE_INFO of pulse_start_i : signal is "xilinx.com:signal:data:1.0 PULSE_START DATA";
    attribute X_INTERFACE_INFO of s_axi_awaddr : signal is "xilinx.com:interface:aximm:1.0 S_AXI AWADDR";
    attribute X_INTERFACE_INFO of s_axi_awprot : signal is "xilinx.com:interface:aximm:1.0 S_AXI AWPROT";
    attribute X_INTERFACE_INFO of s_axi_awvalid : signal is "xilinx.com:interface:aximm:1.0 S_AXI AWVALID";
    attribute X_INTERFACE_INFO of s_axi_awready : signal is "xilinx.com:interface:aximm:1.0 S_AXI AWREADY";
    attribute X_INTERFACE_INFO of s_axi_wdata : signal is "xilinx.com:interface:aximm:1.0 S_AXI WDATA";
    attribute X_INTERFACE_INFO of s_axi_wstrb : signal is "xilinx.com:interface:aximm:1.0 S_AXI WSTRB";
    attribute X_INTERFACE_INFO of s_axi_wvalid : signal is "xilinx.com:interface:aximm:1.0 S_AXI WVALID";
    attribute X_INTERFACE_INFO of s_axi_wready : signal is "xilinx.com:interface:aximm:1.0 S_AXI WREADY";
    attribute X_INTERFACE_INFO of s_axi_bresp : signal is "xilinx.com:interface:aximm:1.0 S_AXI BRESP";
    attribute X_INTERFACE_INFO of s_axi_bvalid : signal is "xilinx.com:interface:aximm:1.0 S_AXI BVALID";
    attribute X_INTERFACE_INFO of s_axi_bready : signal is "xilinx.com:interface:aximm:1.0 S_AXI BREADY";
    attribute X_INTERFACE_INFO of s_axi_araddr : signal is "xilinx.com:interface:aximm:1.0 S_AXI ARADDR";
    attribute X_INTERFACE_INFO of s_axi_arprot : signal is "xilinx.com:interface:aximm:1.0 S_AXI ARPROT";
    attribute X_INTERFACE_INFO of s_axi_arvalid : signal is "xilinx.com:interface:aximm:1.0 S_AXI ARVALID";
    attribute X_INTERFACE_INFO of s_axi_arready : signal is "xilinx.com:interface:aximm:1.0 S_AXI ARREADY";
    attribute X_INTERFACE_INFO of s_axi_rdata : signal is "xilinx.com:interface:aximm:1.0 S_AXI RDATA";
    attribute X_INTERFACE_INFO of s_axi_rresp : signal is "xilinx.com:interface:aximm:1.0 S_AXI RRESP";
    attribute X_INTERFACE_INFO of s_axi_rvalid : signal is "xilinx.com:interface:aximm:1.0 S_AXI RVALID";
    attribute X_INTERFACE_INFO of s_axi_rready : signal is "xilinx.com:interface:aximm:1.0 S_AXI RREADY";
    attribute X_INTERFACE_PARAMETER of s_axi_awaddr : signal is
        "XIL_INTERFACENAME S_AXI, DATA_WIDTH 32, PROTOCOL AXI4LITE, ADDR_WIDTH 7";
end entity;

architecture rtl of acoustic_pcm_iq_tracker is
    constant C_OK : std_logic_vector(1 downto 0) := "00";
    constant C_SLVERR : std_logic_vector(1 downto 0) := "10";
    constant C_SHIFT : natural := 18;
    constant C_ONE_Q32 : unsigned(63 downto 0) := x"0000000100000000";
    type accum_array_t is array (0 to 3) of signed(51 downto 0);
    type word_array_t is array (0 to 3) of std_logic_vector(31 downto 0);
    type level_array_t is array (0 to 3) of natural range 0 to 16777215;
    type pcm_sample_array_t is array (0 to 3) of signed(23 downto 0);
    type dc_estimate_array_t is array (0 to 3) of signed(24 downto 0);
    type onset_count_array_t is array (0 to 3) of natural range 0 to 3;
    type sine_lut_t is array (0 to 256) of signed(15 downto 0);
    constant QUARTER_SINE_Q15 : sine_lut_t := (
        to_signed(0, 16),
        to_signed(201, 16),
        to_signed(402, 16),
        to_signed(603, 16),
        to_signed(804, 16),
        to_signed(1005, 16),
        to_signed(1206, 16),
        to_signed(1407, 16),
        to_signed(1608, 16),
        to_signed(1809, 16),
        to_signed(2009, 16),
        to_signed(2210, 16),
        to_signed(2410, 16),
        to_signed(2611, 16),
        to_signed(2811, 16),
        to_signed(3012, 16),
        to_signed(3212, 16),
        to_signed(3412, 16),
        to_signed(3612, 16),
        to_signed(3811, 16),
        to_signed(4011, 16),
        to_signed(4210, 16),
        to_signed(4410, 16),
        to_signed(4609, 16),
        to_signed(4808, 16),
        to_signed(5007, 16),
        to_signed(5205, 16),
        to_signed(5404, 16),
        to_signed(5602, 16),
        to_signed(5800, 16),
        to_signed(5998, 16),
        to_signed(6195, 16),
        to_signed(6393, 16),
        to_signed(6590, 16),
        to_signed(6786, 16),
        to_signed(6983, 16),
        to_signed(7179, 16),
        to_signed(7375, 16),
        to_signed(7571, 16),
        to_signed(7767, 16),
        to_signed(7962, 16),
        to_signed(8157, 16),
        to_signed(8351, 16),
        to_signed(8545, 16),
        to_signed(8739, 16),
        to_signed(8933, 16),
        to_signed(9126, 16),
        to_signed(9319, 16),
        to_signed(9512, 16),
        to_signed(9704, 16),
        to_signed(9896, 16),
        to_signed(10087, 16),
        to_signed(10278, 16),
        to_signed(10469, 16),
        to_signed(10659, 16),
        to_signed(10849, 16),
        to_signed(11039, 16),
        to_signed(11228, 16),
        to_signed(11417, 16),
        to_signed(11605, 16),
        to_signed(11793, 16),
        to_signed(11980, 16),
        to_signed(12167, 16),
        to_signed(12353, 16),
        to_signed(12539, 16),
        to_signed(12725, 16),
        to_signed(12910, 16),
        to_signed(13094, 16),
        to_signed(13279, 16),
        to_signed(13462, 16),
        to_signed(13645, 16),
        to_signed(13828, 16),
        to_signed(14010, 16),
        to_signed(14191, 16),
        to_signed(14372, 16),
        to_signed(14553, 16),
        to_signed(14732, 16),
        to_signed(14912, 16),
        to_signed(15090, 16),
        to_signed(15269, 16),
        to_signed(15446, 16),
        to_signed(15623, 16),
        to_signed(15800, 16),
        to_signed(15976, 16),
        to_signed(16151, 16),
        to_signed(16325, 16),
        to_signed(16499, 16),
        to_signed(16673, 16),
        to_signed(16846, 16),
        to_signed(17018, 16),
        to_signed(17189, 16),
        to_signed(17360, 16),
        to_signed(17530, 16),
        to_signed(17700, 16),
        to_signed(17869, 16),
        to_signed(18037, 16),
        to_signed(18204, 16),
        to_signed(18371, 16),
        to_signed(18537, 16),
        to_signed(18703, 16),
        to_signed(18868, 16),
        to_signed(19032, 16),
        to_signed(19195, 16),
        to_signed(19357, 16),
        to_signed(19519, 16),
        to_signed(19680, 16),
        to_signed(19841, 16),
        to_signed(20000, 16),
        to_signed(20159, 16),
        to_signed(20317, 16),
        to_signed(20475, 16),
        to_signed(20631, 16),
        to_signed(20787, 16),
        to_signed(20942, 16),
        to_signed(21096, 16),
        to_signed(21250, 16),
        to_signed(21403, 16),
        to_signed(21554, 16),
        to_signed(21705, 16),
        to_signed(21856, 16),
        to_signed(22005, 16),
        to_signed(22154, 16),
        to_signed(22301, 16),
        to_signed(22448, 16),
        to_signed(22594, 16),
        to_signed(22739, 16),
        to_signed(22884, 16),
        to_signed(23027, 16),
        to_signed(23170, 16),
        to_signed(23311, 16),
        to_signed(23452, 16),
        to_signed(23592, 16),
        to_signed(23731, 16),
        to_signed(23870, 16),
        to_signed(24007, 16),
        to_signed(24143, 16),
        to_signed(24279, 16),
        to_signed(24413, 16),
        to_signed(24547, 16),
        to_signed(24680, 16),
        to_signed(24811, 16),
        to_signed(24942, 16),
        to_signed(25072, 16),
        to_signed(25201, 16),
        to_signed(25329, 16),
        to_signed(25456, 16),
        to_signed(25582, 16),
        to_signed(25708, 16),
        to_signed(25832, 16),
        to_signed(25955, 16),
        to_signed(26077, 16),
        to_signed(26198, 16),
        to_signed(26319, 16),
        to_signed(26438, 16),
        to_signed(26556, 16),
        to_signed(26674, 16),
        to_signed(26790, 16),
        to_signed(26905, 16),
        to_signed(27019, 16),
        to_signed(27133, 16),
        to_signed(27245, 16),
        to_signed(27356, 16),
        to_signed(27466, 16),
        to_signed(27575, 16),
        to_signed(27683, 16),
        to_signed(27790, 16),
        to_signed(27896, 16),
        to_signed(28001, 16),
        to_signed(28105, 16),
        to_signed(28208, 16),
        to_signed(28310, 16),
        to_signed(28411, 16),
        to_signed(28510, 16),
        to_signed(28609, 16),
        to_signed(28706, 16),
        to_signed(28803, 16),
        to_signed(28898, 16),
        to_signed(28992, 16),
        to_signed(29085, 16),
        to_signed(29177, 16),
        to_signed(29268, 16),
        to_signed(29358, 16),
        to_signed(29447, 16),
        to_signed(29534, 16),
        to_signed(29621, 16),
        to_signed(29706, 16),
        to_signed(29791, 16),
        to_signed(29874, 16),
        to_signed(29956, 16),
        to_signed(30037, 16),
        to_signed(30117, 16),
        to_signed(30195, 16),
        to_signed(30273, 16),
        to_signed(30349, 16),
        to_signed(30424, 16),
        to_signed(30498, 16),
        to_signed(30571, 16),
        to_signed(30643, 16),
        to_signed(30714, 16),
        to_signed(30783, 16),
        to_signed(30852, 16),
        to_signed(30919, 16),
        to_signed(30985, 16),
        to_signed(31050, 16),
        to_signed(31113, 16),
        to_signed(31176, 16),
        to_signed(31237, 16),
        to_signed(31297, 16),
        to_signed(31356, 16),
        to_signed(31414, 16),
        to_signed(31470, 16),
        to_signed(31526, 16),
        to_signed(31580, 16),
        to_signed(31633, 16),
        to_signed(31685, 16),
        to_signed(31736, 16),
        to_signed(31785, 16),
        to_signed(31833, 16),
        to_signed(31880, 16),
        to_signed(31926, 16),
        to_signed(31971, 16),
        to_signed(32014, 16),
        to_signed(32057, 16),
        to_signed(32098, 16),
        to_signed(32137, 16),
        to_signed(32176, 16),
        to_signed(32213, 16),
        to_signed(32250, 16),
        to_signed(32285, 16),
        to_signed(32318, 16),
        to_signed(32351, 16),
        to_signed(32382, 16),
        to_signed(32412, 16),
        to_signed(32441, 16),
        to_signed(32469, 16),
        to_signed(32495, 16),
        to_signed(32521, 16),
        to_signed(32545, 16),
        to_signed(32567, 16),
        to_signed(32589, 16),
        to_signed(32609, 16),
        to_signed(32628, 16),
        to_signed(32646, 16),
        to_signed(32663, 16),
        to_signed(32678, 16),
        to_signed(32692, 16),
        to_signed(32705, 16),
        to_signed(32717, 16),
        to_signed(32728, 16),
        to_signed(32737, 16),
        to_signed(32745, 16),
        to_signed(32752, 16),
        to_signed(32757, 16),
        to_signed(32761, 16),
        to_signed(32765, 16),
        to_signed(32766, 16),
        to_signed(32767, 16)
    );

    function sine_q15(phase : unsigned(9 downto 0)) return signed is
        variable quadrant : natural range 0 to 3;
        variable index : natural range 0 to 255;
        variable lut_index : natural range 0 to 256;
        variable magnitude : signed(15 downto 0);
    begin
        quadrant := to_integer(phase(9 downto 8));
        index := to_integer(phase(7 downto 0));
        if quadrant = 0 or quadrant = 2 then lut_index := index;
        else lut_index := 256 - index;
        end if;
        magnitude := QUARTER_SINE_Q15(lut_index);
        if quadrant >= 2 then return -magnitude; end if;
        return magnitude;
    end function;

    function scaled_word(value : signed(51 downto 0)) return std_logic_vector is
        variable shifted : signed(51 downto 0);
        variable extension : signed(19 downto 0);
    begin
        shifted := shift_right(value, C_SHIFT);
        extension := (others => shifted(31));
        if shifted(51 downto 32) = extension then
            return std_logic_vector(shifted(31 downto 0));
        elsif shifted(51) = '0' then
            return x"7FFFFFFF";
        else
            return x"80000000";
        end if;
    end function;

    function merge_wstrb(old_value, new_value : std_logic_vector(31 downto 0);
                         strobes : std_logic_vector(3 downto 0)) return std_logic_vector is
        variable merged : std_logic_vector(31 downto 0) := old_value;
    begin
        for byte_index in 0 to 3 loop
            if strobes(byte_index) = '1' then
                merged(byte_index*8+7 downto byte_index*8) :=
                    new_value(byte_index*8+7 downto byte_index*8);
            end if;
        end loop;
        return merged;
    end function;

    function atan_constant(iteration : natural) return signed is
    begin
        case iteration is
            when 0 => return to_signed(210828714, 32);
            when 1 => return to_signed(124459457, 32);
            when 2 => return to_signed(65760959, 32);
            when 3 => return to_signed(33381290, 32);
            when 4 => return to_signed(16755422, 32);
            when 5 => return to_signed(8385879, 32);
            when 6 => return to_signed(4193963, 32);
            when 7 => return to_signed(2097109, 32);
            when 8 => return to_signed(1048571, 32);
            when 9 => return to_signed(524287, 32);
            when 10 => return to_signed(262144, 32);
            when 11 => return to_signed(131072, 32);
            when 12 => return to_signed(65536, 32);
            when 13 => return to_signed(32768, 32);
            when 14 => return to_signed(16384, 32);
            when 15 => return to_signed(8192, 32);
            when 16 => return to_signed(4096, 32);
            when 17 => return to_signed(2048, 32);
            when 18 => return to_signed(1024, 32);
            when 19 => return to_signed(512, 32);
            when 20 => return to_signed(256, 32);
            when 21 => return to_signed(128, 32);
            when 22 => return to_signed(64, 32);
            when 23 => return to_signed(32, 32);
            when others => return to_signed(16 / (2 ** (iteration - 24)), 32);
        end case;
    end function;

    function pixel_from_product(product : signed(42 downto 0);
                                center : unsigned(9 downto 0);
                                screen_y : boolean) return unsigned is
        variable offset : signed(31 downto 0);
        variable coordinate : signed(32 downto 0);
        variable center_signed : signed(32 downto 0);
    begin
        offset := resize(shift_right(product, 16), 32);
        center_signed := resize(signed('0' & center), 33);
        if screen_y then coordinate := center_signed - resize(offset, 33);
        else coordinate := center_signed + resize(offset, 33);
        end if;
        if coordinate < 0 then return to_unsigned(0, 10);
        elsif coordinate > 1023 then return to_unsigned(1023, 10);
        else return unsigned(coordinate(9 downto 0));
        end if;
    end function;

    function magnitude32(value : signed(31 downto 0)) return unsigned is
        variable extended : signed(32 downto 0);
        variable magnitude : unsigned(32 downto 0);
    begin
        extended := resize(value, 33);
        if extended < 0 then magnitude := unsigned(-extended);
        else magnitude := unsigned(extended); end if;
        return magnitude(31 downto 0);
    end function;

    signal axi_awready, axi_wready, axi_arready : std_logic;
    signal axi_bvalid, axi_rvalid : std_logic := '0';
    signal axi_bresp, axi_rresp : std_logic_vector(1 downto 0) := C_OK;
    signal axi_rdata : std_logic_vector(31 downto 0) := (others => '0');
    signal aw_pending, w_pending : std_logic := '0';
    signal awaddr_hold : std_logic_vector(C_S_AXI_ADDR_WIDTH-1 downto 0) := (others => '0');
    signal wdata_hold : std_logic_vector(31 downto 0) := (others => '0');
    signal wstrb_hold : std_logic_vector(3 downto 0) := (others => '0');
    signal enabled : std_logic := '0';
    signal pdoa_enabled : std_logic := '0';
    signal tdoa_enabled : std_logic := '0';
    signal phase_increment : unsigned(31 downto 0) := (others => '0');
    signal window_frames : unsigned(11 downto 0) := to_unsigned(128, 12);
    type threshold_array_t is array (0 to 3) of unsigned(23 downto 0);
    signal toa_threshold : threshold_array_t := (others => to_unsigned(50000, 24));
    signal min_iq_magnitude : unsigned(31 downto 0) := to_unsigned(25000, 32);
    signal toa_timeout_frames : unsigned(31 downto 0) := to_unsigned(24000, 32);
    signal pdoa_scale_x_q16 : signed(31 downto 0) := to_signed(46163, 32);
    signal pdoa_scale_y_q16 : signed(31 downto 0) := to_signed(46163, 32);
    signal tdoa_scale_x_q16 : signed(31 downto 0) := to_signed(9366, 32);
    signal tdoa_scale_y_q16 : signed(31 downto 0) := to_signed(9366, 32);
    signal pdoa_bias_x_q16, pdoa_bias_y_q16 : signed(31 downto 0) := (others => '0');
    signal tdoa_bias_x_q16, tdoa_bias_y_q16 : signed(31 downto 0) := (others => '0');
    signal pixel_center_x : unsigned(9 downto 0) := to_unsigned(320, 10);
    signal pixel_center_y : unsigned(9 downto 0) := to_unsigned(240, 10);
    signal pixels_per_sine_x : unsigned(9 downto 0) := to_unsigned(320, 10);
    signal pixels_per_sine_y : unsigned(9 downto 0) := to_unsigned(240, 10);
    signal clear_toggle : std_logic := '0';
    signal clear_seen : std_logic := '0';
    signal stream_error : std_logic := '0';
    signal result_valid : std_logic := '0';
    signal sequence_count : unsigned(23 downto 0) := (others => '0');
    signal result_i, result_q : word_array_t := (others => (others => '0'));
    signal sum_i, sum_q : accum_array_t := (others => (others => '0'));
    signal result_accum_i, result_accum_q : accum_array_t := (others => (others => '0'));
    signal result_pending : std_logic := '0';
    signal iq_s1_valid, iq_s2_valid, iq_s3_valid : std_logic := '0';
    signal iq_s1_sample, iq_s2_sample : signed(24 downto 0) := (others => '0');
    signal iq_s1_phase : unsigned(9 downto 0) := (others => '0');
    signal iq_s2_sine, iq_s2_cosine : signed(15 downto 0) := (others => '0');
    signal iq_s1_channel, iq_s2_channel, iq_s3_channel : natural range 0 to 3 := 0;
    signal iq_s1_window_end, iq_s2_window_end, iq_s3_window_end : std_logic := '0';
    signal iq_s3_product_i, iq_s3_product_q : signed(40 downto 0) := (others => '0');
    signal dc_estimate : dc_estimate_array_t := (others => (others => '0'));
    signal dc_sample_seen : std_logic_vector(3 downto 0) := (others => '0');
    signal phase_accumulator : unsigned(31 downto 0) := (others => '0');
    signal sample_count : natural range 0 to G_WINDOW_FRAMES-1 := 0;
    signal channel_index : natural range 0 to 3 := 0;
    signal collecting : std_logic := '0';
    signal cycle_counter : unsigned(63 downto 0) := (others => '0');
    signal frame_counter : unsigned(63 downto 0) := (others => '0');
    signal last_frame_cycle : unsigned(63 downto 0) := (others => '0');
    signal trigger_count : unsigned(31 downto 0) := (others => '0');
    signal trigger_frame : unsigned(63 downto 0) := (others => '0');
    signal trigger_cycle : unsigned(63 downto 0) := (others => '0');
    signal trigger_last_frame_cycle : unsigned(63 downto 0) := (others => '0');
    signal pulse_start_previous : std_logic := '0';
    type pdoa_state_t is (
        P_IDLE, P_LOAD_PAIR, P_PAIR_PRODUCTS, P_PAIR_DOT, P_PAIR_SEED,
        P_ITERATE, P_DIFF_PHASES, P_WRAP_FLAGS,
        P_ADJUST_PHASES, P_AVERAGE_PHASES, P_PHASE_NORM_FLAGS,
        P_PHASE_NORMALIZE, P_SCALE_PARTIALS, P_SCALE_SUM_LO,
        P_SCALE_SUM_HI, P_SCALE, P_NORM_X, P_NORM_Y, P_NORM_SUM,
        P_QUALITY, P_PIXEL_PRODUCT, P_PIXEL_COORD, P_VALIDATE);
    type iq_result_array_t is array (0 to 3) of signed(31 downto 0);
    type angle_array_t is array (0 to 3) of signed(31 downto 0);
    signal pdoa_state : pdoa_state_t := P_IDLE;
    signal pdoa_i, pdoa_q : iq_result_array_t := (others => (others => '0'));
    signal pdoa_pair_angles : angle_array_t := (others => (others => '0'));
    signal pdoa_pair_a_i, pdoa_pair_a_q, pdoa_pair_b_i, pdoa_pair_b_q : signed(31 downto 0) := (others => '0');
    signal pdoa_dot_ii, pdoa_dot_qq, pdoa_cross_iq, pdoa_cross_qi : signed(63 downto 0) := (others => '0');
    signal pdoa_pair_dot, pdoa_pair_cross : signed(64 downto 0) := (others => '0');
    signal pdoa_pair_index : natural range 0 to 3 := 0;
    signal pdoa_iteration : natural range 0 to 24 := 0;
    signal pdoa_cordic_x, pdoa_cordic_y : signed(64 downto 0) := (others => '0');
    signal pdoa_cordic_z : signed(31 downto 0) := (others => '0');
    signal pdoa_seq_seen : unsigned(23 downto 0) := (others => '0');
    signal pdoa_result_sequence : unsigned(23 downto 0) := (others => '0');
    signal pdoa_clear_seen : std_logic := '0';
    signal pdoa_valid : std_logic := '0';
    signal pdoa_pair_diff_x, pdoa_pair_diff_y : signed(32 downto 0) := (others => '0');
    signal pdoa_wrap_x_pos, pdoa_wrap_x_neg, pdoa_wrap_y_pos, pdoa_wrap_y_neg : std_logic := '0';
    signal pdoa_right_adjusted_x, pdoa_right_adjusted_y : signed(32 downto 0) := (others => '0');
    signal pdoa_phase_sum_x, pdoa_phase_sum_y : signed(33 downto 0) := (others => '0');
    signal pdoa_phase_raw_x, pdoa_phase_raw_y : signed(31 downto 0) := (others => '0');
    signal pdoa_phase_norm_x_pos, pdoa_phase_norm_x_neg,
           pdoa_phase_norm_y_pos, pdoa_phase_norm_y_neg : std_logic := '0';
    signal pdoa_phase_x, pdoa_phase_y : signed(31 downto 0) := (others => '0');
    signal pdoa_dir_x_q16, pdoa_dir_y_q16 : signed(31 downto 0) := (others => '0');
    signal pdoa_mul_x_ll, pdoa_mul_y_ll : signed(33 downto 0) := (others => '0');
    signal pdoa_mul_x_hl, pdoa_mul_x_lh, pdoa_mul_y_hl, pdoa_mul_y_lh : signed(32 downto 0) := (others => '0');
    signal pdoa_mul_x_hh, pdoa_mul_y_hh : signed(31 downto 0) := (others => '0');
    signal pdoa_mul_accum_x, pdoa_mul_accum_y : signed(63 downto 0) := (others => '0');
    signal pdoa_norm_x, pdoa_norm_y, pdoa_norm : unsigned(63 downto 0) := (others => '0');
    signal pdoa_quality_ok : std_logic := '0';
    signal pdoa_pixel_product_x, pdoa_pixel_product_y : signed(42 downto 0) := (others => '0');
    signal pdoa_pixel_x, pdoa_pixel_y : unsigned(9 downto 0) := (others => '0');
    type arrival_array_t is array (0 to 3) of unsigned(31 downto 0);
    signal toa_armed : std_logic := '0';
    -- Defer the transition into the multi-bit TDoA FSM by one clock after
    -- the channel threshold gate completes, shortening that control path.
    signal toa_capture_pending : std_logic := '0';
    signal toa_pulse_previous : std_logic := '0';
    signal toa_seen : std_logic_vector(3 downto 0) := (others => '0');
    signal toa_arrival : arrival_array_t := (others => (others => '0'));
    signal toa_previous_sample : pcm_sample_array_t := (others => (others => '0'));
    signal toa_previous_valid : std_logic_vector(3 downto 0) := (others => '0');
    signal toa_envelope, toa_baseline : level_array_t := (others => 0);
    -- Pipeline the ToA first-difference and envelope smoother. Keeping the
    -- subtraction/absolute-value, EMA delta and EMA update in separate cycles
    -- avoids a long multi-adder path on the 100 MHz PCM stream.
    signal toa_diff_pending_valid, toa_step_pending_valid : std_logic := '0';
    signal toa_diff_pending_channel, toa_step_pending_channel : natural range 0 to 3 := 0;
    signal toa_diff_pending : unsigned(23 downto 0) := (others => '0');
    signal toa_step_pending_base, toa_step_pending : unsigned(23 downto 0) := (others => '0');
    signal toa_step_pending_increase : std_logic := '0';
    signal toa_crossing_count : onset_count_array_t := (others => 0);
    signal toa_trigger_frame : unsigned(63 downto 0) := (others => '0');
    signal tdoa_hold_frames : unsigned(31 downto 0) := to_unsigned(4800, 32);
    signal tdoa_result_frame : unsigned(63 downto 0) := (others => '0');
    signal toa_clear_seen : std_logic := '0';
    type tdoa_compute_state_t is
        (T_IDLE, T_WAIT_FRAME, T_CAPTURE, T_CORRELATE, T_MULTIPLY, T_ACCUM, T_COMPARE,
         T_DELTA_SUM, T_SCALE_PARTIALS, T_SCALE_SUM, T_SCALE,
         T_PROJECT_X_PRODUCT, T_PROJECT_X, T_PROJECT_Y_PRODUCT, T_PROJECT_Y,
         T_NORM_X, T_NORM_Y, T_VALIDATE);
    type tdoa_pair_array_t is array (0 to 3) of signed(32 downto 0);
    -- First differences remove the large PCM DC offset. A 64-frame window
    -- contains several cycles of the 2.54 kHz test tone; one multiplier scans
    -- four pairs and the bounded lag range after capture.
    type tdoa_sample_array_t is array (0 to 3, 0 to 63) of signed(24 downto 0);
    signal tdoa_samples : tdoa_sample_array_t;
    signal tdoa_capture_index : natural range 0 to 63 := 0;
    signal tdoa_pair_index : natural range 0 to 3 := 0;
    signal tdoa_lag : integer range -8 to 8 := -8;
    signal tdoa_sample_index : natural range 8 to 55 := 8;
    signal tdoa_operand_a, tdoa_operand_b : signed(24 downto 0) := (others => '0');
    signal tdoa_product : signed(49 downto 0) := (others => '0');
    signal tdoa_correlation, tdoa_best_correlation : signed(63 downto 0) := (others => '0');
    signal tdoa_best_lag : integer range -8 to 8 := 0;
    signal tdoa_quality_ok : std_logic := '0';
    signal tdoa_compute_state : tdoa_compute_state_t := T_IDLE;
    signal tdoa_pair_delta : tdoa_pair_array_t := (others => (others => '0'));
    signal tdoa_norm_x, tdoa_norm_y : unsigned(63 downto 0) := (others => '0');
    signal tdoa_valid : std_logic := '0';
    signal tdoa_event_count : unsigned(31 downto 0) := (others => '0');
    signal tdoa_delta_x_frames, tdoa_delta_y_frames : signed(31 downto 0) := (others => '0');
    signal tdoa_dir_x_q16, tdoa_dir_y_q16 : signed(31 downto 0) := (others => '0');
    signal tdoa_mul_x_ll, tdoa_mul_y_ll : unsigned(31 downto 0) := (others => '0');
    signal tdoa_mul_x_hl, tdoa_mul_x_lh, tdoa_mul_y_hl, tdoa_mul_y_lh : unsigned(15 downto 0) := (others => '0');
    signal tdoa_mul_accum_x, tdoa_mul_accum_y : unsigned(15 downto 0) := (others => '0');
    signal tdoa_pixel_product_x, tdoa_pixel_product_y : signed(42 downto 0) := (others => '0');
    signal tdoa_pixel_center_x, tdoa_pixel_center_y : unsigned(9 downto 0) := (others => '0');
    signal tdoa_pixels_per_sine_x : unsigned(9 downto 0) := to_unsigned(320, 10);
    signal tdoa_pixels_per_sine_y : unsigned(9 downto 0) := to_unsigned(240, 10);
    signal tdoa_pixel_x, tdoa_pixel_y : unsigned(9 downto 0) := (others => '0');
    attribute ASYNC_REG : string;
begin
    s_axis_tready <= '1';
    s_axi_awready <= axi_awready;
    s_axi_wready <= axi_wready;
    s_axi_bresp <= axi_bresp;
    s_axi_bvalid <= axi_bvalid;
    s_axi_arready <= axi_arready;
    s_axi_rdata <= axi_rdata;
    s_axi_rresp <= axi_rresp;
    s_axi_rvalid <= axi_rvalid;

    axi_awready <= '1' when aresetn = '1' and aw_pending = '0' and axi_bvalid = '0' else '0';
    axi_wready <= '1' when aresetn = '1' and w_pending = '0' and axi_bvalid = '0' else '0';
    axi_arready <= '1' when aresetn = '1' and axi_rvalid = '0' else '0';

    -- Runtime map is documented in docs/PL_PDOA_TDOA.md. Processing and
    -- coordinate projection stay in this PL block; PS only writes config and
    -- reads results. PCM continues through the DMA tap without reordering.
    process(aclk)
        variable write_addr, read_addr : natural;
        variable command, read_word : std_logic_vector(31 downto 0);
        variable write_error, read_error : boolean;
    begin
        if rising_edge(aclk) then
            if aresetn = '0' then
                axi_bvalid <= '0'; axi_bresp <= C_OK;
                axi_rvalid <= '0'; axi_rresp <= C_OK; axi_rdata <= (others => '0');
                aw_pending <= '0'; awaddr_hold <= (others => '0');
                w_pending <= '0'; wdata_hold <= (others => '0'); wstrb_hold <= (others => '0');
                enabled <= '0'; pdoa_enabled <= '0'; tdoa_enabled <= '0';
                phase_increment <= (others => '0'); clear_toggle <= '0';
                window_frames <= to_unsigned(128, 12);
                toa_threshold <= (others => to_unsigned(50000, 24));
                min_iq_magnitude <= to_unsigned(25000, 32);
                toa_timeout_frames <= to_unsigned(24000, 32);
                tdoa_hold_frames <= to_unsigned(4800, 32);
                pdoa_scale_x_q16 <= to_signed(46163, 32);
                pdoa_scale_y_q16 <= to_signed(46163, 32);
                tdoa_scale_x_q16 <= to_signed(9366, 32);
                tdoa_scale_y_q16 <= to_signed(9366, 32);
                pdoa_bias_x_q16 <= (others => '0');
                pdoa_bias_y_q16 <= (others => '0');
                tdoa_bias_x_q16 <= (others => '0');
                tdoa_bias_y_q16 <= (others => '0');
                pixel_center_x <= to_unsigned(320, 10);
                pixel_center_y <= to_unsigned(240, 10);
                pixels_per_sine_x <= to_unsigned(320, 10);
                pixels_per_sine_y <= to_unsigned(240, 10);
            else
                if axi_bvalid = '1' and s_axi_bready = '1' then axi_bvalid <= '0'; end if;
                if s_axi_awvalid = '1' and axi_awready = '1' then
                    awaddr_hold <= s_axi_awaddr; aw_pending <= '1';
                end if;
                if s_axi_wvalid = '1' and axi_wready = '1' then
                    wdata_hold <= s_axi_wdata; wstrb_hold <= s_axi_wstrb; w_pending <= '1';
                end if;
                if aw_pending = '1' and w_pending = '1' and axi_bvalid = '0' then
                    write_addr := to_integer(unsigned(awaddr_hold));
                    write_error := (write_addr mod 4) /= 0;
                    axi_bresp <= C_OK;
                    if not write_error then
                        case write_addr is
                            when 16#00# =>
                                command := merge_wstrb(x"00000000", wdata_hold, wstrb_hold);
                                enabled <= command(0);
                                pdoa_enabled <= command(2);
                                tdoa_enabled <= command(3);
                                if command(1) = '1' then clear_toggle <= not clear_toggle; end if;
                            when 16#04# =>
                                phase_increment <= unsigned(merge_wstrb(
                                    std_logic_vector(phase_increment), wdata_hold, wstrb_hold));
                            when 16#0C# =>
                                command := merge_wstrb(x"00000000", wdata_hold, wstrb_hold);
                                if unsigned(command) >= 16 and unsigned(command) <= G_WINDOW_FRAMES then
                                    window_frames <= unsigned(command(11 downto 0));
                                else
                                    write_error := true;
                                end if;
                            when 16#54# | 16#58# | 16#5C# | 16#60# =>
                                command := merge_wstrb(x"00000000", wdata_hold, wstrb_hold);
                                if command(31 downto 24) = x"00" then
                                    toa_threshold((write_addr - 16#54#) / 4) <= unsigned(command(23 downto 0));
                                else
                                    write_error := true;
                                end if;
                            when 16#64# =>
                                min_iq_magnitude <= unsigned(merge_wstrb(
                                    std_logic_vector(min_iq_magnitude), wdata_hold, wstrb_hold));
                            when 16#68# =>
                                toa_timeout_frames <= unsigned(merge_wstrb(
                                    std_logic_vector(toa_timeout_frames), wdata_hold, wstrb_hold));
                            when 16#C8# =>
                                tdoa_hold_frames <= unsigned(merge_wstrb(
                                    std_logic_vector(tdoa_hold_frames), wdata_hold, wstrb_hold));
                            when 16#6C# => pdoa_scale_x_q16 <= signed(merge_wstrb(
                                std_logic_vector(pdoa_scale_x_q16), wdata_hold, wstrb_hold));
                            when 16#70# => pdoa_scale_y_q16 <= signed(merge_wstrb(
                                std_logic_vector(pdoa_scale_y_q16), wdata_hold, wstrb_hold));
                            when 16#74# => tdoa_scale_x_q16 <= signed(merge_wstrb(
                                std_logic_vector(tdoa_scale_x_q16), wdata_hold, wstrb_hold));
                            when 16#78# => tdoa_scale_y_q16 <= signed(merge_wstrb(
                                std_logic_vector(tdoa_scale_y_q16), wdata_hold, wstrb_hold));
                            when 16#E4# => pdoa_bias_x_q16 <= signed(merge_wstrb(
                                std_logic_vector(pdoa_bias_x_q16), wdata_hold, wstrb_hold));
                            when 16#E8# => pdoa_bias_y_q16 <= signed(merge_wstrb(
                                std_logic_vector(pdoa_bias_y_q16), wdata_hold, wstrb_hold));
                            when 16#EC# => tdoa_bias_x_q16 <= signed(merge_wstrb(
                                std_logic_vector(tdoa_bias_x_q16), wdata_hold, wstrb_hold));
                            when 16#F0# => tdoa_bias_y_q16 <= signed(merge_wstrb(
                                std_logic_vector(tdoa_bias_y_q16), wdata_hold, wstrb_hold));
                            when 16#7C# =>
                                command := merge_wstrb(x"00000000", wdata_hold, wstrb_hold);
                                if command(31 downto 10) = (21 downto 0 => '0') then
                                    pixel_center_x <= unsigned(command(9 downto 0));
                                else
                                    write_error := true;
                                end if;
                            when 16#80# =>
                                command := merge_wstrb(x"00000000", wdata_hold, wstrb_hold);
                                if command(31 downto 10) = (21 downto 0 => '0') then
                                    pixel_center_y <= unsigned(command(9 downto 0));
                                else
                                    write_error := true;
                                end if;
                            when 16#84# =>
                                command := merge_wstrb(x"00000000", wdata_hold, wstrb_hold);
                                if command(31 downto 10) = (21 downto 0 => '0') then
                                    pixels_per_sine_x <= unsigned(command(9 downto 0));
                                else
                                    write_error := true;
                                end if;
                            when 16#88# =>
                                command := merge_wstrb(x"00000000", wdata_hold, wstrb_hold);
                                if command(31 downto 10) = (21 downto 0 => '0') then
                                    pixels_per_sine_y <= unsigned(command(9 downto 0));
                                else
                                    write_error := true;
                                end if;
                            when others => write_error := true;
                        end case;
                    end if;
                    if write_error then axi_bresp <= C_SLVERR; end if;
                    axi_bvalid <= '1'; aw_pending <= '0'; w_pending <= '0';
                end if;
                if axi_rvalid = '1' and s_axi_rready = '1' then axi_rvalid <= '0'; end if;
                if s_axi_arvalid = '1' and axi_arready = '1' then
                    read_addr := to_integer(unsigned(s_axi_araddr));
                    read_word := (others => '0'); read_error := (read_addr mod 4) /= 0;
                    if not read_error then
                        case read_addr is
                            when 16#00# => read_word(0) := enabled;
                            when 16#04# => read_word := std_logic_vector(phase_increment);
                            when 16#08# =>
                                read_word(0) := enabled;
                                read_word(1) := result_valid;
                                read_word(2) := stream_error;
                                read_word(3) := pdoa_enabled;
                                read_word(4) := tdoa_enabled;
                                read_word(31 downto 8) := std_logic_vector(sequence_count);
                            when 16#0C# => read_word := std_logic_vector(resize(window_frames, 32));
                            when 16#10# => read_word := result_i(0);
                            when 16#14# => read_word := result_q(0);
                            when 16#18# => read_word := result_i(1);
                            when 16#1C# => read_word := result_q(1);
                            when 16#20# => read_word := result_i(2);
                            when 16#24# => read_word := result_q(2);
                            when 16#28# => read_word := result_i(3);
                            when 16#2C# => read_word := result_q(3);
                            when 16#30# => read_word := std_logic_vector(frame_counter(31 downto 0));
                            when 16#34# => read_word := std_logic_vector(frame_counter(63 downto 32));
                            when 16#38# => read_word := std_logic_vector(trigger_count);
                            when 16#3C# => read_word := std_logic_vector(trigger_frame(31 downto 0));
                            when 16#40# => read_word := std_logic_vector(trigger_frame(63 downto 32));
                            when 16#44# => read_word := std_logic_vector(trigger_cycle(31 downto 0));
                            when 16#48# => read_word := std_logic_vector(trigger_cycle(63 downto 32));
                            when 16#4C# => read_word := std_logic_vector(trigger_last_frame_cycle(31 downto 0));
                            when 16#50# => read_word := std_logic_vector(trigger_last_frame_cycle(63 downto 32));
                            when 16#54# | 16#58# | 16#5C# | 16#60# =>
                                read_word := std_logic_vector(resize(
                                    toa_threshold((read_addr - 16#54#) / 4), 32));
                            when 16#64# => read_word := std_logic_vector(min_iq_magnitude);
                            when 16#68# => read_word := std_logic_vector(toa_timeout_frames);
                            when 16#6C# => read_word := std_logic_vector(pdoa_scale_x_q16);
                            when 16#70# => read_word := std_logic_vector(pdoa_scale_y_q16);
                            when 16#74# => read_word := std_logic_vector(tdoa_scale_x_q16);
                            when 16#78# => read_word := std_logic_vector(tdoa_scale_y_q16);
                            when 16#7C# => read_word := std_logic_vector(resize(pixel_center_x, 32));
                            when 16#80# => read_word := std_logic_vector(resize(pixel_center_y, 32));
                            when 16#84# => read_word := std_logic_vector(resize(pixels_per_sine_x, 32));
                            when 16#88# => read_word := std_logic_vector(resize(pixels_per_sine_y, 32));
                            when 16#8C# =>
                                read_word(0) := pdoa_valid;
                                read_word(1) := pdoa_enabled;
                            when 16#90# => read_word := std_logic_vector(pdoa_dir_x_q16);
                            when 16#94# => read_word := std_logic_vector(pdoa_dir_y_q16);
                            when 16#98# =>
                                read_word(9 downto 0) := std_logic_vector(pdoa_pixel_x);
                                read_word(19 downto 10) := std_logic_vector(pdoa_pixel_y);
                            when 16#9C# =>
                                read_word(0) := tdoa_valid;
                                read_word(1) := tdoa_enabled;
                                read_word(31 downto 2) := std_logic_vector(tdoa_event_count(29 downto 0));
                            when 16#A0# => read_word := std_logic_vector(tdoa_dir_x_q16);
                            when 16#A4# => read_word := std_logic_vector(tdoa_dir_y_q16);
                            when 16#A8# =>
                                read_word(9 downto 0) := std_logic_vector(tdoa_pixel_x);
                                read_word(19 downto 10) := std_logic_vector(tdoa_pixel_y);
                            when 16#AC# | 16#B0# | 16#B4# | 16#B8# =>
                                read_word := std_logic_vector(toa_arrival((read_addr - 16#AC#) / 4));
                            when 16#BC# => read_word := std_logic_vector(tdoa_delta_x_frames);
                            when 16#C0# => read_word := std_logic_vector(tdoa_delta_y_frames);
                            when 16#C4# => read_word := std_logic_vector(tdoa_event_count);
                            when 16#C8# => read_word := std_logic_vector(tdoa_hold_frames);
                            when 16#CC# | 16#D0# | 16#D4# | 16#D8# =>
                                read_word := std_logic_vector(resize(
                                    tdoa_pair_delta((read_addr - 16#CC#) / 4), 32));
                            when 16#DC# => read_word(0) := tdoa_quality_ok;
                            when 16#E0# => read_word := x"54444F31"; -- TDO1 correlation map
                            when 16#E4# => read_word := std_logic_vector(pdoa_bias_x_q16);
                            when 16#E8# => read_word := std_logic_vector(pdoa_bias_y_q16);
                            when 16#EC# => read_word := std_logic_vector(tdoa_bias_x_q16);
                            when 16#F0# => read_word := std_logic_vector(tdoa_bias_y_q16);
                            when 16#F4# => read_word := x"414F4132"; -- AOA2 bias/quality map
                            when 16#F8# =>
                                read_word(23 downto 0) := std_logic_vector(pdoa_result_sequence);
                            when 16#FC# => read_word := x"414F4133"; -- AOA3 completed PDoA sequence
                            when others => read_error := true;
                        end case;
                    end if;
                    axi_rdata <= read_word;
                    if read_error then axi_rresp <= C_SLVERR; else axi_rresp <= C_OK; end if;
                    axi_rvalid <= '1';
                end if;
            end if;
        end if;
    end process;

    -- The DDS address is captured with each PCM sample, then reference lookup,
    -- multiplication and accumulation run in separate cycles. All four channel
    -- samples retain their input order and share the phase held for that frame.
    process(aclk)
        variable phase_cos : unsigned(9 downto 0);
        variable next_i, next_q : signed(51 downto 0);
        variable sample_extended, dc_delta, dc_next, filtered_sample : signed(24 downto 0);
        variable capture_sample, window_end : boolean;
    begin
        if rising_edge(aclk) then
            if aresetn = '0' then
                clear_seen <= '0'; stream_error <= '0'; result_valid <= '0';
                sequence_count <= (others => '0'); result_i <= (others => (others => '0'));
                result_q <= (others => (others => '0'));
                sum_i <= (others => (others => '0')); sum_q <= (others => (others => '0'));
                result_accum_i <= (others => (others => '0'));
                result_accum_q <= (others => (others => '0')); result_pending <= '0';
                iq_s1_valid <= '0'; iq_s2_valid <= '0'; iq_s3_valid <= '0';
                iq_s1_sample <= (others => '0'); iq_s2_sample <= (others => '0');
                iq_s1_phase <= (others => '0'); iq_s2_sine <= (others => '0');
                iq_s2_cosine <= (others => '0'); iq_s1_channel <= 0;
                iq_s2_channel <= 0; iq_s3_channel <= 0;
                iq_s1_window_end <= '0'; iq_s2_window_end <= '0'; iq_s3_window_end <= '0';
                iq_s3_product_i <= (others => '0'); iq_s3_product_q <= (others => '0');
                phase_accumulator <= (others => '0'); sample_count <= 0;
                dc_estimate <= (others => (others => '0')); dc_sample_seen <= (others => '0');
                channel_index <= 0; collecting <= '0';
                cycle_counter <= (others => '0'); frame_counter <= (others => '0');
                last_frame_cycle <= (others => '0'); trigger_count <= (others => '0');
                trigger_frame <= (others => '0'); trigger_cycle <= (others => '0');
                trigger_last_frame_cycle <= (others => '0'); pulse_start_previous <= '0';
            else
                cycle_counter <= cycle_counter + 1;
                pulse_start_previous <= pulse_start_i;
                if pulse_start_i = '1' and pulse_start_previous = '0' then
                    trigger_count <= trigger_count + 1;
                    trigger_frame <= frame_counter;
                    trigger_cycle <= cycle_counter;
                    trigger_last_frame_cycle <= last_frame_cycle;
                end if;

                -- Remove the slow PCM baseline before coherent I/Q integration.
                -- The same per-channel pole runs continuously, so the first
                -- measurement window does not include startup/DC transients.
                filtered_sample := (others => '0');
                if s_axis_tvalid = '1' then
                    sample_extended := resize(signed(s_axis_tdata(23 downto 0)), 25);
                    if dc_sample_seen(channel_index) = '0' then
                        dc_estimate(channel_index) <= sample_extended;
                        dc_sample_seen(channel_index) <= '1';
                    else
                        dc_delta := sample_extended - dc_estimate(channel_index);
                        dc_next := dc_estimate(channel_index) + shift_right(dc_delta, 8);
                        dc_estimate(channel_index) <= dc_next;
                        filtered_sample := sample_extended - dc_next;
                    end if;
                end if;

                if clear_toggle /= clear_seen then
                    clear_seen <= clear_toggle;
                    stream_error <= '0'; result_valid <= '0'; sequence_count <= (others => '0');
                    sum_i <= (others => (others => '0')); sum_q <= (others => (others => '0'));
                    result_accum_i <= (others => (others => '0'));
                    result_accum_q <= (others => (others => '0')); result_pending <= '0';
                    iq_s1_valid <= '0'; iq_s2_valid <= '0'; iq_s3_valid <= '0';
                    phase_accumulator <= (others => '0'); sample_count <= 0; collecting <= '0';
                else
                    -- Publish the wide snapshot one cycle after the final
                    -- accumulator update, keeping saturation out of the adder path.
                    if result_pending = '1' then
                        for channel in 0 to 3 loop
                            result_i(channel) <= scaled_word(result_accum_i(channel));
                            result_q(channel) <= scaled_word(result_accum_q(channel));
                        end loop;
                        result_valid <= '1';
                        sequence_count <= sequence_count + 1;
                    end if;
                    result_pending <= '0';

                    -- Stage 3: multiply the delayed sample by its delayed DDS reference.
                    iq_s3_valid <= iq_s2_valid;
                    if iq_s2_valid = '1' then
                        iq_s3_product_i <= iq_s2_sample * iq_s2_cosine;
                        iq_s3_product_q <= iq_s2_sample * (-iq_s2_sine);
                        iq_s3_channel <= iq_s2_channel;
                        iq_s3_window_end <= iq_s2_window_end;
                    end if;

                    -- Stage 2: quarter-wave lookup, separated from accumulation.
                    iq_s2_valid <= iq_s1_valid;
                    if iq_s1_valid = '1' then
                        phase_cos := iq_s1_phase + to_unsigned(256, 10);
                        iq_s2_sample <= iq_s1_sample;
                        iq_s2_sine <= sine_q15(iq_s1_phase);
                        iq_s2_cosine <= sine_q15(phase_cos);
                        iq_s2_channel <= iq_s1_channel;
                        iq_s2_window_end <= iq_s1_window_end;
                    end if;

                    -- Stage 4: one wide accumulation only. On a window boundary,
                    -- snapshot the completed values and clear before next channel 0.
                    if iq_s3_valid = '1' then
                        next_i := sum_i(iq_s3_channel) + resize(iq_s3_product_i, 52);
                        next_q := sum_q(iq_s3_channel) + resize(iq_s3_product_q, 52);
                        if iq_s3_window_end = '1' and iq_s3_channel = 3 then
                            result_accum_i(0) <= sum_i(0); result_accum_q(0) <= sum_q(0);
                            result_accum_i(1) <= sum_i(1); result_accum_q(1) <= sum_q(1);
                            result_accum_i(2) <= sum_i(2); result_accum_q(2) <= sum_q(2);
                            result_accum_i(3) <= next_i; result_accum_q(3) <= next_q;
                            result_pending <= '1';
                            sum_i <= (others => (others => '0'));
                            sum_q <= (others => (others => '0'));
                        else
                            sum_i(iq_s3_channel) <= next_i;
                            sum_q(iq_s3_channel) <= next_q;
                        end if;
                    end if;

                    -- Stage 1: capture sample, channel and phase address in order.
                    iq_s1_valid <= '0';
                    if s_axis_tvalid = '1' then
                        capture_sample := enabled = '1' and
                            (collecting = '1' or channel_index = 0);
                        if capture_sample then
                            iq_s1_valid <= '1';
                            iq_s1_sample <= filtered_sample;
                            iq_s1_phase <= phase_accumulator(31 downto 22);
                            iq_s1_channel <= channel_index;
                            window_end := channel_index = 3 and
                                collecting = '1' and
                                sample_count = to_integer(window_frames)-1;
                            if window_end then iq_s1_window_end <= '1';
                            else iq_s1_window_end <= '0'; end if;
                        end if;
                    end if;
                end if;

                if s_axis_tvalid = '1' then
                    if channel_index = 3 then
                        frame_counter <= frame_counter + 1;
                        last_frame_cycle <= cycle_counter;
                    end if;
                    if s_axis_tlast = '1' and channel_index /= 3 then
                        stream_error <= '1';
                    end if;
                    if clear_toggle = clear_seen and enabled = '1' then
                        if channel_index = 0 then collecting <= '1'; end if;
                        if channel_index = 3 and collecting = '1' then
                            if sample_count = to_integer(window_frames)-1 then
                                sample_count <= 0;
                            else sample_count <= sample_count + 1; end if;
                        end if;
                    end if;
                    -- AXI TLAST marks the end of each 4096-frame DMA
                    -- descriptor. A PCM frame is every four accepted words.
                    if channel_index = 3 and clear_toggle = clear_seen then
                        phase_accumulator <= phase_accumulator + phase_increment;
                    end if;
                    if s_axis_tlast = '1' then channel_index <= 0;
                    elsif channel_index = 3 then channel_index <= 0;
                    else channel_index <= channel_index + 1;
                    end if;
                end if;
            end if;
        end if;
    end process;

    -- PDoA phase extraction and fixed-point direction projection. Parameters
    -- are written by the PS, but phase and direction are calculated in PL.
    process(aclk)
        variable index_a, index_b : natural range 0 to 3;
        variable dot_value, cross_value : signed(64 downto 0);
        variable x_step, y_step : signed(64 downto 0);
        variable z_step : signed(31 downto 0);
        variable left_angle, right_angle : signed(32 downto 0);
        variable angle_sum : signed(33 downto 0);
        variable pi_value, two_pi_value : signed(32 downto 0);
        variable quality_ok : boolean;
    begin
        if rising_edge(aclk) then
            if aresetn = '0' then
                pdoa_state <= P_IDLE;
                pdoa_i <= (others => (others => '0'));
                pdoa_q <= (others => (others => '0'));
                pdoa_pair_angles <= (others => (others => '0'));
                pdoa_pair_a_i <= (others => '0'); pdoa_pair_a_q <= (others => '0');
                pdoa_pair_b_i <= (others => '0'); pdoa_pair_b_q <= (others => '0');
                pdoa_dot_ii <= (others => '0'); pdoa_dot_qq <= (others => '0');
                pdoa_cross_iq <= (others => '0'); pdoa_cross_qi <= (others => '0');
                pdoa_pair_dot <= (others => '0'); pdoa_pair_cross <= (others => '0');
                pdoa_pair_index <= 0; pdoa_iteration <= 0;
                pdoa_cordic_x <= (others => '0'); pdoa_cordic_y <= (others => '0');
                pdoa_cordic_z <= (others => '0'); pdoa_seq_seen <= (others => '0');
                pdoa_clear_seen <= '0'; pdoa_valid <= '0';
                pdoa_result_sequence <= (others => '0');
                pdoa_pair_diff_x <= (others => '0'); pdoa_pair_diff_y <= (others => '0');
                pdoa_wrap_x_pos <= '0'; pdoa_wrap_x_neg <= '0';
                pdoa_wrap_y_pos <= '0'; pdoa_wrap_y_neg <= '0';
                pdoa_right_adjusted_x <= (others => '0'); pdoa_right_adjusted_y <= (others => '0');
                pdoa_phase_sum_x <= (others => '0'); pdoa_phase_sum_y <= (others => '0');
                pdoa_phase_raw_x <= (others => '0'); pdoa_phase_raw_y <= (others => '0');
                pdoa_phase_norm_x_pos <= '0'; pdoa_phase_norm_x_neg <= '0';
                pdoa_phase_norm_y_pos <= '0'; pdoa_phase_norm_y_neg <= '0';
                pdoa_phase_x <= (others => '0'); pdoa_phase_y <= (others => '0');
                pdoa_dir_x_q16 <= (others => '0'); pdoa_dir_y_q16 <= (others => '0');
                pdoa_mul_x_ll <= (others => '0'); pdoa_mul_y_ll <= (others => '0');
                pdoa_mul_x_hl <= (others => '0'); pdoa_mul_x_lh <= (others => '0');
                pdoa_mul_y_hl <= (others => '0'); pdoa_mul_y_lh <= (others => '0');
                pdoa_mul_x_hh <= (others => '0'); pdoa_mul_y_hh <= (others => '0');
                pdoa_mul_accum_x <= (others => '0'); pdoa_mul_accum_y <= (others => '0');
                pdoa_norm_x <= (others => '0'); pdoa_norm_y <= (others => '0');
                pdoa_norm <= (others => '0'); pdoa_quality_ok <= '0';
                pdoa_pixel_product_x <= (others => '0'); pdoa_pixel_product_y <= (others => '0');
                pdoa_pixel_x <= to_unsigned(320, 10); pdoa_pixel_y <= to_unsigned(240, 10);
            else
                if clear_toggle /= pdoa_clear_seen then
                    pdoa_clear_seen <= clear_toggle;
                    pdoa_state <= P_IDLE; pdoa_seq_seen <= sequence_count;
                    pdoa_valid <= '0';
                    pdoa_result_sequence <= (others => '0');
                    pdoa_dir_x_q16 <= (others => '0'); pdoa_dir_y_q16 <= (others => '0');
                    pdoa_pixel_x <= pixel_center_x; pdoa_pixel_y <= pixel_center_y;
                elsif enabled = '0' or pdoa_enabled = '0' then
                    pdoa_state <= P_IDLE; pdoa_seq_seen <= sequence_count;
                    pdoa_valid <= '0';
                else
                    case pdoa_state is
                        when P_IDLE =>
                            if result_valid = '1' and sequence_count /= pdoa_seq_seen then
                                for channel in 0 to 3 loop
                                    pdoa_i(channel) <= signed(result_i(channel));
                                    pdoa_q(channel) <= signed(result_q(channel));
                                end loop;
                                pdoa_seq_seen <= sequence_count;
                                pdoa_pair_index <= 0;
                                pdoa_valid <= '0';
                                pdoa_state <= P_LOAD_PAIR;
                            end if;
                        when P_LOAD_PAIR =>
                            case pdoa_pair_index is
                                when 0 => index_a := 0; index_b := 1; -- Mic1 -> Mic2
                                when 1 => index_a := 2; index_b := 3; -- Mic3 -> Mic4
                                when 2 => index_a := 0; index_b := 2; -- Mic1 -> Mic3
                                when others => index_a := 1; index_b := 3; -- Mic2 -> Mic4
                            end case;
                            pdoa_pair_a_i <= pdoa_i(index_a);
                            pdoa_pair_a_q <= pdoa_q(index_a);
                            pdoa_pair_b_i <= pdoa_i(index_b);
                            pdoa_pair_b_q <= pdoa_q(index_b);
                            pdoa_state <= P_PAIR_PRODUCTS;
                        when P_PAIR_PRODUCTS =>
                            pdoa_dot_ii <= pdoa_pair_a_i * pdoa_pair_b_i;
                            pdoa_dot_qq <= pdoa_pair_a_q * pdoa_pair_b_q;
                            pdoa_cross_iq <= pdoa_pair_a_i * pdoa_pair_b_q;
                            pdoa_cross_qi <= pdoa_pair_a_q * pdoa_pair_b_i;
                            pdoa_state <= P_PAIR_DOT;
                        when P_PAIR_DOT =>
                            dot_value := resize(pdoa_dot_ii, 65) + resize(pdoa_dot_qq, 65);
                            cross_value := resize(pdoa_cross_iq, 65) - resize(pdoa_cross_qi, 65);
                            pdoa_pair_dot <= dot_value;
                            pdoa_pair_cross <= cross_value;
                            pdoa_state <= P_PAIR_SEED;
                        when P_PAIR_SEED =>
                            if pdoa_pair_dot = 0 and pdoa_pair_cross = 0 then
                                pdoa_pair_angles(pdoa_pair_index) <= (others => '0');
                                if pdoa_pair_index = 3 then pdoa_state <= P_DIFF_PHASES;
                                else pdoa_pair_index <= pdoa_pair_index + 1; end if;
                            else
                                if pdoa_pair_dot < 0 then
                                    if pdoa_pair_cross >= 0 then pdoa_cordic_z <= to_signed(843314857, 32);
                                    else pdoa_cordic_z <= to_signed(-843314857, 32); end if;
                                    pdoa_cordic_x <= -pdoa_pair_dot;
                                    pdoa_cordic_y <= -pdoa_pair_cross;
                                else
                                    pdoa_cordic_z <= (others => '0');
                                    pdoa_cordic_x <= pdoa_pair_dot;
                                    pdoa_cordic_y <= pdoa_pair_cross;
                                end if;
                                pdoa_iteration <= 0; pdoa_state <= P_ITERATE;
                            end if;
                        when P_ITERATE =>
                            x_step := pdoa_cordic_x;
                            y_step := pdoa_cordic_y;
                            z_step := pdoa_cordic_z;
                            if pdoa_cordic_y > 0 then
                                x_step := pdoa_cordic_x + shift_right(pdoa_cordic_y, pdoa_iteration);
                                y_step := pdoa_cordic_y - shift_right(pdoa_cordic_x, pdoa_iteration);
                                z_step := pdoa_cordic_z + atan_constant(pdoa_iteration);
                            elsif pdoa_cordic_y < 0 then
                                x_step := pdoa_cordic_x - shift_right(pdoa_cordic_y, pdoa_iteration);
                                y_step := pdoa_cordic_y + shift_right(pdoa_cordic_x, pdoa_iteration);
                                z_step := pdoa_cordic_z - atan_constant(pdoa_iteration);
                            end if;
                            if pdoa_cordic_y = 0 or pdoa_iteration = 24 then
                                pdoa_pair_angles(pdoa_pair_index) <= z_step;
                                if pdoa_pair_index = 3 then pdoa_state <= P_DIFF_PHASES;
                                else
                                    pdoa_pair_index <= pdoa_pair_index + 1;
                                    pdoa_state <= P_LOAD_PAIR;
                                end if;
                            else
                                pdoa_cordic_x <= x_step; pdoa_cordic_y <= y_step;
                                pdoa_cordic_z <= z_step;
                                pdoa_iteration <= pdoa_iteration + 1;
                            end if;
                        when P_DIFF_PHASES =>
                            left_angle := resize(pdoa_pair_angles(0), 33);
                            right_angle := resize(pdoa_pair_angles(1), 33);
                            pdoa_pair_diff_x <= left_angle - right_angle;
                            left_angle := resize(pdoa_pair_angles(2), 33);
                            right_angle := resize(pdoa_pair_angles(3), 33);
                            pdoa_pair_diff_y <= left_angle - right_angle;
                            pdoa_state <= P_WRAP_FLAGS;
                        when P_WRAP_FLAGS =>
                            pi_value := to_signed(843314857, 33);
                            pdoa_wrap_x_pos <= '0'; pdoa_wrap_x_neg <= '0';
                            pdoa_wrap_y_pos <= '0'; pdoa_wrap_y_neg <= '0';
                            if pdoa_pair_diff_x > pi_value then pdoa_wrap_x_pos <= '1';
                            elsif pdoa_pair_diff_x < -pi_value then pdoa_wrap_x_neg <= '1'; end if;
                            if pdoa_pair_diff_y > pi_value then pdoa_wrap_y_pos <= '1';
                            elsif pdoa_pair_diff_y < -pi_value then pdoa_wrap_y_neg <= '1'; end if;
                            pdoa_state <= P_ADJUST_PHASES;
                        when P_ADJUST_PHASES =>
                            two_pi_value := to_signed(1686629713, 33);
                            right_angle := resize(pdoa_pair_angles(1), 33);
                            if pdoa_wrap_x_pos = '1' then
                                pdoa_right_adjusted_x <= right_angle + two_pi_value;
                            elsif pdoa_wrap_x_neg = '1' then
                                pdoa_right_adjusted_x <= right_angle - two_pi_value;
                            else pdoa_right_adjusted_x <= right_angle; end if;
                            right_angle := resize(pdoa_pair_angles(3), 33);
                            if pdoa_wrap_y_pos = '1' then
                                pdoa_right_adjusted_y <= right_angle + two_pi_value;
                            elsif pdoa_wrap_y_neg = '1' then
                                pdoa_right_adjusted_y <= right_angle - two_pi_value;
                            else pdoa_right_adjusted_y <= right_angle; end if;
                            pdoa_state <= P_AVERAGE_PHASES;
                        when P_AVERAGE_PHASES =>
                            angle_sum := resize(pdoa_pair_angles(0), 34) +
                                         resize(pdoa_right_adjusted_x, 34);
                            pdoa_phase_raw_x <= resize(shift_right(angle_sum, 1), 32);
                            angle_sum := resize(pdoa_pair_angles(2), 34) +
                                         resize(pdoa_right_adjusted_y, 34);
                            pdoa_phase_raw_y <= resize(shift_right(angle_sum, 1), 32);
                            pdoa_state <= P_PHASE_NORM_FLAGS;
                        when P_PHASE_NORM_FLAGS =>
                            pi_value := to_signed(843314857, 33);
                            pdoa_phase_norm_x_pos <= '0'; pdoa_phase_norm_x_neg <= '0';
                            pdoa_phase_norm_y_pos <= '0'; pdoa_phase_norm_y_neg <= '0';
                            if resize(pdoa_phase_raw_x, 33) > pi_value then pdoa_phase_norm_x_pos <= '1';
                            elsif resize(pdoa_phase_raw_x, 33) < -pi_value then pdoa_phase_norm_x_neg <= '1'; end if;
                            if resize(pdoa_phase_raw_y, 33) > pi_value then pdoa_phase_norm_y_pos <= '1';
                            elsif resize(pdoa_phase_raw_y, 33) < -pi_value then pdoa_phase_norm_y_neg <= '1'; end if;
                            pdoa_state <= P_PHASE_NORMALIZE;
                        when P_PHASE_NORMALIZE =>
                            if pdoa_phase_norm_x_pos = '1' then
                                pdoa_phase_x <= pdoa_phase_raw_x - to_signed(1686629713, 32);
                            elsif pdoa_phase_norm_x_neg = '1' then
                                pdoa_phase_x <= pdoa_phase_raw_x + to_signed(1686629713, 32);
                            else pdoa_phase_x <= pdoa_phase_raw_x; end if;
                            if pdoa_phase_norm_y_pos = '1' then
                                pdoa_phase_y <= pdoa_phase_raw_y - to_signed(1686629713, 32);
                            elsif pdoa_phase_norm_y_neg = '1' then
                                pdoa_phase_y <= pdoa_phase_raw_y + to_signed(1686629713, 32);
                            else pdoa_phase_y <= pdoa_phase_raw_y; end if;
                            pdoa_state <= P_SCALE_PARTIALS;
                        when P_SCALE_PARTIALS =>
                            -- Split each exact signed 32x32 product into four
                            -- 16-bit partial products. Low halves are zero
                            -- extended so each multiplier fits one DSP48.
                            pdoa_mul_x_ll <= signed('0' & std_logic_vector(pdoa_phase_x(15 downto 0))) *
                                             signed('0' & std_logic_vector(pdoa_scale_x_q16(15 downto 0)));
                            pdoa_mul_x_hl <= pdoa_phase_x(31 downto 16) *
                                             signed('0' & std_logic_vector(pdoa_scale_x_q16(15 downto 0)));
                            pdoa_mul_x_lh <= signed('0' & std_logic_vector(pdoa_phase_x(15 downto 0))) *
                                             pdoa_scale_x_q16(31 downto 16);
                            pdoa_mul_x_hh <= pdoa_phase_x(31 downto 16) * pdoa_scale_x_q16(31 downto 16);
                            pdoa_mul_y_ll <= signed('0' & std_logic_vector(pdoa_phase_y(15 downto 0))) *
                                             signed('0' & std_logic_vector(pdoa_scale_y_q16(15 downto 0)));
                            pdoa_mul_y_hl <= pdoa_phase_y(31 downto 16) *
                                             signed('0' & std_logic_vector(pdoa_scale_y_q16(15 downto 0)));
                            pdoa_mul_y_lh <= signed('0' & std_logic_vector(pdoa_phase_y(15 downto 0))) *
                                             pdoa_scale_y_q16(31 downto 16);
                            pdoa_mul_y_hh <= pdoa_phase_y(31 downto 16) * pdoa_scale_y_q16(31 downto 16);
                            pdoa_state <= P_SCALE_SUM_LO;
                        when P_SCALE_SUM_LO =>
                            pdoa_mul_accum_x <= resize(pdoa_mul_x_ll, 64) +
                                                shift_left(resize(pdoa_mul_x_hl, 64), 16);
                            pdoa_mul_accum_y <= resize(pdoa_mul_y_ll, 64) +
                                                shift_left(resize(pdoa_mul_y_hl, 64), 16);
                            pdoa_state <= P_SCALE_SUM_HI;
                        when P_SCALE_SUM_HI =>
                            pdoa_mul_accum_x <= pdoa_mul_accum_x +
                                                shift_left(resize(pdoa_mul_x_lh, 64), 16);
                            pdoa_mul_accum_y <= pdoa_mul_accum_y +
                                                shift_left(resize(pdoa_mul_y_lh, 64), 16);
                            pdoa_state <= P_SCALE;
                        when P_SCALE =>
                            pdoa_dir_x_q16 <= resize(shift_right(
                                pdoa_mul_accum_x + shift_left(resize(pdoa_mul_x_hh, 64), 32), 28), 32)
                                + pdoa_bias_x_q16;
                            pdoa_dir_y_q16 <= resize(shift_right(
                                pdoa_mul_accum_y + shift_left(resize(pdoa_mul_y_hh, 64), 32), 28), 32)
                                + pdoa_bias_y_q16;
                            pdoa_state <= P_NORM_X;
                        when P_NORM_X =>
                            pdoa_norm_x <= unsigned(pdoa_dir_x_q16 * pdoa_dir_x_q16);
                            pdoa_state <= P_NORM_Y;
                        when P_NORM_Y =>
                            pdoa_norm_y <= unsigned(pdoa_dir_y_q16 * pdoa_dir_y_q16);
                            pdoa_state <= P_NORM_SUM;
                        when P_NORM_SUM =>
                            pdoa_norm <= pdoa_norm_x + pdoa_norm_y;
                            pdoa_state <= P_QUALITY;
                        when P_QUALITY =>
                            quality_ok := true;
                            for channel in 0 to 3 loop
                                if resize(magnitude32(pdoa_i(channel)), 33) +
                                   resize(magnitude32(pdoa_q(channel)), 33) < resize(min_iq_magnitude, 33) then
                                    quality_ok := false;
                                end if;
                            end loop;
                            if quality_ok then pdoa_quality_ok <= '1';
                            else pdoa_quality_ok <= '0'; end if;
                            pdoa_state <= P_PIXEL_PRODUCT;
                        when P_PIXEL_PRODUCT =>
                            pdoa_pixel_product_x <= pdoa_dir_x_q16 * signed('0' & pixels_per_sine_x);
                            pdoa_pixel_product_y <= pdoa_dir_y_q16 * signed('0' & pixels_per_sine_y);
                            pdoa_state <= P_PIXEL_COORD;
                        when P_PIXEL_COORD =>
                            pdoa_pixel_x <= pixel_from_product(pdoa_pixel_product_x, pixel_center_x, false);
                            pdoa_pixel_y <= pixel_from_product(pdoa_pixel_product_y, pixel_center_y, true);
                            pdoa_state <= P_VALIDATE;
                        when P_VALIDATE =>
                            -- Publish the completed projection's I/Q window
                            -- identity with its validity and pixel registers.
                            pdoa_result_sequence <= pdoa_seq_seen;
                            if pdoa_quality_ok = '1' and pdoa_norm <= C_ONE_Q32 then
                                pdoa_valid <= '1';
                            else pdoa_valid <= '0'; end if;
                            pdoa_state <= P_IDLE;
                    end case;
                end if;
            end if;
        end if;
    end process;

    -- The buzzer edge gates a shared acoustic window. Envelope crossing
    -- offsets are diagnostics; bounded PCM correlation supplies the delays.
    process(aclk)
        variable sample_signed : signed(23 downto 0);
        variable sample_difference, sample_difference_abs : signed(24 downto 0);
        variable sample_magnitude : unsigned(23 downto 0);
        variable envelope_base, envelope_delta, envelope_result : unsigned(23 downto 0);
        variable baseline_next, threshold_margin : natural;
        variable next_seen : std_logic_vector(3 downto 0);
        variable next_arrival : arrival_array_t;
        variable elapsed : unsigned(63 downto 0);
        variable dx_wide, dy_wide : signed(33 downto 0);
        variable delta_x, delta_y : signed(31 downto 0);
        variable scale_result_x, scale_result_y : unsigned(31 downto 0);
        variable norm : unsigned(63 downto 0);
        variable correlation_channel_a, correlation_channel_b : natural range 0 to 3;
    begin
        if rising_edge(aclk) then
            if aresetn = '0' then
                toa_armed <= '0'; toa_pulse_previous <= '0';
                toa_capture_pending <= '0';
                toa_seen <= (others => '0'); toa_arrival <= (others => (others => '0'));
                toa_previous_sample <= (others => (others => '0'));
                toa_previous_valid <= (others => '0');
                toa_envelope <= (others => 0); toa_baseline <= (others => 0);
                toa_diff_pending_valid <= '0'; toa_step_pending_valid <= '0';
                toa_diff_pending_channel <= 0; toa_step_pending_channel <= 0;
                toa_diff_pending <= (others => '0');
                toa_step_pending_base <= (others => '0');
                toa_step_pending <= (others => '0'); toa_step_pending_increase <= '0';
                toa_crossing_count <= (others => 0);
                toa_trigger_frame <= (others => '0'); toa_clear_seen <= '0';
                tdoa_compute_state <= T_IDLE;
                tdoa_capture_index <= 0; tdoa_pair_index <= 0;
                tdoa_lag <= -8; tdoa_sample_index <= 8;
                tdoa_operand_a <= (others => '0'); tdoa_operand_b <= (others => '0');
                tdoa_product <= (others => '0');
                tdoa_correlation <= (others => '0');
                tdoa_best_correlation <= (others => '0'); tdoa_best_lag <= 0;
                tdoa_quality_ok <= '0';
                tdoa_pair_delta <= (others => (others => '0'));
                tdoa_norm_x <= (others => '0'); tdoa_norm_y <= (others => '0');
                tdoa_valid <= '0'; tdoa_event_count <= (others => '0');
                tdoa_delta_x_frames <= (others => '0'); tdoa_delta_y_frames <= (others => '0');
                tdoa_dir_x_q16 <= (others => '0'); tdoa_dir_y_q16 <= (others => '0');
                tdoa_mul_x_ll <= (others => '0'); tdoa_mul_y_ll <= (others => '0');
                tdoa_mul_x_hl <= (others => '0'); tdoa_mul_x_lh <= (others => '0');
                tdoa_mul_y_hl <= (others => '0'); tdoa_mul_y_lh <= (others => '0');
                tdoa_mul_accum_x <= (others => '0'); tdoa_mul_accum_y <= (others => '0');
                tdoa_pixel_product_x <= (others => '0');
                tdoa_pixel_product_y <= (others => '0');
                tdoa_pixel_center_x <= to_unsigned(320, 10);
                tdoa_pixel_center_y <= to_unsigned(240, 10);
                tdoa_pixels_per_sine_x <= to_unsigned(320, 10);
                tdoa_pixels_per_sine_y <= to_unsigned(240, 10);
                tdoa_pixel_x <= to_unsigned(320, 10); tdoa_pixel_y <= to_unsigned(240, 10);
                tdoa_result_frame <= (others => '0');
            else
                toa_pulse_previous <= pulse_start_i;

                -- Stage 3: commit the already divided EMA correction. The
                -- update moves by floor(abs(delta)/8), matching the original
                -- integer division toward zero for both directions.
                if toa_step_pending_valid = '1' then
                    if toa_step_pending_increase = '1' then
                        envelope_result := toa_step_pending_base + toa_step_pending;
                    else
                        envelope_result := toa_step_pending_base - toa_step_pending;
                    end if;
                    toa_envelope(toa_step_pending_channel) <= to_integer(envelope_result);
                end if;

                -- Stage 2: compare against the channel's current envelope and
                -- calculate only the unsigned correction magnitude.
                toa_step_pending_valid <= toa_diff_pending_valid;
                if toa_diff_pending_valid = '1' then
                    envelope_base := to_unsigned(
                        toa_envelope(toa_diff_pending_channel), 24);
                    toa_step_pending_base <= envelope_base;
                    toa_step_pending_channel <= toa_diff_pending_channel;
                    if toa_diff_pending >= envelope_base then
                        envelope_delta := toa_diff_pending - envelope_base;
                        toa_step_pending_increase <= '1';
                    else
                        envelope_delta := envelope_base - toa_diff_pending;
                        toa_step_pending_increase <= '0';
                    end if;
                    toa_step_pending <= shift_right(envelope_delta, 3);
                    toa_step_pending_valid <= '1';
                end if;

                -- Stage 1: capture abs(current - previous) and the channel
                -- identity. The next two stages finish before this channel's
                -- next sample arrives four clocks later.
                toa_diff_pending_valid <= '0';
                if s_axis_tvalid = '1' then
                    sample_signed := signed(s_axis_tdata(23 downto 0));
                    if toa_previous_valid(channel_index) = '1' then
                        sample_difference := resize(sample_signed, 25) -
                            resize(toa_previous_sample(channel_index), 25);
                        if sample_difference(24) = '1' then
                            sample_difference_abs := -sample_difference;
                        else
                            sample_difference_abs := sample_difference;
                        end if;
                        sample_magnitude := unsigned(sample_difference_abs(23 downto 0));
                        toa_diff_pending <= sample_magnitude;
                        toa_diff_pending_channel <= channel_index;
                        toa_diff_pending_valid <= '1';
                        if tdoa_compute_state = T_WAIT_FRAME and channel_index = 0 then
                            tdoa_samples(0, 0) <= sample_difference;
                            tdoa_capture_index <= 0;
                            tdoa_compute_state <= T_CAPTURE;
                        elsif tdoa_compute_state = T_CAPTURE then
                            tdoa_samples(channel_index, tdoa_capture_index) <= sample_difference;
                            if channel_index = 3 then
                                if tdoa_capture_index = 63 then
                                    tdoa_pair_index <= 0;
                                    tdoa_lag <= -8;
                                    tdoa_sample_index <= 8;
                                    tdoa_correlation <= (others => '0');
                                    tdoa_compute_state <= T_CORRELATE;
                                else
                                    tdoa_capture_index <= tdoa_capture_index + 1;
                                end if;
                            end if;
                        end if;
                    else
                        toa_previous_valid(channel_index) <= '1';
                    end if;
                    toa_previous_sample(channel_index) <= sample_signed;

                    if toa_previous_valid(channel_index) = '1' and toa_armed = '0' then
                        baseline_next := toa_baseline(channel_index) +
                            (toa_envelope(channel_index) -
                             toa_baseline(channel_index)) / 256;
                        toa_baseline(channel_index) <= baseline_next;
                    end if;
                end if;

                -- The per-channel noise baseline rejects the large PCM DC
                -- drift present before a buzzer pulse and freezes while a
                -- pulse is being measured. Envelope updates are pipelined above.

                if clear_toggle /= toa_clear_seen then
                    toa_clear_seen <= clear_toggle;
                    toa_diff_pending_valid <= '0'; toa_step_pending_valid <= '0';
                    toa_armed <= '0'; toa_seen <= (others => '0');
                    toa_capture_pending <= '0';
                    toa_crossing_count <= (others => 0);
                    toa_arrival <= (others => (others => '0'));
                    tdoa_compute_state <= T_IDLE;
                    tdoa_valid <= '0'; tdoa_event_count <= (others => '0');
                    tdoa_quality_ok <= '0';
                    tdoa_delta_x_frames <= (others => '0'); tdoa_delta_y_frames <= (others => '0');
                    tdoa_dir_x_q16 <= (others => '0'); tdoa_dir_y_q16 <= (others => '0');
                    tdoa_pixel_product_x <= (others => '0');
                    tdoa_pixel_product_y <= (others => '0');
                    tdoa_pixel_center_x <= pixel_center_x;
                    tdoa_pixel_center_y <= pixel_center_y;
                    tdoa_pixels_per_sine_x <= pixels_per_sine_x;
                    tdoa_pixels_per_sine_y <= pixels_per_sine_y;
                    tdoa_pixel_x <= pixel_center_x; tdoa_pixel_y <= pixel_center_y;
                elsif enabled = '1' and tdoa_enabled = '1' and pulse_start_i = '1'
                    and toa_pulse_previous = '0' then
                    toa_armed <= '1'; toa_seen <= (others => '0');
                    toa_capture_pending <= '0';
                    toa_crossing_count <= (others => 0);
                    toa_arrival <= (others => (others => '0'));
                    toa_trigger_frame <= frame_counter;
                    tdoa_compute_state <= T_IDLE;
                    tdoa_valid <= '0';
                    tdoa_quality_ok <= '1';
                elsif toa_capture_pending = '1' then
                    toa_capture_pending <= '0';
                    tdoa_compute_state <= T_WAIT_FRAME;
                elsif tdoa_compute_state = T_CORRELATE then
                    case tdoa_pair_index is
                        when 0 => correlation_channel_a := 0; correlation_channel_b := 1;
                        when 1 => correlation_channel_a := 2; correlation_channel_b := 3;
                        when 2 => correlation_channel_a := 0; correlation_channel_b := 2;
                        when others => correlation_channel_a := 1; correlation_channel_b := 3;
                    end case;
                    -- Positive lag means channel A arrived later than B.
                    -- Common indices for all lags keep each score comparable.
                    tdoa_operand_a <= tdoa_samples(correlation_channel_a, tdoa_sample_index);
                    tdoa_operand_b <= tdoa_samples(correlation_channel_b,
                                                   tdoa_sample_index - tdoa_lag);
                    tdoa_compute_state <= T_MULTIPLY;
                elsif tdoa_compute_state = T_MULTIPLY then
                    tdoa_product <= tdoa_operand_a * tdoa_operand_b;
                    tdoa_compute_state <= T_ACCUM;
                elsif tdoa_compute_state = T_ACCUM then
                    tdoa_correlation <= tdoa_correlation + resize(tdoa_product, 64);
                    if tdoa_sample_index = 55 then
                        tdoa_compute_state <= T_COMPARE;
                    else
                        tdoa_sample_index <= tdoa_sample_index + 1;
                        tdoa_compute_state <= T_CORRELATE;
                    end if;
                elsif tdoa_compute_state = T_COMPARE then
                    if tdoa_lag = -8 or tdoa_correlation > tdoa_best_correlation then
                        tdoa_best_correlation <= tdoa_correlation;
                        tdoa_best_lag <= tdoa_lag;
                    end if;
                    tdoa_correlation <= (others => '0');
                    tdoa_sample_index <= 8;
                    if tdoa_lag = 8 then
                        if tdoa_lag = -8 or tdoa_correlation > tdoa_best_correlation then
                            tdoa_pair_delta(tdoa_pair_index) <= to_signed(tdoa_lag, 33);
                            if tdoa_correlation < to_signed(48000000, 64) then
                                tdoa_quality_ok <= '0';
                            end if;
                        else
                            tdoa_pair_delta(tdoa_pair_index) <= to_signed(tdoa_best_lag, 33);
                            if tdoa_best_correlation < to_signed(48000000, 64) then
                                tdoa_quality_ok <= '0';
                            end if;
                        end if;
                        if tdoa_pair_index = 3 then
                            tdoa_compute_state <= T_DELTA_SUM;
                        else
                            tdoa_pair_index <= tdoa_pair_index + 1;
                            tdoa_lag <= -8;
                            tdoa_compute_state <= T_CORRELATE;
                        end if;
                    else
                        tdoa_lag <= tdoa_lag + 1;
                        tdoa_compute_state <= T_CORRELATE;
                    end if;
                elsif tdoa_compute_state = T_DELTA_SUM then
                    -- A strong peak alone does not establish a spatially valid
                    -- delay. Both baselines on each axis must agree within one
                    -- PCM frame (the correlator has integer-frame resolution).
                    if abs(resize(tdoa_pair_delta(0), 34) -
                           resize(tdoa_pair_delta(1), 34)) > to_signed(1, 34) or
                       abs(resize(tdoa_pair_delta(2), 34) -
                           resize(tdoa_pair_delta(3), 34)) > to_signed(1, 34) then
                        tdoa_quality_ok <= '0';
                    end if;
                    dx_wide := resize(tdoa_pair_delta(0), 34)
                             + resize(tdoa_pair_delta(1), 34);
                    dy_wide := resize(tdoa_pair_delta(2), 34)
                             + resize(tdoa_pair_delta(3), 34);
                    delta_x := resize(shift_right(dx_wide, 1), 32);
                    delta_y := resize(shift_right(dy_wide, 1), 32);
                    tdoa_delta_x_frames <= delta_x;
                    tdoa_delta_y_frames <= delta_y;
                    tdoa_compute_state <= T_SCALE_PARTIALS;
                elsif tdoa_compute_state = T_SCALE_PARTIALS then
                    -- Only the low 32 product bits are observable below.
                    -- Split unsigned bit patterns into 16-bit limbs; signed
                    -- and unsigned multiplication have identical low bits.
                    tdoa_mul_x_ll <= unsigned(tdoa_delta_x_frames(15 downto 0)) *
                                     unsigned(tdoa_scale_x_q16(15 downto 0));
                    tdoa_mul_x_hl <= resize(
                        unsigned(tdoa_delta_x_frames(31 downto 16)) *
                        unsigned(tdoa_scale_x_q16(15 downto 0)), 16);
                    tdoa_mul_x_lh <= resize(
                        unsigned(tdoa_delta_x_frames(15 downto 0)) *
                        unsigned(tdoa_scale_x_q16(31 downto 16)), 16);
                    tdoa_mul_y_ll <= unsigned(tdoa_delta_y_frames(15 downto 0)) *
                                     unsigned(tdoa_scale_y_q16(15 downto 0));
                    tdoa_mul_y_hl <= resize(
                        unsigned(tdoa_delta_y_frames(31 downto 16)) *
                        unsigned(tdoa_scale_y_q16(15 downto 0)), 16);
                    tdoa_mul_y_lh <= resize(
                        unsigned(tdoa_delta_y_frames(15 downto 0)) *
                        unsigned(tdoa_scale_y_q16(31 downto 16)), 16);
                    tdoa_compute_state <= T_SCALE_SUM;
                elsif tdoa_compute_state = T_SCALE_SUM then
                    tdoa_mul_accum_x <= tdoa_mul_x_ll(31 downto 16) + tdoa_mul_x_hl;
                    tdoa_mul_accum_y <= tdoa_mul_y_ll(31 downto 16) + tdoa_mul_y_hl;
                    tdoa_compute_state <= T_SCALE;
                elsif tdoa_compute_state = T_SCALE then
                    scale_result_x(31 downto 16) := tdoa_mul_accum_x + tdoa_mul_x_lh;
                    scale_result_x(15 downto 0) := tdoa_mul_x_ll(15 downto 0);
                    scale_result_y(31 downto 16) := tdoa_mul_accum_y + tdoa_mul_y_lh;
                    scale_result_y(15 downto 0) := tdoa_mul_y_ll(15 downto 0);
                    tdoa_dir_x_q16 <= signed(scale_result_x) + tdoa_bias_x_q16;
                    tdoa_dir_y_q16 <= signed(scale_result_y) + tdoa_bias_y_q16;
                    -- Snapshot the pixel geometry once per result so both axes
                    -- use one coherent PS configuration throughout projection.
                    tdoa_pixel_center_x <= pixel_center_x;
                    tdoa_pixel_center_y <= pixel_center_y;
                    tdoa_pixels_per_sine_x <= pixels_per_sine_x;
                    tdoa_pixels_per_sine_y <= pixels_per_sine_y;
                    tdoa_compute_state <= T_PROJECT_X_PRODUCT;
                elsif tdoa_compute_state = T_PROJECT_X_PRODUCT then
                    tdoa_pixel_product_x <= tdoa_dir_x_q16 *
                                            signed('0' & tdoa_pixels_per_sine_x);
                    tdoa_compute_state <= T_PROJECT_X;
                elsif tdoa_compute_state = T_PROJECT_X then
                    tdoa_pixel_x <= pixel_from_product(
                        tdoa_pixel_product_x, tdoa_pixel_center_x, false);
                    tdoa_compute_state <= T_PROJECT_Y_PRODUCT;
                elsif tdoa_compute_state = T_PROJECT_Y_PRODUCT then
                    tdoa_pixel_product_y <= tdoa_dir_y_q16 *
                                            signed('0' & tdoa_pixels_per_sine_y);
                    tdoa_compute_state <= T_PROJECT_Y;
                elsif tdoa_compute_state = T_PROJECT_Y then
                    tdoa_pixel_y <= pixel_from_product(
                        tdoa_pixel_product_y, tdoa_pixel_center_y, true);
                    tdoa_compute_state <= T_NORM_X;
                elsif tdoa_compute_state = T_NORM_X then
                    tdoa_norm_x <= unsigned(tdoa_dir_x_q16 * tdoa_dir_x_q16);
                    tdoa_compute_state <= T_NORM_Y;
                elsif tdoa_compute_state = T_NORM_Y then
                    tdoa_norm_y <= unsigned(tdoa_dir_y_q16 * tdoa_dir_y_q16);
                    tdoa_compute_state <= T_VALIDATE;
                elsif tdoa_compute_state = T_VALIDATE then
                    norm := tdoa_norm_x + tdoa_norm_y;
                    if norm <= C_ONE_Q32 and tdoa_quality_ok = '1' then tdoa_valid <= '1';
                    else tdoa_valid <= '0'; end if;
                    tdoa_event_count <= tdoa_event_count + 1;
                    tdoa_result_frame <= frame_counter;
                    tdoa_compute_state <= T_IDLE;
                elsif toa_armed = '1' and tdoa_enabled = '1' then
                    elapsed := frame_counter - toa_trigger_frame;
                    if elapsed > resize(toa_timeout_frames, 64) then
                        toa_armed <= '0'; toa_seen <= (others => '0');
                        toa_capture_pending <= '0';
                        toa_crossing_count <= (others => 0);
                        tdoa_valid <= '0';
                    elsif s_axis_tvalid = '1' and
                          toa_previous_valid(channel_index) = '1' then
                        next_seen := toa_seen;
                        next_arrival := toa_arrival;
                        if toa_seen(channel_index) = '0' then
                            threshold_margin := to_integer(shift_right(
                                toa_threshold(channel_index), 5));
                            if threshold_margin < 1500 then threshold_margin := 1500; end if;
                            if toa_envelope(channel_index) >=
                               toa_baseline(channel_index) + threshold_margin then
                                if toa_crossing_count(channel_index) = 3 then
                                    next_seen(channel_index) := '1';
                                    next_arrival(channel_index) := resize(
                                        frame_counter - toa_trigger_frame, 32);
                                    toa_crossing_count(channel_index) <= 0;
                                else
                                    toa_crossing_count(channel_index) <=
                                        toa_crossing_count(channel_index) + 1;
                                end if;
                            else
                                toa_crossing_count(channel_index) <= 0;
                            end if;
                        end if;
                        toa_seen <= next_seen;
                        toa_arrival <= next_arrival;
                        if next_seen = "1111" then
                            toa_armed <= '0';
                            -- Thresholds locate a shared active window only.
                            -- Their per-channel crossing times are diagnostic,
                            -- not a physical delay estimate.
                            toa_capture_pending <= '1';
                        end if;
                    end if;
                elsif tdoa_valid = '1' and tdoa_hold_frames /= 0 and
                    (frame_counter - tdoa_result_frame) > resize(tdoa_hold_frames, 64) then
                    tdoa_valid <= '0';
                end if;
            end if;
        end if;
    end process;
end architecture;
