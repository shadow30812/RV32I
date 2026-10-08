// Regression for defect 4: JAL immediate bits treated as source registers.
// The JAL at PC 12 has offset 40, so its rs2 field (imm[4:1], imm[11])
// encodes x8, which the addi right before it writes. The JAL runs for the
// first time (not predicted) while its fall-through line (PC 16) is already
// in the I-cache, so no I-cache stall masks a false branch-data stall.
// Pre-fix RTL: the JAL is squashed, x1 = 0, x20 = 0. Fixed RTL: both 16.

addi x8, x0, 0           // PC 0
jal  x0, warm            // PC 4: execute PC 16 first to warm its I-cache line

producer:
addi x8, x0, 9           // PC 8: writes x8 right before the JAL
jal  x1, tgt             // PC 12: offset 40, rs1 field = x0, rs2 field = x8

warm:
addi x21, x21, 1         // PC 16: the JAL's fall-through, only run by the warm-up
jal  x0, producer        // PC 20

addi x0, x0, 0           // PC 24-48: padding so the JAL offset is 40
addi x0, x0, 0
addi x0, x0, 0
addi x0, x0, 0
addi x0, x0, 0
addi x0, x0, 0
addi x0, x0, 0

tgt:
addi x20, x1, 0          // PC 52: copy of the link value

end_loop:
jal x0, end_loop
