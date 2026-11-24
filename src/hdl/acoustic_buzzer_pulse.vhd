-- One-shot active-buzzer driver for the PYNQ-Z2 AR2 digital header.
-- AXI-Lite runs on FCLK3 at 100 MHz. A start write launches one bounded
-- electrical pulse; it never repeats without another command.
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity acoustic_buzzer_pulse is
    generic (
        C_S_AXI_DATA_WIDTH : integer := 32;
        C_S_AXI_ADDR_WIDTH : integer := 5
    );
    port (
        aclk             : in  std_logic;
        aresetn          : in  std_logic;

        s_axi_awaddr     : in  std_logic_vector(C_S_AXI_ADDR_WIDTH-1 downto 0);
        s_axi_awprot     : in  std_logic_vector(2 downto 0);
        s_axi_awvalid    : in  std_logic;
        s_axi_awready    : out std_logic;
        s_axi_wdata      : in  std_logic_vector(C_S_AXI_DATA_WIDTH-1 downto 0);
        s_axi_wstrb      : in  std_logic_vector((C_S_AXI_DATA_WIDTH/8)-1 downto 0);
        s_axi_wvalid     : in  std_logic;
        s_axi_wready     : out std_logic;
        s_axi_bresp      : out std_logic_vector(1 downto 0);
        s_axi_bvalid     : out std_logic;
        s_axi_bready     : in  std_logic;
        s_axi_araddr     : in  std_logic_vector(C_S_AXI_ADDR_WIDTH-1 downto 0);
        s_axi_arprot     : in  std_logic_vector(2 downto 0);
        s_axi_arvalid    : in  std_logic;
        s_axi_arready    : out std_logic;
        s_axi_rdata      : out std_logic_vector(C_S_AXI_DATA_WIDTH-1 downto 0);
        s_axi_rresp      : out std_logic_vector(1 downto 0);
        s_axi_rvalid     : out std_logic;
        s_axi_rready     : in  std_logic;

        buzzer_pulse_o   : out std_logic
    );
    attribute X_INTERFACE_PARAMETER : string;
    attribute X_INTERFACE_PARAMETER of aclk : signal is
        "XIL_INTERFACENAME aclk, ASSOCIATED_BUSIF s_axi, ASSOCIATED_RESET aresetn, FREQ_HZ 100000000";
end acoustic_buzzer_pulse;

