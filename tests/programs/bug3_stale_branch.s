// Regression for defect 3: branch resolved on stale operands.
// beq waits in ID for x5 from the andi right before it (branch-data stall).
// x6 is always even, so the andi gives 0 and the beq is always taken, and
// the predictor learns that. During the stall the register file still holds
// x5 = 1 from the end of the previous iteration, a not-taken outcome that
// disagrees with the prediction. Once the loop is warm no I-cache stall masks
// the early resolution, so the stale outcome would squash the beq and send
// fetch down the odd path.
// Fixed RTL: the odd path never runs (x8 = 6, x9 = 0).

addi x6, x0, 0           // even value under test
addi x7, x0, 6           // iterations
addi x8, x0, 0           // even-path count
addi x9, x0, 0           // odd-path count (must stay 0)
addi x10, x0, 0          // iteration count

loop:
andi x5, x6, 1           // always 0
beq  x5, x0, even        // depends on the andi directly before it
addi x9, x9, 1           // odd path: wrong
jal  x0, next

even:
addi x8, x8, 1

next:
addi x5, x0, 1           // leave a stale x5 that disagrees with the beq
addi x6, x6, 2
addi x10, x10, 1
bne  x10, x7, loop

end_loop:
jal x0, end_loop
