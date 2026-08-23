# **High-Performance Pipelined RV32I Processor Core with L1 Cache, Dynamic Branch Prediction, and SPI Peripheral**

## **Design Specification, Verification, and Advanced Microarchitectural Analysis**

## **1\. Executive Summary**

This repository contains a synthesizable, first-principles Verilog implementation of an optimized **5-stage pipelined RISC-V (RV32I) Processor Core**. Engineered with a focus on high-throughput, low-latency microarchitectural solutions, this design is tailored for embedded System-on-Chip (SoC) deployments.

Unlike standard textbook academic implementations, this processor integrates a **256-entry dynamic branch predictor** (2-bit saturating counter BHT with BTB and tag-based aliasing protection), a **split Harvard L1 cache hierarchy** (separate 64-entry direct-mapped Instruction and Data caches), early branch-resolution in the Decode stage, a robust structural interlock and data hazard unit with multi-stage forwarding, and **Dual-Port Block RAM** as physical main memory. Additionally, the system includes a Memory-Mapped I/O (MMIO) bridge interfacing the CPU to a fully functional, configurable SPI Master peripheral.

**Target FPGA**: Kintex-7 `xc7k325tfbv900-3` — Verified at **125 MHz** with **+1.685 ns** setup slack (Fmax ≈ 158 MHz). Total on-chip power: **202 mW**.

## **2\. Microarchitectural Topology**

The processor implements a 5-stage pipeline with dynamic branch prediction in the Fetch stage, early branch resolution in Decode, and a split L1 cache hierarchy backed by Harvard Dual-Port Block RAM:

```
                    ┌─────────────────────────────────────────────────────┐
                    │             Branch Prediction Feedback              │
                    │       (actual_branch_valid, actual_mispredict)      │
                    │                                                     │
  [Fetch/IF] ────────> [Decode/ID] ────────> [Execute/EX] ────────> [Memory/MEM] ────────> [Writeback/WB]
  ┌──────────┐       ┌────────────┐          ┌──────────┐           ┌────────────┐         ┌────────────┐
  │ PC Gen   │       │ Instr Dec  │          │ ALU      │           │ Addr Demux │         │ WB MUX     │
  │ BHT/BTB  │       │ Imm Gen    │          │ Fwd MUX  │           │ Cache/MMIO │         │ ALU/Mem/PC │
  │ Predictor│       │ Branch Cmp │          │ (3-to-1) │           │ Stall Gen  │         │            │
  └──────────┘       └────────────┘          └──────────┘           └────────────┘         └────────────┘
       |                   |                       |                       |                      |
       |<──────────────────+                       |                       |                      |
       |   (Mispredict     |                       |                       |                      |
       |    Recovery)      |                       |                       |                      |
       |              ┌────+───────────────────────+───────────────────────+──────────────────────+
       |              │            Hazard Detection & Forwarding Unit (hazard.v)                  │
       |              │  EX Forwarding (fwd_a/fwd_b)  |  ID Forwarding (rs1/rs2_data_fwd)        │
       |              │  Load-Use Stall | Branch Stall | Cache Stall | I-Cache Stall             │
       |              └──────────────────────────────────────────────────────────────────────────-┘
       |                   |                                              |
  ┌────+────┐         ┌────+────┐                                    ┌────+────┐
  │ L1      │         │ RegFile │                                    │ L1      │
  │ I-Cache │         │ (32x32) │                                    │ D-Cache │
  │ (64-ln) │         │ Bypass  │                                    │ (64-ln) │
  └────+────┘         └─────────┘                                    └────+────┘
       |   Port A                                                Port B   |
  ┌────+──────────────────────────────────────────────────────────────────-+────┐
  │                    Dual-Port Block RAM (ram.v)                             │
  │                  iram[0:1023] (4 KB)  |  dram[0:1023] (4 KB)              │
  └────────────────────────────────────────────────────────────────────────────┘
```

### **Stage Pipeline Organization:**

