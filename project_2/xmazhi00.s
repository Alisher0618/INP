; Autor: xmazhi00

; Projekt 2 - INP 2022
; Vernamova sifra na architekture MIPS64
; xmazhi00-r11-r16-r28-r18-r0-r4

; DATA SEGMENT
                .data
login:          .asciiz "xmazhi00"  ; sem doplnte vas login
cipher:         .space  17  ; misto pro zapis sifrovaneho loginu

params_sys5:    .space  8   ; misto pro ulozeni adresy pocatku
                            ; retezce pro vypis pomoci syscall 5
                            ; (viz nize "funkce" print_string)

; CODE SEGMENT
                .text

; ***************My Implementation*************** 
main:           
    addi r4, r0, 0
    addi r18, r0, 0
                
while:      
    lb r11, login(r4)
    slti r16, r11, 97           
    bne r16, r18, finish
    andi r16, r4, 1
    beq r16, r18, increment    
    bne r16, r18, decrement     
                
increment:  ; +13
    addi r11, r11, 13
    addi r28, r28, 26
    slti r16, r11, 123
    bne r16, r18, write
    sub r11, r11, r28
    b write

decrement:  ; -1
    addi r28, r28, 1
    sub r11, r11, r28    
    slti r16, r11, 97
    beq r16, r18, write
    addi r11, r11, 26 
    b write

write:
    sb r11, cipher(r4)
    addi r4, r4, 1
    xor r28, r28, r28
    b while

finish:
    daddi r4, r0, cipher
    jal print_string
    syscall 0    
; ***************End of Implmentation***************

print_string:   ; adresa retezce se ocekava v r4
                sw      r4, params_sys5(r0)
                daddi   r14, r0, params_sys5    ; adr pro syscall 5 musi do r14
                syscall 5   ; systemova procedura - vypis retezce na terminal
                jr      r31 ; return - r31 je urcen na return address
                
