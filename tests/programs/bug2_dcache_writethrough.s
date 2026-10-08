// Regression for defect 2: D-cache write-through address and data.
// Addresses 0 and 256 map to the same D-cache line (64 entries x 4 bytes).
// The store hit to address 0 must write its own address and data through to
// RAM, so the reload after the conflict eviction returns 0x222. The load miss
// right after the write-through must also take its own RAM response.
// Pre-fix RTL: RAM[0] = 0, x9 = 0. Fixed RTL: RAM[0] = 0x222, x9 = 0x222.

addi x1, x0, 0x111
addi x2, x0, 0x222
addi x4, x0, 0x333
sw   x4, 256(x0)         // store miss: line 0 <- address 256
sw   x1, 0(x0)           // store miss: evicts 256, line 0 <- address 0
sw   x2, 0(x0)           // store hit: write-through of 0x222 to RAM[0]
lw   x3, 256(x0)         // conflict miss right after the write-through
lw   x9, 0(x0)           // conflict miss: reload address 0 from RAM
add  x10, x9, x3         // 0x222 + 0x333 = 0x555

end_loop:
jal x0, end_loop