1. **Instruction Fetch (IF)**: Incorporates PC generation with priority-decoded control flow, a **256-entry dynamic branch predictor** (2-bit saturating counter BHT, BTB, and tag-aliased tables), speculative instruction fetching, and instantaneous control-flow redirection upon misprediction signals from the Decode stage.
2. **Instruction Decode (ID)**: Houses register file read ports, immediate generation (U/I/S/B/J types), instruction decoding, and an **early branch evaluation unit** that resolves branch outcomes in 1 cycle using forwarded operand data from the hazard unit.
3. **Execute (EX)**: Performs execution of arithmetic, logic, and shift operations using a parameterized ALU with **3-to-1 forwarding multiplexers** on both operand inputs.
4. **Memory Access (MEM)**: Interfaces with the L1 Data Cache and the MMIO arbiter. Dynamically decodes addresses to route transactions to the appropriate subsystem and generates pipeline stalls on cache misses or busy peripherals.
5. **Writeback (WB)**: Selects between the ALU result, memory-read data, or program counter link value (PC+4) to commit state back to the architectural register file.

## **3\. Comprehensive File Breakdown & Industry-Grade Features**

Standard academic processors often bypass physical memory latencies, resolve control flow deep in the pipeline (incurring massive stall penalties), or omit real-world peripheral integration. Below is an exhaustive breakdown of each source file, highlighting the advanced design features that distinguish this project.

### **3.1. system.v (System Top-Level Integration)**

* **Architectural Role**: Integrates the pipelined core, the hazard unit, the split L1 cache hierarchy (I-Cache and D-Cache), the Dual-Port Block RAM, and the SPI Master controller onto a unified SoC interconnect.
* **Special Features & Competitive Advantages**:
  * **Unified CPU-Peripheral SoC Interconnect**: Implements a dedicated memory address-space decoder that seamlessly routes memory transactions to either the L1 D-Cache (for cacheable RAM spaces) or the MMIO arbiter (for non-cacheable device address spaces).
  * **Harvard Cache-RAM Hierarchy**: The system instantiates the I-Cache and D-Cache as separate modules, each connected to independent ports of the Dual-Port Block RAM, enabling simultaneous instruction fetch and data access without structural hazards.
  * **Configurable Clock-Phase (CPHA) and Clock-Polarity (CPOL) Registers**: Exposes registers directly mapped to `0x8000_0004` that allow the CPU to dynamically configure SPI timing configurations on-the-fly, supporting diverse external slave peripherals.
  * **Dynamic Status Flags Register**: Offers a 32-bit read-only status port detailing the state of the SPI FIFOs (Full, Empty, Busy, RX-Valid).

### **3.2. hazard.v (Hazard Detection and Forwarding Unit)**

* **Architectural Role**: Combinationally evaluates data dependencies across the pipeline and orchestrates structural flushes, pipeline freezes, and multi-stage data forwarding.
* **Special Features & Competitive Advantages**:
  * **Dual-Level Forwarding Network**: Provides two independent forwarding channels:
    * **EX-Stage Forwarding** (`fwd_a`, `fwd_b`): 3-to-1 MUXes feeding ALU operand inputs, with MEM-stage priority over WB-stage over RegFile data.
    * **ID-Stage Branch Forwarding** (`rs1_data_fwd`, `rs2_data_fwd`): Dedicated forwarding paths that pull operands from the MEM or WB stages directly into the ID-stage branch comparators, enabling 1-cycle branch resolution without waiting for register file writeback.
  * **Interlocking Logic for Load-Use and Branch Hazards**:
    * **Load-Use Interlock**: Detects when a decoded instruction reads a register undergoing a load operation in the execution stage and asserts a 1-cycle stall bubble.
    * **Branch-Data Interlock**: Detects when a branch instruction depends on an active instruction in EX (whose ALU output is not yet computed) or a Load instruction in MEM (whose data is not yet available), and initiates the required pipeline freeze.
  * **I-Cache Miss Stall Integration**: The `stall_icache` signal from the L1 Instruction Cache propagates through the hazard unit to freeze all pipeline stages and inject bubbles during instruction cache refills, ensuring coherent pipeline operation across cache misses.

### **3.3. icache.v (L1 Instruction Cache)**

