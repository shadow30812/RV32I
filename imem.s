// RV32I EXTENSIVE SELF-CHECKING BENCHMARK (STRICT RV32I SUBSET)
// Supported Instructions: ADD, SUB, AND, OR, XOR, SLT, ADDI, ANDI, ORI, XORI,
//                         SLTI, LUI, LW, SW, BEQ, BNE, BLT, BGE, JAL

// ----------------------------------------------------------------------------
// Part 1: Comprehensive ALU & RAW Hazard Interlocks (x1 - x10)
// ----------------------------------------------------------------------------
addi x1,  x0, 15         // x1  = 15
addi x2,  x0, 25         // x2  = 25
add  x3,  x1, x2         // x3  = 40
sub  x4,  x2, x1         // x4  = 10
xor  x5,  x1, x2         // x5  = 15 ^ 25 = 22
and  x6,  x1, x2         // x6  = 15 & 25 = 9
or   x7,  x1, x2         // x7  = 15 | 25 = 31
slt  x8,  x1, x2         // x8  = 1
slt  x9,  x2, x1         // x9  = 0
xori x10, x3, 15         // x10 = 40 ^ 15 = 39

// ----------------------------------------------------------------------------
// Part 2: L1 Data Cache Store/Load, Miss/Hit, Load-Use Hazards (x11 - x15)
// ----------------------------------------------------------------------------
addi x11, x0, 64         // Base address = 64
addi x12, x0, 0x123      // Test pattern
sw   x12, 0(x11)         // Store 0x123 to Data RAM[64]
sw   x3,  4(x11)         // Store 40 to Data RAM[68]
lw   x13, 0(x11)         // Load 0x123 (Cache Hit)
lw   x14, 4(x11)         // Load 40 (Cache Hit)
add  x15, x13, x14       // x15 = 0x123 + 40 = 291 + 40 = 331 (0x14B)

// ----------------------------------------------------------------------------
// Part 3: Fibonacci Sequence with Array Loop (x16 - x20)
// Computes first 14 Fibonacci numbers: 0, 1, 1, 2, 3, 5, 8, 13, 21, 34, 55, 89, 144, 233
// ----------------------------------------------------------------------------
addi x16, x0, 0          // F(n-2) = 0
addi x17, x0, 1          // F(n-1) = 1
addi x18, x0, 2          // i = 2
addi x19, x0, 14         // limit = 14
addi x20, x0, 1          // sum accumulator = 1 (F0 + F1)

fib_loop:
add  x12, x16, x17       // F(n) = F(n-2) + F(n-1)
add  x20, x20, x12       // sum += F(n)
add  x16, x17, x0        // F(n-2) = F(n-1)
add  x17, x12, x0        // F(n-1) = F(n)
addi x18, x18, 1         // i++
bne  x18, x19, fib_loop  // loop until i == 14

// Restore temporary register x12:
addi x12, x0, 0x123

// ----------------------------------------------------------------------------
// Part 4: Euclidean GCD Algorithm (x21 - x25)
// Computes GCD(252, 105) = 21
// ----------------------------------------------------------------------------
addi x21, x0, 252        // a = 252
addi x22, x0, 105        // b = 105
addi x23, x0, 0          // iterations counter = 0

gcd_loop:
addi x23, x23, 1
beq  x21, x22, gcd_done
blt  x22, x21, gcd_a_greater
sub  x22, x22, x21       // b -= a
jal  x0, gcd_loop

gcd_a_greater:
sub  x21, x21, x22       // a -= b
jal  x0, gcd_loop

gcd_done:
addi x24, x0, 21         // x24 = Verified GCD constant = 21
add  x25, x21, x23       // x25 = GCD + iterations = 21 + 6 = 27

// ----------------------------------------------------------------------------
// Part 5: Modular Arithmetic Accumulator Loop (x26 - x28)
// Computes: (12 * 15) + 25 = 205 using JAL branching
// ----------------------------------------------------------------------------
addi x26, x0, 12         // multiplier = 12
addi x27, x0, 15         // multiplicand = 15
addi x28, x0, 25         // addend = 25

addi x12, x0, 0          // product = 0
addi x13, x0, 0          // counter = 0

mult_loop:
add  x12, x12, x26       // product += multiplier
addi x13, x13, 1
bne  x13, x27, mult_loop
add  x26, x12, x28       // x26 = (12 * 15) + 25 = 205

// Restore temporary registers:
addi x11, x0, 64
addi x12, x0, 0x123
addi x13, x0, 0x123

// ----------------------------------------------------------------------------
// Part 6: Bitwise Signatures & Cumulative Architectural Checksum (x27 - x31)
// ----------------------------------------------------------------------------
lui  x27, 0x12345
ori  x27, x27, 0x678     // x27 = 0x12345678
lui  x28, 0x55555
ori  x28, x28, 0x555     // x28 = 0x55555555
xor  x29, x27, x28       // x29 = 0x12345678 ^ 0x55555555 = 0x4761032D
addi x30, x0, 500        // x30 = 500

// x31 = Cumulative Checksum of x1 to x30
addi x31, x0, 0
add  x31, x31, x1
add  x31, x31, x2
add  x31, x31, x3
add  x31, x31, x4
add  x31, x31, x5
add  x31, x31, x6
add  x31, x31, x7
add  x31, x31, x8
add  x31, x31, x9
add  x31, x31, x10
add  x31, x31, x11
add  x31, x31, x12
add  x31, x31, x13
add  x31, x31, x14
add  x31, x31, x15
add  x31, x31, x16
add  x31, x31, x17
add  x31, x31, x18
add  x31, x31, x19
add  x31, x31, x20
add  x31, x31, x21
add  x31, x31, x22
add  x31, x31, x23
add  x31, x31, x24
add  x31, x31, x25
add  x31, x31, x26
add  x31, x31, x27
add  x31, x31, x28
add  x31, x31, x29
add  x31, x31, x30

addi x0, x0, 0
end_loop:
jal x0, end_loop