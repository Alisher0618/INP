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
    
    signal mx1_input_sel: std_logic;
    signal mx1_output: std_logic_vector(12 downto 0);

    signal mx2_input_sel: std_logic_vector(1 downto 0);
    signal mx2_output: std_logic_vector(7 downto 0);

    type all_states is (
      idle,
      s_wait,
      fetch_1, fetch_2, 
      fetch_init_1, fetch_init_2, 
      fetch_wait,
      decode_init, decode,
      inc_ptr,dec_ptr,
      inc_val_1, inc_val_2, inc_val_3, inc_val_4,
      dec_val_1, dec_val_2, dec_val_3, dec_val_4,
      while_1, while_2, while_3, while_4, while_5,
      end_while_1, end_while_2, end_while_3, end_while_4, end_while_5,  
      putchar_1, putchar_2, putchar_3,
      getchar_1, getchar_2, getchar_3,
      s_ready,s_done,
      S_BREAK, S_BREAK1, S_BREAK2, S_BREAK3, S_BREAK4,
      s_others, s_halt
      );

    signal fsm_state : all_states := idle;
    signal next_state : all_states;

begin 
    --counter register
    cnt: process (CLK, RESET, cnt_inc, cnt_dec, cnt_rst)
    begin
        if RESET = '1' then
            cnt_reg <= (others => '0');
        elsif rising_edge(CLK) then
            if cnt_inc = '1' then
                cnt_reg <= cnt_reg + 1;
            elsif cnt_dec = '1' then
                cnt_reg <= cnt_reg - 1;
            elsif cnt_rst = '1' then
                cnt_reg <= ( 0 => '1', others => '0');
            end if;
        end if;
    end process;

    --pc register
    pc: process (CLK, RESET, pc_inc, pc_dec)
    begin
        if RESET = '1' then
            pc_reg <= (others => '0');
        elsif rising_edge(CLK) then
            if pc_inc = '1' then
                pc_reg <= pc_reg + 1;
            elsif pc_dec = '1' then
                pc_reg <= pc_reg - 1;
            end if;
        end if;
    end process;

    --ptr register
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

    -- PTR/PC multiplexor
    mx1: process (CLK, RESET, mx1_input_sel, pc_reg, ptr_reg)
    begin
        if RESET = '1' then
            mx1_output <= (others => '0');
        elsif rising_edge(CLK) then
            case mx1_input_sel is
                when '0'    => mx1_output <= pc_reg;
                when '1'    => mx1_output <= ptr_reg;
                when others => mx1_output <= (others => '0');
            end case;
        end if;
    end process;

    DATA_ADDR <= mx1_output;

    -- WRITE_DATA multiplexor
    mx2: process (CLK, RESET, mx2_input_sel, IN_DATA, DATA_RDATA)
    begin
        if RESET = '1' then
            mx2_output <= (others => '0');
        elsif rising_edge(CLK) then
            case mx2_input_sel is
                when "00"   => mx2_output <= IN_DATA;
                when "01"   => mx2_output <= DATA_RDATA + 1;
                when "10"   => mx2_output <= DATA_RDATA - 1;
                when others => mx2_output <= (others => '0');
            end case;
        end if;
    end process;

    DATA_WDATA <= mx2_output;


    OUT_DATA <= DATA_RDATA;
    
    -- RESET state
    fsm_state_proc: process (CLK, RESET, EN)
    begin
        if RESET = '1' then
            fsm_state <= idle;
        elsif rising_edge(CLK) and EN = '1' then
            fsm_state <= next_state;
        end if;
    end process fsm_state_proc;

    fsm: process (RESET, EN, DATA_RDATA, IN_DATA, fsm_state, OUT_BUSY, IN_VLD)
    begin
        cnt_inc <= '0';
        cnt_dec <= '0';
        cnt_rst <= '0';
        pc_inc <= '0';
        pc_dec <= '0';
        pc_rst <= '0';
        ptr_inc <= '0';
        ptr_dec <= '0';
        ptr_rst <= '0';
        mx1_input_sel <= '0';
        mx2_input_sel <= "00";
        DATA_RDWR <= '0';
        DATA_EN <= '0';
        IN_REQ <= '0';
        OUT_WE <= '0';
        DONE <= '0';

        case fsm_state is
            when idle =>
                READY <= '0';
                next_state <= fetch_wait;

            when fetch_wait =>
                next_state <= fetch_init_1;

            --INIT START
            
            when fetch_init_1 => --mem[PTR]
                mx1_input_sel <= '1';
                next_state <= fetch_init_2;

            when fetch_init_2 => --DATA_RDATA = mem[PTR}
                DATA_EN <= '1';
                DATA_RDWR <= '0';
                next_state <= decode_init;

            when decode_init =>
                if DATA_RDATA = X"40" then  --@
                    ptr_inc <= '1';
                    next_state <= s_ready;
                else
                    ptr_inc <= '1';
                    next_state <= fetch_init_1;
                end if;

            when s_ready => --ptr on @ was found
                READY <= '1';
                next_state <= s_wait;

            --INIT END

            when s_done =>  --pc of @ was found
                DONE <= '1';
                next_state <= S_HALT;

            when S_HALT =>
                DONE <= '1';
                next_state <= S_HALT;
                
            when s_wait =>
                next_state <= fetch_1;
            
            when fetch_1 =>   
                mx1_input_sel <= '0';       --mem[PC]
                next_state <= fetch_2;
            
            when fetch_2 =>
                DATA_EN <= '1'; --DATA_RDATA = mem[PC]
                DATA_RDWR <= '0';
                next_state <= decode;

            when decode =>
                case DATA_RDATA is
                    when X"3E" => -- >
                        next_state <= inc_ptr; 
                    when X"3C" => -- <
                        next_state <= dec_ptr;
                    when X"2B" => -- +
                        next_state <= inc_val_1;
                    when X"2D" => -- -
                        next_state <= dec_val_1;
                    when X"5B" => -- [
                        next_state <= while_1;
                    when X"5D" => -- ]
                        next_state <= end_while_1;
                    when X"7E" => -- ~
                        next_state <= S_BREAK;
                    when X"2E" => -- .
                        next_state <= putchar_1;
                    when X"2C" => -- ,
                        next_state <= getchar_1;
                    when X"40" => -- @
                        next_state <= s_done;
                    when others =>
                        next_state <= s_others;
                end case;

            -- inc of pointer

            when inc_ptr =>
                ptr_inc <= '1';
                pc_inc <= '1';

                next_state <= fetch_1;

            -- dec of pointer

            when dec_ptr =>
                ptr_dec <= '1';
                pc_inc <= '1';

                next_state <= fetch_1;

            -- inc of value

            when inc_val_1 =>
                mx1_input_sel <= '1';

                next_state <= inc_val_2;
                    
            when inc_val_2 =>
                DATA_EN <= '1';
                DATA_RDWR <= '0';

                next_state <= inc_val_3;

            when inc_val_3 =>
                mx2_input_sel <= "01";
                mx1_input_sel <= '1';
                
                next_state <= inc_val_4;

            when inc_val_4 =>
                DATA_EN <= '1';
                DATA_RDWR <= '1';
                pc_inc <= '1';

                next_state <= fetch_1;

            -- dec of value

            when dec_val_1 =>
                mx1_input_sel <= '1';

                next_state <= dec_val_2;
                    
            when dec_val_2 =>
                DATA_EN <= '1';
                DATA_RDWR <= '0';

                next_state <= dec_val_3;

            when dec_val_3 =>
                mx2_input_sel <= "10";
                mx1_input_sel <= '1';

                next_state <= dec_val_4;

            when dec_val_4 =>
                DATA_EN <= '1';
                DATA_RDWR <= '1';
                pc_inc <= '1';

                next_state <= fetch_1;

            -- start of while cycle

            when while_1 =>
                mx1_input_sel <= '1';
                pc_inc <= '1';

                next_state <= while_2;

            when while_2 =>
                DATA_EN <= '1';
                DATA_RDWR <= '0';
                next_state <= while_3;

            when while_3 =>
                if DATA_RDATA = "00000000" then
                    DATA_EN <= '1';
                    DATA_RDWR <= '0';
                    cnt_inc <= '1';
                    next_state <= while_4;
                    
                else
                    next_state <= fetch_1;
                end if;

            when while_4 =>
                DATA_EN <= '1';
                DATA_RDWR <= '0';
                next_state <= while_4;

            when while_5 =>
                if cnt_reg = "0000000000000" then

                    next_state <= fetch_1;
                else
                    if DATA_RDATA = X"5B" then
                        cnt_inc <= '1';
                    elsif DATA_RDATA = X"5D" then
                        cnt_dec <= '1';
                    end if;
                    pc_inc <= '1';

                    next_state <= while_4;
                end if;

            -- start of end while cycle

            when end_while_1 =>
                mx1_input_sel <= '1';
                next_state <= end_while_2;

            when end_while_2 =>
                DATA_EN <= '1';
                DATA_RDWR <= '0';

                next_state <= end_while_3;

            when end_while_3 =>
                if DATA_RDATA = "00000000" then
                    pc_inc <= '1';

                    next_state <= fetch_1;
                else
                    cnt_inc <= '1';
                    pc_dec <= '1';

                    next_state <= end_while_4;
                end if;
            
            when end_while_4 =>
                if cnt_reg = "0000000000000" then

                    next_state <= fetch_1;
                else 
                    if DATA_RDATA = X"5D" then
                        cnt_inc <= '1';
                    elsif DATA_RDATA = X"5B" then
                        cnt_dec <= '1';
                    end if;

                    next_state <= end_while_5;
                end if;

            when end_while_5 =>
                if cnt_reg = "0000000000000" then
                    pc_inc <= '1';
                else
                    pc_dec <= '1';
                end if;
                DATA_EN <= '1';
                DATA_RDWR <= '0';

                next_state <= end_while_4;
            
            -- break of while cycle

            when S_BREAK =>
                mx1_input_sel <= '1';
                pc_inc <= '1';
                
                next_state <= S_BREAK2;

            when S_BREAK2 =>
                DATA_EN <= '1';
                DATA_RDWR <= '0';

                next_state <= S_BREAK3;
            
            when S_BREAK3 =>
                if cnt_reg = "0000000000000" then

                    next_state <= s_wait;
                else
                    if DATA_RDATA = X"5B" then
                        cnt_inc <= '1';
                    elsif DATA_RDATA = X"5D" then
                        cnt_dec <= '1';
                    end if;
                    pc_inc <= '1';
                end if;
                next_state <= S_BREAK1;

            -- print value

            when putchar_1 =>
                mx1_input_sel <= '1';
                next_state <= putchar_2;
         
            when putchar_2 =>
                DATA_EN <= '1';
                DATA_RDWR <= '0';
                next_state <= putchar_3;

            when putchar_3 =>
                if OUT_BUSY = '1' then
                    next_state <= putchar_3;
                else
                    OUT_WE <= '1';
                    pc_inc <= '1';
                    next_state <= fetch_1;
                end if;

            -- get value

            when getchar_1 =>
                IN_REQ <= '1';
                next_state <= getchar_2;
                
            when getchar_2 =>
                if IN_VLD = '0' then
                    IN_REQ <= '1';
                    next_state <= getchar_1;
                else
                    mx1_input_sel <= '1';
                    mx2_input_sel <= "00";
                    next_state <= getchar_3;
                end if;

            when getchar_3 =>
                DATA_EN <= '1';
                DATA_RDWR <= '1';
                pc_inc <= '1';
                
                next_state <= fetch_1;

            when others =>
                pc_inc <= '1';
                next_state <= s_wait;

        end case;
    end process fsm;


end behavioral;

 -- pri tvorbe kodu reflektujte rady ze cviceni INP, zejmena mejte na pameti, ze 
 --   - nelze z vice procesu ovladat stejny signal,
 --   - je vhodne mit jeden proces pro popis jedne hardwarove komponenty, protoze pak
 --      - u synchronnich komponent obsahuje sensitivity list pouze CLK a RESET a 
 --      - u kombinacnich komponent obsahuje sensitivity list vsechny ctene signaly. 
