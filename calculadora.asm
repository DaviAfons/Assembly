section .data
    ; --- Mensagens do Menu e Prompts ---
    ; Define as strings constantes usadas na interface do usuário.
    ; '10' é o caractere de nova linha (\n) e '0' é o terminador nulo (estilo C).
menu_msg     db "Calculadora Assembly", 10, 0
menu_opts    db "1) Soma",10, "2) Subtracao",10, "3) Multiplicacao",10, "4) Divisao",10, "0) Sair",10, 0
choose_msg   db "Escolha uma opcao: ", 0
prompt1      db "Digite o primeiro inteiro: ", 0
prompt2      db "Digite o segundo inteiro: ", 0
err_div_zero db "Erro: divisao por zero", 10, 0

section .bss
    ; --- Buffers de Entrada/Saída ---
    ; Reserva espaço na memória para armazenar temporariamente as strings lidas ou a serem impressas.
inbuf    resb 128  ; Buffer para leitura do teclado
outbuf   resb 128  ; Buffer para montagem de números para impressão

section .text
global _start

; --- Wrappers de Syscall (Chamadas de Sistema) ---
; Funções auxiliares para simplificar as chamadas ao kernel Linux.

write_sys:
    ; Executa a syscall write (rax=1). Requer rdi (fd), rsi (buffer), rdx (tamanho).
    mov rax, 1
    syscall
    ret

read_sys:
    ; Executa a syscall read (rax=0). Requer rdi (fd), rsi (buffer), rdx (tamanho).
    mov rax, 0
    syscall
    ret

; --- Função: print_cstr ---
; Imprime uma string terminada em nulo (C-style string) para a saída padrão (stdout).
print_cstr:
    push rsi
    push rdx
    mov rsi, rdi        ; Ponteiro da string passa para RSI
    xor rcx, rcx        ; Zera o contador
.find_nl:
    ; Loop para encontrar o terminador nulo (0) e calcular o tamanho da string
    mov al, [rsi + rcx]
    cmp al, 0
    je .found_len
    inc rcx
    jmp .find_nl
.found_len:
    ; Configura os registradores para a syscall write usando o tamanho encontrado (RCX)
    mov rdx, rcx
    mov rax, 1          ; syscall: sys_write
    mov rdi, 1          ; fd: stdout
    mov rsi, rsi        ; buffer: início da string
    syscall
    pop rdx
    pop rsi
    ret

; --- Função: atoi_simple ---
; Converte uma string ASCII para um inteiro de 64 bits com sinal (ASCII to Integer).
atoi_simple:
    push rbp
    mov rbp, rsp
    push rbx
    push rcx
    push rdx
    mov rcx, 0          ; Índice da string
    mov rax, 0          ; Acumulador do resultado
    mov rbx, 1          ; Multiplicador de sinal (1 por padrão)
.skip_spaces:
    ; Pula espaços em branco ou tabulações iniciais
    mov bl, [rdi + rcx]
    cmp bl, ' '
    je .inc_i
    cmp bl, 9           ; Tab horizontal
    je .inc_i
    jmp .parse_sign
.inc_i:
    inc rcx
    jmp .skip_spaces
.parse_sign:
    ; Verifica se há um sinal explícito ('-' ou '+')
    mov bl, [rdi + rcx]
    cmp bl, '-'
    jne .check_plus
    mov rbx, -1         ; Define sinal como negativo
    inc rcx
    jmp .parse_digits
.check_plus:
    cmp bl, '+'
    jne .parse_digits
    inc rcx
.parse_digits:
    ; Loop principal de conversão dos dígitos
    mov bl, [rdi + rcx]
    cmp bl, 0           ; Fim da string (nulo)
    je .atoi_done
    cmp bl, '0'         ; Validação: menor que '0'?
    jb .atoi_done
    cmp bl, '9'         ; Validação: maior que '9'?
    ja .atoi_done
    
    ; Multiplica o acumulador atual por 10 (rax = rax * 10 + dígito)
    ; Usa um truque de shift/lea para multiplicar por 10: (rax * 8) + (rax * 2)
    mov rdx, rax
    shl rax, 3          ; rax * 8
    lea rax, [rax + rdx*2] ; rax = (rax*8) + (rax_original * 2) = rax * 10
    
    movzx rdx, bl       ; Carrega o dígito ASCII atual
    sub rdx, '0'        ; Converte ASCII para valor numérico
    add rax, rdx        ; Soma ao total
    inc rcx
    jmp .parse_digits
