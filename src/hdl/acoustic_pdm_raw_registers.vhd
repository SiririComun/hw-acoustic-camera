-- Phase-3 RAW register adapter; all ports use aclk.
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity acoustic_pdm_raw_registers is
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

        clock_ready_i, busy_i, done_i : in std_logic;
        error_flags_i : in std_logic_vector(2 downto 0);
        frames_produced_i, words_sent_i, overflow_count_i : in std_logic_vector(31 downto 0);
        clock_enable_o, source_pattern_o : out std_logic;
        n_frames_o : out std_logic_vector(31 downto 0);
        start_o, abort_o, clear_o, config_error_o : out std_logic
    );
end acoustic_pdm_raw_registers;

architecture rtl of acoustic_pdm_raw_registers is
    constant C_MAGIC             : std_logic_vector(31 downto 0) := x"4143414D";
    constant C_ABI_VERSION       : std_logic_vector(31 downto 0) := x"00010000";
    constant C_CAPABILITIES      : std_logic_vector(31 downto 0) := x"0000000B";
    constant C_CHANNELS          : std_logic_vector(31 downto 0) := x"00000004";
    constant C_BUILD_ID          : std_logic_vector(127 downto 0) :=
        x"9FD0DDCDB84D4C52910805339C28CE2E";
    constant C_PDM_CLOCK_HZ      : std_logic_vector(31 downto 0) := x"00249F00";
    constant C_WARMUP_CYCLES     : std_logic_vector(31 downto 0) := x"0000BB80";
    constant C_RESPONSE_OK       : std_logic_vector(1 downto 0) := "00";
    constant C_RESPONSE_SLVERR   : std_logic_vector(1 downto 0) := "10";

    signal clock_enable_reg      : std_logic := '0';
    signal format_reg            : std_logic_vector(31 downto 0) := (others => '0');
    signal source_reg            : std_logic_vector(31 downto 0) := (others => '0');
    signal n_frames_reg          : std_logic_vector(31 downto 0) := (others => '0');

    signal aw_pending            : std_logic := '0';
    signal awaddr_hold           : std_logic_vector(6 downto 0) := (others => '0');
    signal w_pending             : std_logic := '0';
    signal wdata_hold            : std_logic_vector(31 downto 0) := (others => '0');
    signal wstrb_hold            : std_logic_vector(3 downto 0) := (others => '0');
    signal axi_bvalid            : std_logic := '0';
    signal axi_bresp             : std_logic_vector(1 downto 0) := C_RESPONSE_OK;
    signal axi_rvalid            : std_logic := '0';
    signal axi_rresp             : std_logic_vector(1 downto 0) := C_RESPONSE_OK;
    signal axi_rdata             : std_logic_vector(31 downto 0) := (others => '0');
    signal axi_awready            : std_logic;
    signal axi_wready             : std_logic;
    signal axi_arready            : std_logic;

    function merge_wstrb (
        old_value : std_logic_vector(31 downto 0);
        new_value : std_logic_vector(31 downto 0);
        strobes   : std_logic_vector(3 downto 0)
    ) return std_logic_vector is
        variable merged : std_logic_vector(31 downto 0) := old_value;
    begin
        for byte_index in 0 to 3 loop
            if strobes(byte_index) = '1' then
                merged(byte_index * 8 + 7 downto byte_index * 8) :=
                    new_value(byte_index * 8 + 7 downto byte_index * 8);
            end if;
        end loop;
        return merged;
    end function;
