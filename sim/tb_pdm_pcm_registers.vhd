library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

entity tb_pdm_pcm_registers is end;
architecture test of tb_pdm_pcm_registers is
    signal clk : std_logic := '0';
    signal resetn : std_logic := '0';
    signal awaddr, araddr : std_logic_vector(6 downto 0) := (others=>'0');
    signal awvalid, wvalid, bready, arvalid, rready : std_logic := '0';
    signal awready, wready, bvalid, arready, rvalid : std_logic;
    signal wdata, rdata : std_logic_vector(31 downto 0) := (others=>'0');
    signal wstrb : std_logic_vector(3 downto 0) := "1111";
    signal bresp, rresp : std_logic_vector(1 downto 0);
    signal stream_resetn : std_logic := '1';
    signal data : std_logic_vector(31 downto 0);
    signal keep : std_logic_vector(3 downto 0);
    signal last, valid, pdm_clock : std_logic;
    signal ready : std_logic := '1';
    signal case_id, expected_words, received : natural := 0;
    signal expected_pcm, expected_pattern : boolean := true;
begin
    clk <= not clk after 5 ns;
    dut : entity work.acoustic_pdm_pcm_control
        port map(clk,resetn,awaddr,"000",awvalid,awready,wdata,wstrb,wvalid,wready,bresp,bvalid,bready,
            araddr,"000",arvalid,arready,rdata,rresp,rvalid,rready,
            pdm_clock,"1010",stream_resetn,data,keep,last,valid,ready);
    process(clk)
        variable previous_case, index : natural := 0;
        variable expected : signed(31 downto 0);
        variable held : boolean := false;
        variable held_data : std_logic_vector(31 downto 0);
        variable held_last : std_logic;
    begin
        if rising_edge(clk) then
            if resetn='0' or stream_resetn='0' then held:=false;
            else
                if held then
                    assert valid='1' and data=held_data and last=held_last and keep="1111"
                        report "AXI stalled data changed" severity failure;
                end if;
                held := valid='1' and ready='0'; held_data:=data; held_last:=last;
            end if;
            if previous_case/=case_id then index:=0; received<=0; previous_case:=case_id; end if;
            if case_id/=0 and valid='1' and ready='1' and stream_resetn='1' then
                if expected_pattern then
                    if expected_pcm then expected:=to_signed(16*(index/4)+index mod 4,32);
                    else expected:=to_signed(index,32); end if;
                else
                    if index mod 2=0 then expected:=to_signed(-8388608,32);
                    else expected:=to_signed(8388607,32); end if;
                end if;
                assert signed(data)=expected and keep="1111" and index<expected_words
                    report "Full-top capture word mismatch" severity failure;
                if index=expected_words-1 then assert last='1' severity failure;
                else assert last='0' severity failure; end if;
                index:=index+1; received<=index;
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
            awvalid <= '0'; ticks(2);
            wdata <= std_logic_vector(to_unsigned(value,32)); wstrb <= strobe; wvalid <= '1';
            loop wait until rising_edge(clk); exit when wready='1'; end loop;
            wvalid <= '0'; bready <= '0';
            loop wait until rising_edge(clk); exit when bvalid='1'; end loop;
            assert bresp=response report "Write response mismatch" severity failure;
            ticks(2); assert bvalid='1' and bresp=response report "B response not held" severity failure;
            bready <= '1'; ticks; bready <= '0';
        end;
        procedure read_word(address : natural; variable result : out std_logic_vector(31 downto 0);
                            response : std_logic_vector(1 downto 0) := "00") is
        begin
            araddr <= std_logic_vector(to_unsigned(address,7)); arvalid <= '1';
            loop wait until rising_edge(clk); exit when arready='1'; end loop;
            arvalid <= '0'; rready <= '0';
            loop wait until rising_edge(clk); exit when rvalid='1'; end loop;
            result:=rdata;
            assert rresp=response report "Read response mismatch" severity failure;
            ticks(2); assert rvalid='1' and rdata=result report "R data not held" severity failure;
            rready <= '1'; ticks; rready <= '0';
        end;
        procedure rd(address : natural; value : natural; response : std_logic_vector(1 downto 0) := "00") is
            variable result : std_logic_vector(31 downto 0);
        begin
            read_word(address,result,response);
            assert unsigned(result)=value report "Read mismatch addr=" & integer'image(address) & " data=" & to_hstring(result) severity failure;
        end;
        procedure idle is
            variable status : std_logic_vector(31 downto 0);
        begin
            for i in 1 to 10000 loop
                read_word(16#28#,status); exit when status(1)='0'; ticks(20);
            end loop;
            assert status(1)='0' report "Idle deadline" severity failure;
        end;
        procedure clear_state is begin wr(16#24#,4); idle; rd(16#2c#,0); end;
        procedure capture_ok(id,length : positive; pcm : boolean; pattern : boolean) is
        begin
            expected_pcm<=pcm; expected_pattern<=pattern; case_id<=id;
            if pcm then wr(16#30#,1); expected_words<=4*length;
            else wr(16#30#,0); expected_words<=length; end if;
            if pattern then wr(16#34#,1); else wr(16#34#,0); end if;
            wr(16#38#,length); wr(16#24#,1); idle;
            assert received=expected_words report "Completion word count mismatch" severity failure;
            rd(16#4c#,length); rd(16#50#,expected_words); rd(16#54#,0);
            if not pattern then rd(16#58#,4*length); else rd(16#58#,0); end if;
            case_id<=0;
        end;
        variable status, result : std_logic_vector(31 downto 0);
        constant build_id : std_logic_vector(127 downto 0) := x"B691CC9C9F6249AD938D2063E4767C54";
    begin
        ticks(10); resetn<='1'; idle;
        rd(0,16#4143414d#); rd(4,16#10000#); rd(8,15); rd(12,4);
        for i in 0 to 3 loop
            read_word(16#10#+4*i,result);
            assert result=build_id(i*32+31 downto i*32) report "BUILD_ID mismatch" severity failure;
        end loop;
        rd(16#3c#,65536); rd(16#44#,48000); rd(16#48#,50); rd(16#60#,6);
        rd(1,0,"10"); wr(0,0,"1111","10"); rd(16#24#,0,"10");
        wr(16#24#,1); rd(16#2c#,1); clear_state;
        wr(16#30#,2); rd(16#30#,0); rd(16#2c#,1); clear_state;
        wr(16#30#,1,"0000"); rd(16#30#,0);
        wr(16#20#,1,"0001");
        -- Native MMCM/divider/warmup must report ready before this test proceeds.
        for i in 1 to 500 loop
            read_word(16#28#,status); exit when status(0)='1'; ticks(5000);
        end loop;
        assert status(0)='1' and status(4)='0' report "Expected warmup then filter startup window" severity failure;
        wr(16#30#,1); wr(16#34#,0); wr(16#38#,17); wr(16#24#,1);
        rd(16#2c#,1); clear_state; -- PCM physical requires FILTER_READY.
        capture_ok(1,1,true,true); clear_state; -- pattern bypasses FILTER_READY.
        capture_ok(2,17,true,true); clear_state;
        read_word(16#28#,status); assert status(4)='1' report "Filter failed to settle" severity failure;
        capture_ok(3,17,true,false); clear_state;
        read_word(16#28#,status); assert status(4)='1' report "CLEAR/START reset physical filter" severity failure;
        capture_ok(4,17,false,true); clear_state;
        wr(16#38#,65536); rd(16#38#,65536);
        wr(16#38#,65537); rd(16#2c#,1); rd(16#38#,65536); clear_state;
        -- A forbidden live format change invalidates capture, preserving config
        -- and a stalled stream word until the DMA-local stream reset.
        wr(16#30#,1); wr(16#34#,1); wr(16#38#,17); ready<='0'; wr(16#24#,1);
        wait until valid='1' for 100 us; assert valid='1' severity failure;
        wr(16#30#,0); rd(16#30#,1); rd(16#2c#,1);
        wr(16#20#,0); rd(16#20#,1); wr(16#24#,2); rd(16#2c#,5);
        stream_resetn<='0'; ticks(20); stream_resetn<='1'; idle;
        rd(16#20#,1); rd(16#30#,1); rd(16#34#,1); rd(16#2c#,5);
        read_word(16#28#,status); assert status(4)='1' report "DMA recovery reset the filter" severity failure;
        clear_state; ready<='1'; capture_ok(5,2,true,true); clear_state;
        wr(16#20#,0); ticks(100);
        read_word(16#28#,status);
        assert status(0)='0' and status(4)='0' and pdm_clock='0'
            report "Clock disable did not reset filter readiness" severity failure;
        report "PDM_PCM_REGISTERS_ALL_PASS" severity note;
        finish;
    end process;
    process begin wait for 40 ms; assert false report "Full-top test deadline" severity failure; end process;
end;
