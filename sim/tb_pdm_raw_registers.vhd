library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

entity tb_pdm_raw_registers is end;
architecture test of tb_pdm_raw_registers is
    signal clk : std_logic := '0';
    signal clk24 : std_logic := '0';
    signal resetn : std_logic := '0';
    signal awaddr, araddr : std_logic_vector(6 downto 0) := (others=>'0');
    signal awvalid, wvalid, bready, arvalid, rready : std_logic := '0';
    signal awready, wready, bvalid, arready, rvalid : std_logic;
    signal wdata, rdata : std_logic_vector(31 downto 0) := (others=>'0');
    signal wstrb : std_logic_vector(3 downto 0) := "1111";
    signal bresp, rresp : std_logic_vector(1 downto 0);
    signal busy, done, enable, pattern, start_cmd, abort_cmd, clear_cmd, config_err : std_logic;
    signal n, frames, words, overflows : std_logic_vector(31 downto 0);
    signal errors : std_logic_vector(2 downto 0);
    signal stream_resetn : std_logic := '1';
    signal data : std_logic_vector(31 downto 0);
    signal keep : std_logic_vector(3 downto 0);
    signal last, valid : std_logic;
    signal ready : std_logic := '1';
    signal sample_ce : std_logic := '0';
    signal expected_n : natural := 1;
    signal received : natural := 0;
begin
    clk <= not clk after 5 ns;
    clk24 <= not clk24 after 20.833 ns;
    process(clk24)
        variable count : natural range 0 to 9 := 0;
    begin
        if rising_edge(clk24) then
            sample_ce <= '0';
            if count = 9 then count := 0; sample_ce <= '1'; else count := count+1; end if;
        end if;
    end process;
    regs : entity work.acoustic_pdm_raw_registers
        port map(clk,resetn,awaddr,"000",awvalid,awready,wdata,wstrb,wvalid,wready,bresp,bvalid,bready,
            araddr,"000",arvalid,arready,rdata,rresp,rvalid,rready,
            '1',busy,done,errors,frames,words,overflows,enable,pattern,n,
            start_cmd,abort_cmd,clear_cmd,config_err);
    core : entity work.acoustic_pdm_raw_capture
        port map(clk24,resetn,clk,resetn,sample_ce,"1010",'1',start_cmd,abort_cmd,clear_cmd,config_err,
            n,pattern,stream_resetn,busy,done,errors,frames,words,overflows,data,keep,last,valid,ready);
    process(clk)
    begin
        if rising_edge(clk) then
            if resetn='0' or clear_cmd='1' or start_cmd='1' then received <= 0;
            elsif valid='1' and ready='1' then
                if errors="000" then
                    assert unsigned(data)=received report "Pattern word mismatch" severity failure;
                    assert keep="1111" report "TKEEP mismatch" severity failure;
                    if received=expected_n-1 then assert last='1' severity failure;
                    else assert last='0' severity failure; end if;
                end if;
                received <= received+1;
            end if;
        end if;
    end process;
    process
        procedure ticks(count : positive := 1) is
        begin for i in 1 to count loop wait until rising_edge(clk); end loop; wait for 1 ns; end;
        procedure wr(address : natural; value : natural; strobe : std_logic_vector(3 downto 0) := "1111";
                     response : std_logic_vector(1 downto 0) := "00") is
        begin
            awaddr <= std_logic_vector(to_unsigned(address,7)); awvalid <= '1';
            loop wait until rising_edge(clk); exit when awready='1'; end loop;
            awvalid <= '0'; ticks(2); -- AW and W intentionally arrive independently.
            wdata <= std_logic_vector(to_unsigned(value,32)); wstrb <= strobe; wvalid <= '1';
            loop wait until rising_edge(clk); exit when wready='1'; end loop;
            wvalid <= '0'; bready <= '0';
            loop wait until rising_edge(clk); exit when bvalid='1'; end loop;
            assert bresp=response report "Write response mismatch" severity failure;
            ticks(2); assert bvalid='1' and bresp=response report "B response not held" severity failure;
            bready <= '1'; ticks; bready <= '0';
        end;
        procedure rd(address : natural; value : natural; response : std_logic_vector(1 downto 0) := "00") is
        begin
            araddr <= std_logic_vector(to_unsigned(address,7)); arvalid <= '1';
            loop wait until rising_edge(clk); exit when arready='1'; end loop;
            arvalid <= '0'; rready <= '0';
            loop wait until rising_edge(clk); exit when rvalid='1'; end loop;
            assert rresp=response and unsigned(rdata)=value report "Read mismatch addr=" & integer'image(address) & " data=" & to_hstring(rdata) severity failure;
            ticks(2); assert rvalid='1' and unsigned(rdata)=value report "R data not held" severity failure;
            rready <= '1'; ticks; rready <= '0';
        end;
        procedure idle is
        begin
            for i in 1 to 5000 loop ticks; exit when busy='0'; end loop;
            assert busy='0' report "Idle deadline" severity failure;
        end;
        procedure clear_state is begin wr(16#24#,4); idle; rd(16#2c#,0); end;
        procedure capture_ok(length : positive) is
        begin
            expected_n <= length; wr(16#38#,length); wr(16#24#,1); idle;
            assert done='1' and received=length report "Completion mismatch" severity failure;
            rd(16#4c#,length); rd(16#50#,length); rd(16#54#,0); rd(16#28#,5);
        end;
    begin
        ticks(5); resetn <= '1'; idle;
        rd(0,16#4143414d#); rd(8,11); rd(16#3c#,65536);
        rd(1,0,"10"); wr(0,0,"1111","10"); rd(16#24#,0,"10");
        wr(16#24#,1); rd(16#2c#,1); clear_state; -- reset N=0 rejects START
        wr(16#30#,1); rd(16#2c#,1); clear_state; -- PCM unavailable
        wr(16#34#,1,"0000"); rd(16#34#,0); -- zero strobe does not change source
        wr(16#20#,1,"0001"); rd(16#20#,1);
        wr(16#34#,1); rd(16#34#,1);
        wr(16#38#,65536); rd(16#38#,65536); -- upper valid boundary
        wr(16#38#,65537); rd(16#2c#,1); rd(16#38#,65536); clear_state;
        capture_ok(1); clear_state; capture_ok(17); clear_state;
        ready <= '0'; expected_n <= 17; wr(16#38#,17); wr(16#24#,1);
        ticks(80); assert busy='1' severity failure;
        wr(16#34#,0); rd(16#34#,1); rd(16#2c#,1); -- busy write rejected
        wr(16#24#,2); rd(16#2c#,5);
        stream_resetn <= '0'; ticks(20); stream_resetn <= '1'; idle;
        rd(16#20#,1); rd(16#34#,1); clear_state; ready <= '1'; capture_ok(2);
        report "PDM_RAW_REGISTERS_ALL_PASS" severity note;
        finish;
    end process;
    process begin wait for 1 ms; assert false report "Register test deadline" severity failure; end process;
end;