.atoi_done:
    ; Aplica o sinal final ao resultado
    cmp rbx, -1
    jne .ret_ok
    neg rax
.ret_ok:
    pop rdx
    pop rcx
    pop rbx
    pop rbp
    ret

; --- Função: print_int ---
; Converte um inteiro de 64 bits (em RDI) para string e imprime na tela.
print_int:
    push rbp
    mov rbp, rsp
    push rbx
    push rcx
    push rdx
    push rsi
    push rdi
    push r8             

    mov rax, rdi        ; O número a ser impresso
    mov rsi, outbuf     ; Buffer de saída
    xor rcx, rcx        ; Contador de dígitos

    ; Caso especial: se o número for zero
    cmp rax, 0
    jne .not_zero
    mov byte [rsi], '0'
    inc rcx
    jmp .print_done_conv

.not_zero:
    ; Verifica sinal. Se negativo, torna positivo e marca flag (rbx=1)
    xor rbx, rbx        
    cmp rax, 0
    jge .positive
    neg rax
    mov rbx, 1          
.positive:

.conv_loop:
    ; Loop de divisão por 10 para extrair dígitos (do último para o primeiro)
    xor rdx, rdx
    mov r8, 10         
    div r8              ; RAX / 10 -> Quociente em RAX, Resto em RDX
    add dl, '0'         ; Converte resto para ASCII
    mov [outbuf + rcx], dl ; Armazena no buffer
    inc rcx
    cmp rax, 0          ; Continua até o quociente ser 0
    jne .conv_loop

    ; Se era negativo, adiciona o sinal '-' ao final da string invertida
    cmp rbx, 1         
    jne .print_done_conv
    mov byte [outbuf + rcx], '-'
    inc rcx

.print_done_conv:
    ; A string está invertida no buffer (ex: "321-" para -123).
    ; Este bloco inverte a string para a ordem correta.
    xor rbx, rbx        ; Índice inicial (esquerda)
    mov rdx, rcx
    dec rdx             ; Índice final (direita)

.rev_loop:
    cmp rbx, rdx
    jge .rev_done       ; Se os índices se cruzaram, terminou a inversão

    mov al, [outbuf + rbx]
    mov r8b, [outbuf + rdx]
    mov [outbuf + rbx], r8b ; Troca os caracteres das pontas
    mov [outbuf + rdx], al

    inc rbx
    dec rdx
    jmp .rev_loop

.rev_done:
    ; Adiciona uma quebra de linha ao final para melhor formatação
    mov byte [outbuf + rcx], 10
    inc rcx

    ; Imprime o buffer final
    mov rdx, rcx        ; Tamanho total
    mov rax, 1          ; sys_write
    mov rdi, 1          ; stdout
    mov rsi, outbuf
    syscall

    pop r8
    pop rdi
    pop rsi
    pop rdx
    pop rcx
    pop rbx
    pop rbp
    ret

; --- Ponto de Entrada Principal ---
_start:
main_loop:
    ; --- Exibição do Menu ---
    lea rdi, [rel menu_msg]
    call print_cstr
    lea rdi, [rel menu_opts]
    call print_cstr
    lea rdi, [rel choose_msg]
    call print_cstr
    
    ; --- Leitura da Opção ---
    mov rdi, 0          ; stdin
    lea rsi, [rel inbuf]
    mov rdx, 8          ; lê alguns bytes (apenas o primeiro importa)
    call read_sys
    
    ; --- Despacho (Switch Case) ---
    mov al, [inbuf]
    cmp al, '0'
    je .op0             ; Sair
    cmp al, '1'
    je .op1             ; Soma
    cmp al, '2'
    je .op2             ; Subtração
    cmp al, '3'
    je .op3             ; Multiplicação
    cmp al, '4'
    je .op4             ; Divisão
    jmp main_loop       ; Opção inválida, repete menu