* **Architectural Role**: Provides a 64-entry, direct-mapped L1 Instruction Cache for low-latency instruction fetching.
* **Special Features & Competitive Advantages**:
  * **Cache Geometry**: 64 entries (2^6), 1-word (32-bit) per cache line, direct-mapped indexing. Address decomposition: Index = `addr[7:2]` (6 bits), Tag = `addr[31:8]` (24 bits).
  * **Cycle-Accurate Latency FSM**: Implements a 3-state Finite State Machine (`STATE_IDLE`, `STATE_FETCH`, `STATE_READY`) to model realistic memory access latency on cache misses.
  * **Miss Refill Protocol**: On an I-Cache miss, the FSM asserts `mem_req` to Port A of the Dual-Port Block RAM, waits for `mem_ready`, allocates the cache line (writing `data_array`, `tag_array`, and `valid_array`), then enters `STATE_READY` for a 1-cycle hold to allow the stalled pipeline to latch the fetched instruction before returning to `STATE_IDLE`.
  * **Distributed RAM Inference**: Data and tag arrays are synthesized as LUT-based distributed RAM (`(* ram_style = "distributed" *)`) for minimum-latency combinational reads.

### **3.4. dcache.v (L1 Data Cache)**

* **Architectural Role**: Provides a 64-entry, direct-mapped L1 Data Cache for low-latency variable read and write operations with a write-through policy.
* **Special Features & Competitive Advantages**:
  * **Cache Geometry**: Identical to I-Cache — 64 entries, 1-word lines, direct-mapped. Index = `addr[7:2]`, Tag = `addr[31:8]`.
  * **Write-Through + Write-Allocate Policy**:
    * **Write Hit**: Updates the local cache line AND simultaneously writes through to main memory, ensuring memory coherence.
    * **Write Miss**: Sends the write to main memory via the FSM AND allocates the cache line with the write data.
    * **Read Miss**: Fetches the line from main memory, allocates into cache, and enters the `STATE_READY` hold state.
  * **Synchronous Hardware Wait-State Signaling**: On a cache miss, the FSM asserts a stall signal via `cache_hit` deassertion, which propagates through the memory stage to freeze the pipeline until the refill completes.

### **3.5. fetch.v (Fetch Stage with Dynamic Branch Prediction)**

* **Architectural Role**: Drives the program counter (PC) logic, coordinates instruction retrieval from the L1 I-Cache, and implements a full dynamic branch prediction subsystem.
* **Special Features & Competitive Advantages**:
  * **256-Entry Dynamic Branch Predictor**: The Fetch stage implements a complete prediction subsystem comprising:
    * **Branch History Table (BHT)**: 256 entries of 2-bit saturating counters with 4 states: Strongly Not Taken (`SNT = 2'b00`), Weakly Not Taken (`WNT = 2'b01`), Weakly Taken (`WT = 2'b10`), Strongly Taken (`ST = 2'b11`). Prediction is "taken" when `bht[1] == 1`.
    * **Branch Target Buffer (BTB)**: 256 entries of 32-bit cached target addresses, providing the predicted target PC on a predicted-taken branch.
    * **Tag Table**: 256 entries of 22-bit aliasing protection tags, preventing false positive predictions from unrelated instructions mapping to the same BHT/BTB index.
    * **Valid Table**: 1-bit per entry, cleared on reset, set when a branch is first resolved.
  * **Prediction Logic**: `pred_taken = valid[idx] && (tag[idx] == pc_tag) && bht[idx][1]`. On a predicted-taken branch, the BTB supplies the target address directly.
  * **Speculative Control-Flow Recovery**: If a misprediction is signaled from the Decode stage, the Fetch stage flushes the speculative instruction from the IF/ID register and redirects the PC to the corrected path.
  * **Counter Update Policy**: On tag match, the 2-bit counter increments/decrements as a standard saturating counter. On tag mismatch (new branch at same index), the counter is reset to `WT` or `WNT` to avoid stale predictions from the previous occupant.
  * **Distributed RAM Tables**: All prediction tables use `(* ram_style = "distributed" *)` for LUT RAM inference, enabling single-cycle combinational reads and synchronous writes.

### **3.6. decode.v (Decode Stage with Early Branch Resolution)**

