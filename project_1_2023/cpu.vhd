-- cpu.vhd: Simple 8-bit CPU (BrainFuck interpreter)
-- Copyright (C) 2023 Brno University of Technology,
--                    Faculty of Information Technology
-- Author(s): Alisher Mazhirinov <xmazhi00 AT stud.fit.vutbr.cz>
--
library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_arith.all;
use ieee.std_logic_unsigned.all;

-- ----------------------------------------------------------------------------
--                        Entity declaration
-- ----------------------------------------------------------------------------
entity cpu is
 port (
   CLK   : in std_logic;  -- hodinovy signal
   RESET : in std_logic;  -- asynchronni reset procesoru
   EN    : in std_logic;  -- povoleni cinnosti procesoru
 
   -- synchronni pamet RAM
   DATA_ADDR  : out std_logic_vector(12 downto 0); -- adresa do pameti
   DATA_WDATA : out std_logic_vector(7 downto 0); -- mem[DATA_ADDR] <- DATA_WDATA pokud DATA_EN='1'
   DATA_RDATA : in std_logic_vector(7 downto 0);  -- DATA_RDATA <- ram[DATA_ADDR] pokud DATA_EN='1'
   DATA_RDWR  : out std_logic;                    -- cteni (0) / zapis (1)
   DATA_EN    : out std_logic;                    -- povoleni cinnosti
   
   -- vstupni port
   IN_DATA   : in std_logic_vector(7 downto 0);   -- IN_DATA <- stav klavesnice pokud IN_VLD='1' a IN_REQ='1'
   IN_VLD    : in std_logic;                      -- data platna
   IN_REQ    : out std_logic;                     -- pozadavek na vstup data
   
   -- vystupni port
   OUT_DATA : out  std_logic_vector(7 downto 0);  -- zapisovana data
   OUT_BUSY : in std_logic;                       -- LCD je zaneprazdnen (1), nelze zapisovat
   OUT_WE   : out std_logic;                      -- LCD <- OUT_DATA pokud OUT_WE='1' a OUT_BUSY='0'

   -- stavove signaly
   READY    : out std_logic;                      -- hodnota 1 znamena, ze byl procesor inicializovan a zacina vykonavat program
   DONE     : out std_logic                       -- hodnota 1 znamena, ze procesor ukoncil vykonavani programu (narazil na instrukci halt)
 );
end cpu;


-- ----------------------------------------------------------------------------
--                      Architecture declaration
-- ----------------------------------------------------------------------------
architecture behavioral of cpu is
    signal cnt_inc: std_logic;
    signal cnt_dec: std_logic;
    signal cnt_rst: std_logic;
    signal cnt_reg: std_logic_vector(12 downto 0);

    signal pc_inc: std_logic;
    signal pc_dec: std_logic;
    signal pc_rst: std_logic;
    signal pc_reg: std_logic_vector(12 downto 0);

    signal ptr_inc: std_logic;
    signal ptr_dec: std_logic;
    signal ptr_rst: std_logic;
    signal ptr_reg: std_logic_vector(12 downto 0);
    
    signal mx1_sel: std_logic;
    signal mx1_out: std_logic_vector(12 downto 0);

    signal mx2_sel: std_logic_vector(1 downto 0);
    signal mx2_out: std_logic_vector(7 downto 0);

    signal ready_internal : std_logic := '0';
    signal done_internal  : std_logic := '0';

    type STATE_TYPE is (
      IDLE,
      S_WAIT, S_WAIT_NEXT,
      FETCH, FETCH1, FETCH_INIT, FETCH_INIT2, FETCH_WAIT,
      DECODE, DECODE_INIT,
      INC_PTR,
      DEC_PTR,
      INC_VAL_START, INC_VAL_TO_DATA, INC_VAL_INC, INC_VAL_END,
      DEC_VAL_START, DEC_VAL_TO_DATA, DEC_VAL_DEC, DEC_VAL_END,
      WHILE_START, WHILE_GET_DATA, WHILE_CHECK_DATA, WHILE_CHECK_CNT, WHILE_FIND_BRACKET,
      END_WHILE_START, END_WHILE_GET_DATA, END_WHILE_CHECK_DATA, END_WHILE_S_WAIT_DATA, END_WHILE_CHECK_CNT, END_WHILE_CHECK_FOUND, 
      END_WHILE_FIND_BRACKET, 
      PUTCHAR_START, PUTCHAR_IN, PUTCHAR_END,
      GETCHAR_START, GETCHAR_IN, GETCHAR_END,
      S_RETURN,
      S_READY,
      S_DONE,
      S_INIT_START,
      S_INIT1,
      S_INIT2,
      S_INIT3,
      S_INIT4,
      S_BREAK,
      S_OTHERS, S_OTHERS_NEXT,
      S_HALT,
      S_HALT1,
      S_HALT2
      );

    signal fsm_state : STATE_TYPE := IDLE;
    signal NEXT_STATE : STATE_TYPE;

    --signal PTR_Z   : std_logic_vector(12 downto 0) := (others => '0');
    --signal PC_Z    : std_logic_vector(12 downto 0) := (others => '0');