.op0: ; --- Opção 0: Sair ---
    mov rax, 60         ; sys_exit
    xor rdi, rdi        ; código de retorno 0
    syscall

.op1: ; --- Opção 1: Soma ---
    lea rdi, [rel prompt1]
    call print_cstr
    mov rdi, 0
    lea rsi, [rel inbuf]
    mov rdx, 64
    call read_sys       ; Lê primeiro número como string
    lea rdi, [rel inbuf]
    call atoi_simple    ; Converte para inteiro
    mov rbx, rax        ; Salva primeiro número em RBX

    lea rdi, [rel prompt2]
    call print_cstr
    mov rdi, 0
    lea rsi, [rel inbuf]
    mov rdx, 64
    call read_sys       ; Lê segundo número
    lea rdi, [rel inbuf]
    call atoi_simple    ; Converte para inteiro (está em RAX)
    
    add rax, rbx        ; SOMA: RAX = RAX + RBX
    mov rdi, rax
    call print_int      ; Imprime resultado
    jmp main_loop

.op2: ; --- Opção 2: Subtração ---
    ; (Lógica de leitura idêntica à soma)
    lea rdi, [rel prompt1]
    call print_cstr
    mov rdi, 0
    lea rsi, [rel inbuf]
    mov rdx, 64
    call read_sys
    lea rdi, [rel inbuf]
    call atoi_simple
    mov rbx, rax        ; RBX = primeiro número

    lea rdi, [rel prompt2]
    call print_cstr
    mov rdi, 0
    lea rsi, [rel inbuf]
    mov rdx, 64
    call read_sys
    lea rdi, [rel inbuf]
    call atoi_simple
    mov rcx, rax        ; RCX = segundo número
    
    mov rax, rbx        ; Move primeiro número para RAX
    sub rax, rcx        ; SUBTRAÇÃO: RAX = RAX - RCX
    mov rdi, rax
    call print_int
    jmp main_loop

.op3: ; --- Opção 3: Multiplicação ---
    ; (Lógica de leitura idêntica)
    lea rdi, [rel prompt1]
    call print_cstr
    mov rdi, 0
    lea rsi, [rel inbuf]
    mov rdx, 64
    call read_sys
    lea rdi, [rel inbuf]
    call atoi_simple
    mov rbx, rax

    lea rdi, [rel prompt2]
    call print_cstr
    mov rdi, 0
    lea rsi, [rel inbuf]
    mov rdx, 64
    call read_sys
    lea rdi, [rel inbuf]
    call atoi_simple
    
    imul rax, rbx       ; MULTIPLICAÇÃO com sinal: RAX = RAX * RBX
    mov rdi, rax
    call print_int
    jmp main_loop

.op4: ; --- Opção 4: Divisão ---
    lea rdi, [rel prompt1]
    call print_cstr
    mov rdi, 0
    lea rsi, [rel inbuf]
    mov rdx, 64
    call read_sys
    lea rdi, [rel inbuf]
    call atoi_simple
    mov rbx, rax        ; Dividendo em RBX

    lea rdi, [rel prompt2]
    call print_cstr
    mov rdi, 0
    lea rsi, [rel inbuf]
    mov rdx, 64
    call read_sys
    lea rdi, [rel inbuf]
    call atoi_simple
    mov rcx, rax        ; Divisor em RCX

    ; Verificação de divisão por zero
    cmp rcx, 0
    jne .do_div
    lea rdi, [rel err_div_zero]
    call print_cstr
    jmp main_loop

.do_div:
    mov rax, rbx        ; Configura dividendo em RAX
    cqo                 ; Estende o sinal de RAX para RDX:RAX (necessário para idiv)
    idiv rcx            ; DIVISÃO com sinal: RAX = (RDX:RAX) / RCX
    mov rdi, rax        ; Resultado (quociente) vai para RDI para impressão
    call print_int
    jmp main_loop