* **Architectural Role**: Extracts opcodes, register addresses, generates immediates, and executes early branch comparisons using forwarded operand data.
* **Special Features & Competitive Advantages**:
  * **Integrated High-Speed Decode Comparator**: Evaluates branch conditions (BEQ, BNE, BLT, BGE) and unconditional jumps (JAL) combinationally within the ID stage using forwarded register values (`rs1_data_fwd` and `rs2_data_fwd`). This enables 1-cycle branch resolution and immediate misprediction signaling.
  * **Dynamic Misprediction Detection**: Compares the Fetch stage's prediction (`if_id_pred_taken`) against the actual resolution (`actual_branch_taken`). If they differ and no stall is active, `actual_mispredict` is asserted, triggering IF/ID flush and PC redirection.

### **3.7. execute.v (Execute Stage)**

* **Architectural Role**: Computes arithmetic, logical, and address-generation operations.
* **Special Features & Competitive Advantages**:
  * **Three-Source Operand Forwarding Multiplexers**: Features 3-to-1 operational multiplexers on both ALU inputs, allowing the execute stage to run without pipeline stalls by bypassing operands directly from the MEM (ALU result) and WB (writeback data) registers.
  * **Signed Comparison Support**: The SLT operation uses `$signed` wire casting for correct signed less-than comparison.

### **3.8. memory.v (Memory Stage)**

* **Architectural Role**: Coordinates core pipeline access to physical memory subsystems and peripheral address maps.
* **Special Features & Competitive Advantages**:
  * **Dynamic Wait-State Aggregator & Bus Arbiter**: Dynamically decodes CPU address requests using the MSB of the ALU result (`ex_mem_alu_result[31]`). Transactions targeting addresses ≥ `0x8000_0000` are routed to the MMIO controller; all others route to the L1 D-Cache.
  * **Unified Stall Generation**: `stall_mem = (is_cache && !cache_hit) || (is_mmio && !mmio_ready)`. This signal propagates backward through the hazard unit, freezing all upstream pipeline stages and injecting synchronous bubbles to preserve state correctness.

### **3.9. ram.v (Dual-Port Block RAM — Physical Main Memory)**

* **Architectural Role**: Provides the physical Harvard-architecture main memory backing both the L1 I-Cache and L1 D-Cache via independent read/write ports.
* **Special Features & Competitive Advantages**:
  * **Dual-Port Harvard Architecture**: Two independent BRAM arrays — `iram[0:1023]` (4 KB instruction memory) and `dram[0:1023]` (4 KB data memory) — synthesized as Block RAM (`(* ram_style = "block" *)`).
  * **Port A (Instruction)**: Synchronous read-only port connected to the L1 I-Cache. Provides 1-cycle read latency with `readya` handshake signal.
  * **Port B (Data)**: Synchronous read/write port connected to the L1 D-Cache. Supports simultaneous read and write with `readyb` handshake.
  * **Hex Initialization**: Instruction memory is initialized at synthesis/simulation time via `$readmemh(INIT_HEX, iram)`, loading the compiled assembly program.

### **3.10. regfile.v (Register File)**

* **Architectural Role**: Manages the 32 architectural registers of the RISC-V ISA.
* **Special Features & Competitive Advantages**:
  * **Distributed RAM Inference**: Synthesized using `(* ram_style = "distributed" *)`, mapping to LUT-based RAM primitives for minimum-latency combinational reads.
  * **Internal Write-to-Read Bypass (Combinational Bypassing)**: If the read address matches the active write address and `reg_write` is asserted, the writeback data is forwarded directly to the read output, eliminating register-file read hazards without requiring structural pipeline stalls.
  * **Hardwired x0**: Register x0 unconditionally reads as `32'h0` and writes are suppressed.

### **3.11. writeback.v (Writeback Stage)**

* **Architectural Role**: Commits data back to the register file.
* **Special Features & Competitive Advantages**:
  * **Multi-Source Bus Consolidation**: Purely combinational multiplexer routing three data streams: ALU result (`2'b00`), memory read data (`2'b01`), and PC+4 link address (`2'b10`). Drives both the RegFile write port and the WB forwarding bus used by the hazard unit.

### **3.12. test\_risc.v (System-Level Testbench)**