architecture rtl of acoustic_buzzer_pulse is
    constant C_RESPONSE_OK   : std_logic_vector(1 downto 0) := "00";
    constant C_RESPONSE_SLVERR : std_logic_vector(1 downto 0) := "10";
    constant C_DEFAULT_WIDTH : unsigned(31 downto 0) := to_unsigned(500000, 32);
    constant C_MIN_WIDTH     : unsigned(31 downto 0) := to_unsigned(10, 32);
    constant C_MAX_WIDTH     : unsigned(31 downto 0) := to_unsigned(100000000, 32);

    signal aw_pending       : std_logic := '0';
    signal awaddr_hold      : std_logic_vector(C_S_AXI_ADDR_WIDTH-1 downto 0) := (others => '0');
    signal w_pending        : std_logic := '0';
    signal wdata_hold       : std_logic_vector(C_S_AXI_DATA_WIDTH-1 downto 0) := (others => '0');
    signal wstrb_hold       : std_logic_vector((C_S_AXI_DATA_WIDTH/8)-1 downto 0) := (others => '0');
    signal axi_bvalid       : std_logic := '0';
    signal axi_bresp        : std_logic_vector(1 downto 0) := C_RESPONSE_OK;
    signal axi_rvalid       : std_logic := '0';
    signal axi_rresp        : std_logic_vector(1 downto 0) := C_RESPONSE_OK;
    signal axi_rdata        : std_logic_vector(C_S_AXI_DATA_WIDTH-1 downto 0) := (others => '0');
    signal axi_awready      : std_logic;
    signal axi_wready       : std_logic;
    signal axi_arready      : std_logic;

    signal pulse_width      : unsigned(31 downto 0) := C_DEFAULT_WIDTH;
    signal pulse_remaining  : unsigned(31 downto 0) := (others => '0');
    signal pulse_active     : std_logic := '0';
    signal pulse_done       : std_logic := '0';
    signal pulse_error      : std_logic := '0';
    signal cycle_counter    : unsigned(63 downto 0) := (others => '0');
    signal pulse_start_tick : unsigned(63 downto 0) := (others => '0');

    function merge_wstrb (
        old_value : std_logic_vector(31 downto 0);
        new_value : std_logic_vector(31 downto 0);
        strobes   : std_logic_vector(3 downto 0)
    ) return std_logic_vector is
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
begin
    buzzer_pulse_o <= pulse_active;
    axi_awready <= '1' when aresetn = '1' and aw_pending = '0' and axi_bvalid = '0' else '0';
    axi_wready  <= '1' when aresetn = '1' and w_pending = '0' and axi_bvalid = '0' else '0';
    axi_arready <= '1' when aresetn = '1' and axi_rvalid = '0' else '0';
    s_axi_awready <= axi_awready;
    s_axi_wready  <= axi_wready;
    s_axi_bresp   <= axi_bresp;
    s_axi_bvalid  <= axi_bvalid;
    s_axi_arready <= axi_arready;
    s_axi_rdata   <= axi_rdata;
    s_axi_rresp   <= axi_rresp;
    s_axi_rvalid  <= axi_rvalid;

    -- Register map: 0x00 command (bit 0 start, bit 1 abort, bit 2 clear),
    -- 0x04 width in FCLK3 cycles, 0x08 status, 0x0C/0x10 start tick low/high.
    process (aclk)
        variable write_addr  : natural;
        variable read_addr   : natural;
        variable command     : std_logic_vector(31 downto 0);
        variable width_word  : std_logic_vector(31 downto 0);
        variable read_word   : std_logic_vector(31 downto 0);
        variable write_error : boolean;
        variable read_error  : boolean;
    begin
        if rising_edge(aclk) then
            if aresetn = '0' then
                aw_pending <= '0'; awaddr_hold <= (others => '0');
                w_pending <= '0'; wdata_hold <= (others => '0'); wstrb_hold <= (others => '0');
                axi_bvalid <= '0'; axi_bresp <= C_RESPONSE_OK;
                axi_rvalid <= '0'; axi_rresp <= C_RESPONSE_OK; axi_rdata <= (others => '0');
                pulse_width <= C_DEFAULT_WIDTH; pulse_remaining <= (others => '0');
                pulse_active <= '0'; pulse_done <= '0'; pulse_error <= '0';
                cycle_counter <= (others => '0'); pulse_start_tick <= (others => '0');
            else
                cycle_counter <= cycle_counter + 1;

                if pulse_active = '1' then
                    if pulse_remaining = 1 then
                        pulse_remaining <= (others => '0');
                        pulse_active <= '0';
                        pulse_done <= '1';
                    elsif pulse_remaining > 1 then
                        pulse_remaining <= pulse_remaining - 1;
                    else
                        pulse_active <= '0';
                        pulse_error <= '1';
                    end if;
                end if;

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
                    axi_bresp <= C_RESPONSE_OK;
                    if not write_error then
                        case write_addr is
                            when 16#00# =>
                                command := merge_wstrb(x"00000000", wdata_hold, wstrb_hold);
                                if command(1) = '1' then
                                    pulse_active <= '0'; pulse_remaining <= (others => '0');
                                    pulse_done <= '1';
                                end if;
                                if command(2) = '1' then
                                    pulse_done <= '0'; pulse_error <= '0';
                                end if;
                                if command(0) = '1' then
                                    if pulse_active = '0' and pulse_width >= C_MIN_WIDTH
                                        and pulse_width <= C_MAX_WIDTH then
                                        pulse_remaining <= pulse_width;
                                        pulse_active <= '1'; pulse_done <= '0';
                                        pulse_start_tick <= cycle_counter;
                                    else
                                        pulse_error <= '1';
                                    end if;
                                end if;
                            when 16#04# =>
                                width_word := merge_wstrb(std_logic_vector(pulse_width), wdata_hold, wstrb_hold);
                                if unsigned(width_word) >= C_MIN_WIDTH and unsigned(width_word) <= C_MAX_WIDTH then
                                    pulse_width <= unsigned(width_word);
                                else
                                    pulse_error <= '1';
                                end if;
                            when others => write_error := true;
                        end case;
                    end if;
                    if write_error then axi_bresp <= C_RESPONSE_SLVERR; end if;
                    axi_bvalid <= '1'; aw_pending <= '0'; w_pending <= '0';
                end if;

                if axi_rvalid = '1' and s_axi_rready = '1' then axi_rvalid <= '0'; end if;
                if s_axi_arvalid = '1' and axi_arready = '1' then
                    read_addr := to_integer(unsigned(s_axi_araddr));
                    read_word := (others => '0');
                    read_error := (read_addr mod 4) /= 0;
                    if not read_error then
                        case read_addr is
                            when 16#00# => read_error := true;
                            when 16#04# => read_word := std_logic_vector(pulse_width);
                            when 16#08# =>
                                read_word(0) := pulse_active;
                                read_word(1) := pulse_done;
                                read_word(2) := pulse_error;
                            when 16#0C# => read_word := std_logic_vector(pulse_start_tick(31 downto 0));
                            when 16#10# => read_word := std_logic_vector(pulse_start_tick(63 downto 32));
                            when others => read_error := true;
                        end case;
                    end if;
                    axi_rdata <= read_word;
                    if read_error then axi_rresp <= C_RESPONSE_SLVERR;
                    else axi_rresp <= C_RESPONSE_OK;
                    end if;
                    axi_rvalid <= '1';
                end if;
            end if;
        end if;
    end process;
end rtl;
