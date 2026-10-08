// Regression for defect 1: JAL link value forwarded from MEM.
// From the second iteration on the BTB predicts the JAL, so its target
// follows it with no bubble and reads x1 through the MEM-stage forward.
// That forward must carry PC+4 (16), not the ALU output (x0 + x8 = 0).
// Pre-fix RTL: x2 = 0, x12 = 16. Fixed RTL: x2 = 16, x12 = 48.

addi x10, x0, 3          // iterations
addi x12, x0, 0          // sum of link values seen
addi x11, x0, 0          // i = 0

loop:
jal  x1, tgt             // PC 12, link = 16; rs1/rs2 fields = x0/x8
addi x0, x0, 0           // skipped

tgt:
addi x2, x1, 0           // reads the link register right after the JAL
add  x12, x12, x2
addi x11, x11, 1
bne  x11, x10, loop

end_loop:
jal x0, end_loop