* **Architectural Role**: Simulates the system-level environment with self-checking verification and performance instrumentation.
* **Special Features & Competitive Advantages**:
  * **Golden-Value Self-Checking**: Maintains a precomputed expected-value array for all 31 architectural registers. After program completion, automatically compares every register against its golden reference and reports PASS/FAIL with zero-tolerance bit-exact verification.
  * **Performance Counter Instrumentation**: Tracks total cycles, retired instructions, branch resolutions, and branch mispredictions in real-time. Computes and reports IPC, branch predictor accuracy, and instruction retirement rate.
  * **Completion Detection**: Monitors the instruction fetch address and triggers final verification after `imem_addr >= 356` settles for 5 consecutive clock cycles — detecting program completion without relying on magic addresses or timeout-only termination.
  * **Real-Time Writeback Logging**: Intercepts every register writeback transaction and logs it with simulation timestamps to both the console and `results.txt`.

## **4\. Advanced Engineering Solutions & Design Trade-offs**

### **Dynamic Branch Prediction vs. Static Prediction**

* **Trade-off**: A static "always not taken" predictor is trivial to implement but incurs a misprediction penalty on every taken branch. A dynamic predictor adds hardware cost (BHT/BTB/Tag storage) but learns branch behavior at runtime.
* **Implementation**: This core uses a 256-entry dynamic predictor with 2-bit saturating counters. The predictor is indexed in the Fetch stage and trains from the Decode stage's resolution output. Aliasing protection via tag comparison prevents false-positive predictions from unrelated branches mapping to the same index. The measured branch prediction accuracy is **87%** (74 correct / 85 total branches), achieving **0-cycle penalty** on correct predictions and **1-cycle penalty** on mispredictions.

### **Early Branching vs. Critical Path Frequency**

* **Trade-off**: Resolving branches in the Decode stage (ID) reduces the branch misprediction penalty to 1 cycle, compared to 2 cycles when resolved in the Execute stage (EX).
* **Implementation**: The branch target calculation and comparison logic operates in the ID stage using forwarded operands from the hazard unit. Because comparison depends on the output of the forwarding network, this extends the combinatorial critical path. The resulting critical path (11 logic levels through instruction decode → branch comparison → BHT update) achieves timing closure at 125 MHz with 1.685 ns positive slack.

### **Hardware-Managed Interlocking vs. Compiler-Inserted NOPs**

* **Trade-off**: Standard academic designs often offload hazard resolution to the compiler (by requiring NOP instructions).
* **Implementation**: This core implements a hardware-managed interlock and forwarding unit. It combinationally resolves hazards, maximizing IPC (Instructions Per Cycle) and maintaining absolute binary compatibility with standard RISC-V toolchains.

### **Split L1 Cache Hierarchy vs. Unified Cache**

* **Trade-off**: A unified L1 cache is simpler but creates structural hazards when the pipeline needs to fetch an instruction and access data simultaneously. A split (Harvard) cache eliminates this conflict at the cost of duplicated cache control logic.
* **Implementation**: This design uses independent I-Cache and D-Cache modules, each with their own FSM, tag/data/valid arrays, and dedicated BRAM ports. This enables fully concurrent instruction fetch and data access, eliminating structural stalls between the Fetch and Memory stages.

### **Write-Through vs. Write-Back Cache Policy**

* **Trade-off**: Write-back reduces memory bus traffic but requires dirty-bit tracking and complex eviction logic. Write-through is simpler and guarantees memory coherence at the cost of higher bus utilization.
* **Implementation**: The D-Cache uses a Write-Through + Write-Allocate policy. Every store operation that hits the cache simultaneously updates both the cache line and main memory. This simplifies the design while maintaining strict coherence — critical for correct MMIO operation.

## **5\. Supported Instruction Set (RV32I Subset — 19 Instructions)**