begin
    cnt: process (CLK, RESET, cnt_inc, cnt_dec)
    begin
        if RESET = '1' then
            cnt_reg <= (others => '0');
        elsif (CLK'event) and (CLK = '1') then
            if cnt_inc = '1' then
                cnt_reg <= cnt_reg + 1;
            elsif cnt_dec = '1' then
                cnt_reg <= cnt_reg - 1;

            end if;
        end if;
    end process cnt;

    pc: process (CLK, RESET, pc_inc, pc_dec)
    begin
        if RESET = '1' then
            pc_reg <= (others => '0');
        elsif (CLK'event) and (CLK = '1') then
            if pc_inc = '1' then
                pc_reg <= pc_reg + 1;
            elsif pc_dec = '1' then
                pc_reg <= pc_reg - 1;
            end if;
        end if;
    end process;

    ptr: process (CLK, RESET, ptr_inc, ptr_dec)
    begin
        if RESET = '1' then
            ptr_reg <= (others => '0');
        elsif rising_edge(CLK) then
            if ptr_inc = '1' then
                ptr_reg <= ptr_reg + 1;
            elsif ptr_dec = '1' then
                ptr_reg <= ptr_reg - 1;

            end if;
        end if;
    end process;

    mx1: process (CLK, RESET, mx1_sel, pc_reg, ptr_reg)
    begin
        if RESET = '1' then
            mx1_out <= (others => '0');
        elsif rising_edge(CLK) then
            case mx1_sel is
                when '0'    => mx1_out <= pc_reg;
                when '1'    => mx1_out <= ptr_reg;
                when others => mx1_out <= (others => '0');
            end case;
        end if;
    end process;

    mx2: process (CLK, RESET, mx2_sel, IN_DATA, DATA_RDATA)
    begin
        if RESET = '1' then
            mx2_out <= (others => '0');
        elsif rising_edge(CLK) then
            case mx2_sel is
                when "00"   => mx2_out <= IN_DATA;
                when "01"   => mx2_out <= DATA_RDATA + 1;
                when "10"   => mx2_out <= DATA_RDATA - 1;
                when others => mx2_out <= (others => '0');
            end case;
        end if;
    end process;

    DATA_ADDR <= mx1_out;
    DATA_WDATA <= mx2_out;
    OUT_DATA <= DATA_RDATA;
    
    fsm_state_proc: process (CLK, RESET, EN)
    begin
        if RESET = '1' then
            fsm_state <= IDLE;
        elsif rising_edge(CLK) and EN = '1' then
            fsm_state <= NEXT_STATE;
        end if;
    end process fsm_state_proc;

    fsm: process (RESET, EN, DATA_RDATA, IN_DATA, fsm_state, OUT_BUSY, IN_VLD)
    begin
        -- __PC__
        pc_inc <= '0';
        pc_dec <= '0';
        pc_rst <= '0';
        -- __PTR__
        ptr_inc <= '0';
        ptr_dec <= '0';
        ptr_rst <= '0';
        -- __CNT__
        cnt_inc <= '0';
        cnt_dec <= '0';
        cnt_rst <= '0';
        -- __IN-OUT__
        IN_REQ <= '0';
        OUT_WE <= '0';
        -- __MX1__
        mx1_sel <= '0';
        -- __MX2__
        mx2_sel <= "00";
        -- __DATA__
        DATA_RDWR <= '0';
        DATA_EN <= '0';

        DONE <= '0';

        case fsm_state is
            when IDLE =>
                READY <= '0';
                NEXT_STATE <= FETCH_WAIT;

            when FETCH_WAIT =>
                NEXT_STATE <= FETCH_INIT;
            
            when FETCH_INIT =>
                mx1_sel <= '1';
                NEXT_STATE <= FETCH_INIT2;

            when FETCH_INIT2 =>
                DATA_EN <= '1';
                DATA_RDWR <= '0';
                NEXT_STATE <= DECODE_INIT;
       
            when S_DONE =>
                DONE <= '1';
                NEXT_STATE <= S_DONE;

            when DECODE_INIT =>
                if DATA_RDATA = X"40" then
                    ptr_inc <= '1';
                    NEXT_STATE <= S_READY;
                else
                    ptr_inc <= '1';
                    NEXT_STATE <= FETCH_INIT;
                end if;

            when S_READY =>
                ready_internal <= '1';
                READY <= '1';
                NEXT_STATE <= S_WAIT_NEXT;


            when S_HALT =>
                NEXT_STATE <= S_HALT;
            --+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
                
            when S_WAIT_NEXT =>
                NEXT_STATE <= FETCH1;
            
            when FETCH =>   
                mx1_sel <= '0';             
                NEXT_STATE <= FETCH1;
            
            when FETCH1 =>
                DATA_EN <= '1';
                DATA_RDWR <= '0';
                NEXT_STATE <= DECODE;

            when DECODE =>
                case DATA_RDATA is
                    when X"3E" =>
                        NEXT_STATE <= INC_PTR;
                    when X"3C" =>
                        NEXT_STATE <= DEC_PTR;
                    when X"2B" =>
                        NEXT_STATE <= INC_VAL_START;
                    when X"2D" =>
                        NEXT_STATE <= DEC_VAL_START;
                    when X"40" =>
                        NEXT_STATE <= S_DONE;
                    when X"5B" =>
                        NEXT_STATE <= WHILE_START;
                    when X"5D" =>
                        NEXT_STATE <= END_WHILE_START;
                    when X"7E" =>
                        NEXT_STATE <= S_BREAK;
                    when X"2E" =>
                        NEXT_STATE <= PUTCHAR_START;
                    when X"2C" =>
                        NEXT_STATE <= GETCHAR_START;
                    when others =>
                        NEXT_STATE <= S_OTHERS_NEXT;
                end case;


            when INC_PTR =>
                ptr_inc <= '1';
                pc_inc <= '1';

                NEXT_STATE <= FETCH;

            when DEC_PTR =>
                ptr_dec <= '1';
                pc_inc <= '1';

                NEXT_STATE <= FETCH;
            
            --- incrementace hodnoty aktualni bunky
            when INC_VAL_START =>
                mx1_sel <= '1';

                NEXT_STATE <= INC_VAL_TO_DATA;
                    
            when INC_VAL_TO_DATA =>
                DATA_EN <= '1';
                
                mx1_sel <= '1';

                NEXT_STATE <= INC_VAL_INC;

            when INC_VAL_INC =>
                mx2_sel <= "01";
                mx1_sel <= '1';
                pc_inc <= '1';

                NEXT_STATE <= INC_VAL_END;

            when INC_VAL_END =>
                DATA_EN <= '1';
                DATA_RDWR <= '1';

                NEXT_STATE <= FETCH;


            --- decrementace hodnoty aktualni bunky
            when DEC_VAL_START =>
                mx1_sel <= '1';

                NEXT_STATE <= DEC_VAL_TO_DATA;
                    
            when DEC_VAL_TO_DATA =>
                DATA_EN <= '1';
                mx1_sel <= '1';

                NEXT_STATE <= DEC_VAL_DEC;

            when DEC_VAL_DEC =>
                mx2_sel <= "10";
                mx1_sel <= '1';
                pc_inc <= '1';

                NEXT_STATE <= DEC_VAL_END;

            when DEC_VAL_END =>
                DATA_EN <= '1';
                DATA_RDWR <= '1';

                NEXT_STATE <= FETCH;

            --- vytiskni hodnotu aktualni bunky
            when PUTCHAR_START =>
                mx1_sel <= '1';

                NEXT_STATE <= PUTCHAR_IN;
         
            when PUTCHAR_IN =>
                DATA_EN <= '1';
                DATA_RDWR <= '0';
                mx1_sel <= '1';

                NEXT_STATE <= PUTCHAR_END;

            when PUTCHAR_END =>
                if OUT_BUSY = '1' then
                    mx1_sel <= '1';
                    DATA_EN <= '1';
                    DATA_RDWR <= '0';

                    NEXT_STATE <= PUTCHAR_END;
                else
                    mx1_sel <= '0';
                    OUT_WE <= '1';
                    pc_inc <= '1';
                    
                    NEXT_STATE <= S_WAIT_NEXT;
                end if;

            --- nacti hodnotu a uloz ji do aktualnı bunky
            when GETCHAR_START =>
                mx1_sel <= '1';
                if IN_VLD /= '1' then
                    IN_REQ <= '1';
                    
                    NEXT_STATE <= GETCHAR_START;
                else
                    DATA_EN <= '1';
                    mx2_sel <= "00";
                    
                    NEXT_STATE <= GETCHAR_IN;
                end if;

            when GETCHAR_IN =>
                DATA_EN <= '1';
                mx1_sel <= '1';
                DATA_RDWR <= '1';
                pc_inc <= '1';
                
                NEXT_STATE <= GETCHAR_END;

            when GETCHAR_END =>
            
            NEXT_STATE <= FETCH;

            --- while start
            when WHILE_START =>
                mx1_sel <= '1';

                NEXT_STATE <= WHILE_GET_DATA;

            when WHILE_GET_DATA =>
                pc_inc <= '1';
                DATA_EN <= '1';

                NEXT_STATE <= WHILE_CHECK_DATA;

            when WHILE_CHECK_DATA =>
                if DATA_RDATA /= "00000000" then
                
                    NEXT_STATE <= FETCH1;
                else
                    DATA_EN <= '1';
                    cnt_inc <= '1';

                    NEXT_STATE <= WHILE_CHECK_CNT;
                end if;

            when WHILE_CHECK_CNT =>
                if cnt_reg = "0000000000000" then

                    NEXT_STATE <= FETCH1;
                else
                    if DATA_RDATA = X"5B" then
                        cnt_inc <= '1';
                    elsif DATA_RDATA = X"5D" then
                        cnt_dec <= '1';
                    end if;
                    pc_inc <= '1';

                    NEXT_STATE <= WHILE_FIND_BRACKET;
                end if;

            when WHILE_FIND_BRACKET =>
                DATA_EN <= '1';

                NEXT_STATE <= WHILE_CHECK_CNT;

            --- while end
            when END_WHILE_START =>
                mx1_sel <= '1';

                NEXT_STATE <= END_WHILE_GET_DATA;

            when END_WHILE_GET_DATA =>
                DATA_EN <= '1';

                NEXT_STATE <= END_WHILE_CHECK_DATA;

            when END_WHILE_CHECK_DATA =>
                if DATA_RDATA = (DATA_RDATA'range => '0') then
                    pc_inc <= '1';

                    NEXT_STATE <= S_WAIT_NEXT;
                else
                    cnt_inc <= '1';
                    pc_dec <= '1';

                    NEXT_STATE <= END_WHILE_CHECK_CNT;
                end if;
            
            when END_WHILE_CHECK_CNT =>
                if cnt_reg = (cnt_reg'range => '0') then

                    NEXT_STATE <= FETCH1;
                else 
                    if DATA_RDATA = X"5D" then
                        cnt_inc <= '1';
                    elsif DATA_RDATA = X"5B" then
                        cnt_dec <= '1';
                    end if;

                    NEXT_STATE <= END_WHILE_CHECK_FOUND;
                end if;

            when END_WHILE_CHECK_FOUND =>
                if cnt_reg = (cnt_reg'range => '0') then
                    pc_inc <= '1';
                else
                    pc_dec <= '1';
                end if;

                NEXT_STATE <= END_WHILE_FIND_BRACKET;
            
            when END_WHILE_FIND_BRACKET =>
                DATA_EN <= '1';

                NEXT_STATE <= END_WHILE_CHECK_CNT;
            

                                        
            when others =>
                pc_inc <= '1';
                NEXT_STATE <= S_WAIT_NEXT;

        end case;

    
    end process fsm;


end behavioral;

 -- pri tvorbe kodu reflektujte rady ze cviceni INP, zejmena mejte na pameti, ze 
 --   - nelze z vice procesu ovladat stejny signal,
 --   - je vhodne mit jeden proces pro popis jedne hardwarove komponenty, protoze pak
 --      - u synchronnich komponent obsahuje sensitivity list pouze CLK a RESET a 
 --      - u kombinacnich komponent obsahuje sensitivity list vsechny ctene signaly. 