begin
    clock_enable_o <= clock_enable_reg;
    source_pattern_o <= source_reg(0);
    n_frames_o <= n_frames_reg;

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

    -- AXI4-Lite accepts AW and W independently, one outstanding write at a
    -- time. All words are 32-bit aligned; byte strobes are applied to RW words.
    process (aclk)
        variable write_addr       : natural;
        variable merged_word      : std_logic_vector(31 downto 0);
        variable command_word     : std_logic_vector(31 downto 0);
        variable write_error      : boolean;
        variable response         : std_logic_vector(1 downto 0);
    begin
        if rising_edge(aclk) then
            start_o <= '0'; abort_o <= '0'; clear_o <= '0'; config_error_o <= '0';
            if aresetn = '0' then
                clock_enable_reg <= '0';
                format_reg <= (others => '0');
                source_reg <= (others => '0');
                n_frames_reg <= (others => '0');
                aw_pending <= '0';
                awaddr_hold <= (others => '0');
                w_pending <= '0';
                wdata_hold <= (others => '0');
                wstrb_hold <= (others => '0');
                axi_bvalid <= '0';
                axi_bresp <= C_RESPONSE_OK;
            else
                if axi_bvalid = '1' and s_axi_bready = '1' then
                    axi_bvalid <= '0';
                end if;

                if s_axi_awvalid = '1' and axi_awready = '1' then
                    awaddr_hold <= s_axi_awaddr;
                    aw_pending <= '1';
                end if;
                if s_axi_wvalid = '1' and axi_wready = '1' then
                    wdata_hold <= s_axi_wdata;
                    wstrb_hold <= s_axi_wstrb;
                    w_pending <= '1';
                end if;

                if aw_pending = '1' and w_pending = '1' and axi_bvalid = '0' then
                    write_addr := to_integer(unsigned(awaddr_hold));
                    write_error := (write_addr mod 4) /= 0;
                    response := C_RESPONSE_OK;

                    if write_error then
                        response := C_RESPONSE_SLVERR;
                    else
                        case write_addr is
                            when 16#20# =>
                                merged_word := merge_wstrb((31 downto 1 => '0') & clock_enable_reg, wdata_hold, wstrb_hold);
                                if busy_i = '1' or unsigned(merged_word(31 downto 1)) /= 0 then
                                    config_error_o <= '1';
                                else
                                    clock_enable_reg <= merged_word(0);
                                end if;
                            when 16#24# =>
                                command_word := merge_wstrb(x"00000000", wdata_hold, wstrb_hold);
                                case command_word is
                                    when x"00000000" => null;
                                    when x"00000001" => start_o <= '1';
                                    when x"00000002" => abort_o <= '1';
                                    when x"00000004" => clear_o <= '1';
                                    when others => config_error_o <= '1';
                                end case;
                            when 16#30# =>
                                merged_word := merge_wstrb(format_reg, wdata_hold, wstrb_hold);
                                if busy_i = '1' or unsigned(merged_word) /= 0 then
                                    config_error_o <= '1';
                                else
                                    format_reg <= merged_word;
                                end if;
                            when 16#34# =>
                                merged_word := merge_wstrb(source_reg, wdata_hold, wstrb_hold);
                                if busy_i = '1' or unsigned(merged_word) > 1 then
                                    config_error_o <= '1';
                                else
                                    source_reg <= merged_word;
                                end if;
                            when 16#38# =>
                                merged_word := merge_wstrb(n_frames_reg, wdata_hold, wstrb_hold);
                                if busy_i = '1' or unsigned(merged_word) < 1 or unsigned(merged_word) > 65536 then
                                    config_error_o <= '1';
                                else
                                    n_frames_reg <= merged_word;
                                end if;

                            when others => -- RO and unmapped locations are errors
                                write_error := true;
                        end case;
                        -- Valid configuration/command addresses acknowledge the
                        -- bus transaction and report application rejection via
                        -- ERROR_FLAGS. SLVERR on an ordinary MMIO write can cause
                        -- a CPU external abort instead of a recoverable error.
                        -- Keep bus errors for malformed/unmapped/RO accesses.
                        if write_error then
                            response := C_RESPONSE_SLVERR;
                        end if;
                    end if;

                    axi_bresp <= response;
                    axi_bvalid <= '1';
                    aw_pending <= '0';
                    w_pending <= '0';
                end if;
            end if;
        end if;
    end process;

    -- AXI read channel for identity, configuration and status. It returns
    -- SLVERR for command, unaligned and unimplemented addresses; unavailable
    -- measurements read as zero.
    process (aclk)
        variable read_addr : natural;
        variable read_word : std_logic_vector(31 downto 0);
        variable read_error : boolean;
    begin
        if rising_edge(aclk) then
            if aresetn = '0' then
                axi_rvalid <= '0';
                axi_rresp <= C_RESPONSE_OK;
                axi_rdata <= (others => '0');
            else
                if axi_rvalid = '1' and s_axi_rready = '1' then
                    axi_rvalid <= '0';
                end if;

                if s_axi_arvalid = '1' and axi_arready = '1' then
                    read_addr := to_integer(unsigned(s_axi_araddr));
                    read_word := (others => '0');
                    read_error := (read_addr mod 4) /= 0;

                    if not read_error then
                        case read_addr is
                            when 16#00# => read_word := C_MAGIC;
                            when 16#04# => read_word := C_ABI_VERSION;
                            when 16#08# => read_word := C_CAPABILITIES;
                            when 16#0C# => read_word := C_CHANNELS;
                            when 16#10# => read_word := C_BUILD_ID(31 downto 0);
                            when 16#14# => read_word := C_BUILD_ID(63 downto 32);
                            when 16#18# => read_word := C_BUILD_ID(95 downto 64);
                            when 16#1C# => read_word := C_BUILD_ID(127 downto 96);
                            when 16#20# => read_word(0) := clock_enable_reg;
                            when 16#24# => read_error := true; -- WO COMMAND
                            when 16#28# =>
                                read_word(0) := clock_ready_i;
                                read_word(1) := busy_i;
                                read_word(2) := done_i;
                                if error_flags_i /= "000" then
                                    read_word(3) := '1';
                                end if;
                            when 16#2C# => read_word(2 downto 0) := error_flags_i;
                            when 16#30# => read_word := format_reg;
                            when 16#34# => read_word := source_reg;
                            when 16#38# => read_word := n_frames_reg;
                            when 16#3C# => read_word := x"00010000"; -- MAX_FRAMES
                            when 16#40# => read_word := C_PDM_CLOCK_HZ;
                            when 16#44# => read_word := (others => '0'); -- PCM_RATE_HZ
                            when 16#48# => read_word := (others => '0'); -- DECIMATION
                            when 16#4C# => read_word := frames_produced_i;
                            when 16#50# => read_word := words_sent_i;
                            when 16#54# => read_word := overflow_count_i;
                            when 16#58# => read_word := (others => '0'); -- CLIP_COUNT
                            when 16#5C# => read_word := C_WARMUP_CYCLES;
                            when 16#60# => read_word := (others => '0'); -- FILTER_SETTLE_FRAMES
                            when others => read_error := true;
                        end case;
                    end if;

                    axi_rdata <= read_word;
                    if read_error then
                        axi_rresp <= C_RESPONSE_SLVERR;
                    else
                        axi_rresp <= C_RESPONSE_OK;
                    end if;
                    axi_rvalid <= '1';
                end if;
            end if;
        end if;
    end process;
end rtl;