| Instruction | Type | Opcode | Funct3 | Funct7 | Operation |
| :--- | :---: | :---: | :---: | :---: | :--- |
| `ADD` | R | `0110011` | `000` | `0000000` | rd ← rs1 + rs2 |
| `SUB` | R | `0110011` | `000` | `0100000` | rd ← rs1 − rs2 |
| `AND` | R | `0110011` | `111` | `0000000` | rd ← rs1 & rs2 |
| `OR` | R | `0110011` | `110` | `0000000` | rd ← rs1 \| rs2 |
| `XOR` | R | `0110011` | `100` | `0000000` | rd ← rs1 ⊕ rs2 |
| `SLT` | R | `0110011` | `010` | `0000000` | rd ← (rs1 <ₛ rs2) ? 1 : 0 |
| `ADDI` | I | `0010011` | `000` | — | rd ← rs1 + imm |
| `ANDI` | I | `0010011` | `111` | — | rd ← rs1 & imm |
| `ORI` | I | `0010011` | `110` | — | rd ← rs1 \| imm |
| `XORI` | I | `0010011` | `100` | — | rd ← rs1 ⊕ imm |
| `SLTI` | I | `0010011` | `010` | — | rd ← (rs1 <ₛ imm) ? 1 : 0 |
| `LW` | I | `0000011` | `010` | — | rd ← MEM[rs1 + imm] |
| `SW` | S | `0100011` | `010` | — | MEM[rs1 + imm] ← rs2 |
| `BEQ` | B | `1100011` | `000` | — | if (rs1 == rs2) PC ← PC + imm |
| `BNE` | B | `1100011` | `001` | — | if (rs1 ≠ rs2) PC ← PC + imm |
| `BLT` | B | `1100011` | `100` | — | if (rs1 <ₛ rs2) PC ← PC + imm |
| `BGE` | B | `1100011` | `101` | — | if (rs1 ≥ₛ rs2) PC ← PC + imm |
| `JAL` | J | `1101111` | — | — | rd ← PC + 4; PC ← PC + imm |
| `LUI` | U | `0110111` | — | — | rd ← imm << 12 |

## **6\. Memory Map Specifications**

| Base Address Range | Target Device | Access Width | Description |
| :--- | :--- | :--- | :--- |
| `0x0000_0000` – `0x7FFF_FFFF` | Instruction/Data RAM | 32-bit | Primary execution and data space routed through the L1 Caches. |
| `0x8000_0000` | SPI Data Register | 8-bit | Writes enqueue data to the TX FIFO; reads retrieve data from the RX FIFO. |
| `0x8000_0004` | SPI Control/Status | 32-bit | Read/Write access to status flags and CPOL/CPHA configurations. |

### **SPI Control & Status Register Bit Mapping (0x8000\_0004):**

\[31:6\] Reserved (Hardwired to 0)
\[5\]    RX Valid (Read-Only)
\[4\]    Busy Status (Read-Only)
\[3\]    TX FIFO Empty (Read-Only)
\[2\]    TX FIFO Full (Read-Only)
\[1\]    CPOL (Clock Polarity, Read/Write)
\[0\]    CPHA (Clock Phase, Read/Write)

## **7\. FPGA Implementation Results**

Implementation was performed using Vivado v.2026.1 targeting the **Kintex-7 xc7k325tfbv900-3** (Speed Grade -3, Extended temperature grade).

### **7.1. Timing Summary**

| Metric | Value | Status |
| :--- | :--- | :---: |
| Target Clock Period | 8.000 ns (125 MHz) | — |
| Worst Negative Slack (WNS) | +1.685 ns | ✅ MET |
| Total Negative Slack (TNS) | 0.000 ns | ✅ MET |
| Worst Hold Slack (WHS) | +0.075 ns | ✅ MET |
| Worst Pulse Width Slack (WPWS) | +3.326 ns | ✅ MET |
| Failing Endpoints | 0 / 6,204 | ✅ |
| **Maximum Achievable Frequency** | **≈ 158 MHz** (Tmin = 6.315 ns) | — |

**Critical Setup Path**: `u_fetch/if_id_inst_reg[4]/C` → `u_fetch/bht_table_reg` — 11 logic levels, 5.782 ns data path delay (16.9% logic, 83.1% routing).

### **7.2. Resource Utilization**

| Resource | Used | Available | Utilization |
| :--- | ---: | ---: | ---: |
| Slice LUTs | 2,072 | 203,800 | 1.02% |
| ↳ LUT as Logic | 1,548 | 203,800 | 0.76% |
| ↳ LUT as Distributed RAM | 524 | 64,000 | 0.82% |
| Slice Registers (FFs) | 987 | 407,600 | 0.24% |
| Block RAM (RAMB36E1) | 2 | 445 | 0.45% |
| DSP48E1 | 0 | 840 | 0.00% |
| Bonded IOBs | 6 | 500 | 1.20% |
| CARRY4 | 67 | 50,950 | 0.13% |
| F7/F8 Muxes | 124 | 203,800 | 0.06% |
| BUFG | 1 | 32 | 3.13% |

### **7.3. Power Analysis**

| Power Component | Value |
| :--- | ---: |
| **Total On-Chip Power** | **202 mW** |
| Dynamic Power | 44 mW (21.8%) |
| Static Power | 158 mW (78.2%) |
| Junction Temperature | 25.4°C |
| Thermal Margin | 74.6°C |

**Dynamic Power by Module:**

| Module | Function | Power | % Dynamic |
| :--- | :--- | ---: | ---: |
| `u_fetch` | Branch Predictor + Fetch | 16 mW | 36.4% |
| `u_execute` | ALU + Pipeline Regs | 8 mW | 18.2% |
| `u_decode` | Decode + Branch Resolution | 6 mW | 13.6% |
| `spi_ctrl` | SPI Master Controller | 2 mW | 4.5% |
| `u_dcache` | L1 Data Cache | 2 mW | 4.5% |
| `u_icache` | L1 Instruction Cache | 2 mW | 4.5% |
| `u_memory` | Memory Stage | 2 mW | 4.5% |
| `u_ram` | Dual-Port BRAM | 2 mW | 4.5% |
| `u_regfile` | Register File | 2 mW | 4.5% |

## **8\. Simulation & Verification Results**

### **8.1. Test Program**

The verification suite uses a 6-part self-checking benchmark (`imem.s`) covering:

1. **ALU & RAW Hazard Interlocks** — Back-to-back arithmetic testing pipeline forwarding
2. **L1 Data Cache Store/Load** — Cache miss/hit sequences and load-use hazard stalls
3. **Fibonacci Iterative Loop** — 14-term computation exercising branch predictor training
4. **Euclidean GCD Algorithm** — GCD(252, 105) = 21 with conditional branches and jumps
5. **Modular Multiplication Loop** — (12 × 15) + 25 = 205 via accumulation loop
6. **Bitwise Signatures & Checksum** — LUI/ORI patterns and 30-register cumulative checksum

### **8.2. Results**

```
ALL 31 REGISTER CHECKS PASSED — 0 ERRORS
Cumulative Checksum (x31) = 0xAEEABACA ✓
```

| Performance Metric | Value |
| :--- | ---: |
| Total Cycles | 536 |
| Instructions Retired | 180 |
| IPC | 0.335 |
| Branches Resolved | 85 |
| Branch Mispredicts | 11 |
| **Branch Predictor Accuracy** | **87%** |

## **9\. Compilation, Simulation, and Verification Guide**

The verification suite utilizes Icarus Verilog (iverilog) for architectural compilation, the vvp simulation runtime engine, and GTKWave for timing diagram and waveform analysis.

### **System Verification Prerequisites:**

* **Compiler**: Icarus Verilog (v10.0 or higher recommended)
* **Waveform Viewer**: GTKWave
* **FPGA Synthesis** (optional): AMD Vivado 2026.1+

### **Verification Execution Pipeline:**

Execute the following commands in your terminal to compile the RTL, run the testbench verification suite, and open the waveform output:

```bash
# Navigate to the project's parent directory
cd /path/to/Projects

# Compile RTL, peripherals, and testbench; execute simulation; view waveforms
iverilog -o RV32I/sim.out  \
         RV32I/src/*.v     \
         SPI/src/*.v       \
         RV32I/test_risc.v && \
vvp RV32I/sim.out && \
gtkwave RV32I/dump_risc.vcd
```

This compilation flow ensures that all modules — including the core pipeline, hazard detection, cache hierarchy, memory subsystems, and SPI master — are compiled and verified.
