# **High-Performance pipelined RV32I Processor Core with L1 Cache and SPI Peripheral**

## **Design Specification, Verification, and Advanced Microarchitectural Analysis**

## **1\. Executive Summary**

This repository contains a synthesizable, first-principles Verilog implementation of an optimized **5-stage pipelined RISC-V (RV32I) Processor Core**. Engineered with a focus on high-throughput, low-latency microarchitectural solutions, this design is tailored for embedded System-on-Chip (SoC) deployments.

Unlike standard textbook academic implementations, this processor integrates a cycle-accurate direct-mapped L1 Data Cache, an early branch-resolution mechanism in the Decode stage, and a robust structural interlock and data hazard unit. Additionally, the system includes a Memory-Mapped I/O (MMIO) bridge interfacing the CPU to a fully functional, configurable SPI Master peripheral.

## **2\. Microarchitectural Topology**

The processor implements a classic RISC-V 5-stage pipeline, deeply modified to support high-speed operation and minimal control flow latency:

```null
[Fetch] ----> [Decode] ----> [Execute] ----> [Memory] ----> [Writeback]  
   |             |              |               |               |       
   |<----------------[Hazard & Forwarding Unit]---------------->|       
   |             |                              |                       
 (IF_Stall)   (Early Branch/Fwd)           (Cache/MMIO Stall)           
```

### **Stage Pipeline Organization:**

1. **Instruction Fetch (IF)**: Incorporates PC generation, speculative sequential fetching, and instantaneous control-flow redirection upon branch misprediction signals.  
2. **Instruction Decode (ID)**: Houses register file read ports, immediate generation, instruction decoding, and an **early branch evaluation arithmetic unit**.  
3. **Execute (EX)**: Performs execution of arithmetic, logic, and shift operations using an optimized, parameterized Arithmetic Logic Unit (ALU).  
4. **Memory Access (MEM)**: Interfaces with the L1 Data Cache and the MMIO arbiter. Manages transaction completion and wait-state generation.  
5. **Writeback (WB)**: Selects between the executing ALU result, memory-read data, or program counter link values to commit state back to the architectural register file.

## **3\. Comprehensive File Breakdown & Industry-Grade Features**

Standard academic processors often bypass physical memory latencies, resolve control flow deep in the pipeline (incurring massive stall penalties), or omit real-world peripheral integration. Below is an exhaustive breakdown of each source file, highlighting the advanced design features that distinguish this project.

### **3.1. system.v (System Top-Level Integration)**

* **Architectural Role**: Integrates the pipelined core, the hazard unit, the L1 data cache, and the SPI Master controller onto a unified SoC interconnect.  
* **Special Features & Competitive Advantages**:  
  * **Unified CPU-Peripheral SoC Interconnect**: Implements a dedicated memory address-space decoder that seamlessly routes memory transactions to either the L1 Cache (for cacheable RAM spaces) or the MMIO arbiter (for non-cacheable device address spaces).  
  * **Configurable Clock-Phase (CPHA) and Clock-Polarity (CPOL) Registers**: Standard projects hardwire SPI timing configurations. This design exposes registers directly mapped to 0x8000\_0004 that allow the CPU to dynamically configure CPOL and CPHA configurations on-the-fly, supporting diverse external slave peripherals.  
  * **Dynamic Status Flags Register**: Offers a 32-bit read-only status port detailing the state of the SPI FIFOs (Full, Empty, Busy, RX-Valid).

### **3.2. hazard.v (Hazard Detection and Forwarding Unit)**

* **Architectural Role**: Combinationally evaluates data dependencies across the pipeline and orchestrates structural flushes and pipeline freezes.  
* **Special Features & Competitive Advantages**:  
  * **Decode-Stage Early Branch Bypassing**: Resolving branches in the Decode (ID) stage drastically reduces branch penalties to 1 cycle. However, this introduces complex data hazards if the branch registers are being updated by preceding active instructions. hazard.v resolves this by incorporating a *dedicated bypassing network* (rs1\_data\_fwd, rs2\_data\_fwd) that pulls operands directly from the MEM or WB stages into the ID stage comparators before they are written to the register file.  
  * **Interlocking Logic for Load-Use and Branch Hazards**:  
    * **Load-Use Interlock**: Detects when a decoded instruction reads a register undergoing a load operation in the execution stage and asserts a 1-cycle stall bubble.  
    * **Branch-Data Interlock**: Detects when a branch instruction depends on an active instruction whose output is not yet available at the MEM stage, initiating the required pipeline freeze combinationally.

### **3.3. cache.v (L1 Direct-Mapped Data Cache)**

* **Architectural Role**: Provides a 64-entry, direct-mapped L1 cache for low-latency variable read and write operations.  
* **Special Features & Competitive Advantages**:  
  * **Cycle-Accurate Latency Emulation FSM**: Rather than utilizing idealized single-cycle RAM models, cache.v implements a realistic memory access protocol with a cycle-accurate Finite State Machine (STATE\_IDLE, STATE\_FETCH, STATE\_READY).  
  * **Synchronous Hardware Wait-State Signaling**: On an L1 Cache miss, the FSM stalls the pipeline for MEM\_LATENCY (configurable, default is 4 cycles) to fetch data from the next level of memory. It utilizes a custom handshaking state (STATE\_READY) to assert a single-cycle hold, ensuring that execution registers properly latch retrieved memory data before resuming instruction flow.  
  * **Write-Hit Cache Allocation**: Supports real-time cache updates on write operations when a tag match is present.

### **3.4. fetch.v (Fetch Stage)**

* **Architectural Role**: Drives the program counter (PC) logic and coordinates instruction retrieval from memory.  
* **Special Features & Competitive Advantages**:  
  * **Speculative Control-Flow Recovery Coordination**: Interfaces directly with the early branch-resolution mechanism. If a branch is mispredicted in the ID stage, fetch.v flushes the speculative instruction loaded in the IF/ID register on the next rising clock edge and immediately redirects execution to the correct instruction path, ensuring zero-cycle bubble recovery.

### **3.5. decode.v (Decode Stage)**

* **Architectural Role**: Extracts opcodes, register addresses, and executes early branch comparisons.  
* **Special Features & Competitive Advantages**:  
  * **Integrated High-Speed Decode Comparator**: Standard decoders are passive instruction parsers. This implementation integrates parallel comparator blocks directly within the ID stage. It compares forwarded register values (rs1\_data\_fwd and rs2\_data\_fwd) to determine branch outcomes (such as equal, less-than, or greater-than) combinationally, signaling mispredictions instantly to the fetch unit.

### **3.6. execute.v (Execute Stage)**

* **Architectural Role**: Computes arithmetic, logical, and address-generation operations.  
* **Special Features & Competitive Advantages**:  
  * **Three-Source Operand Forwarding Multiplexers**: Features 3-to-1 operational multiplexers on both ALU inputs, allowing the execute stage to run without pipeline stalls by bypassing operands directly from the MEM (ALU result) and WB (writeback data) registers.

### **3.7. memory.v (Memory Stage)**

* **Architectural Role**: Coordinates core pipeline access to physical memory subsystems and peripheral address maps.  
* **Special Features & Competitive Advantages**:  
  * **Dynamic Wait-State Aggregator & Bus Arbiter**: Dynamically decodes CPU address requests. If a transaction targets the Cache or MMIO and either interface is busy (e.g., L1 cache fetch or slow MMIO execution), memory.v generates a unified stall\_mem signal. This signal propagates backward, freezing state registers in the IF, ID, and EX stages, and injecting synchronous bubbles into the pipeline to preserve state correctness.

### **3.8. regfile.v (Register File)**

* **Architectural Role**: Manages the 32 architectural registers of the RISC-V ISA.  
* **Special Features & Competitive Advantages**:  
  * **Internal Write-to-Read Bypass (Combinational Bypassing)**: Academic register files suffer from hazards when writing to and reading from the same register on the same clock cycle. This design includes combinational bypass paths: if the read address matches the active write address, the writeback data is forwarded directly to the read output, eliminating register-file read hazards without requiring structural pipeline stalls.

### **3.9. writeback.v (Writeback Stage)**

* **Architectural Role**: Commits data back to the register file.  
* **Special Features & Competitive Advantages**:  
  * **Multi-Source Bus Consolidation**: Routes and multiplexes multiple data streams—including ALU outputs, cache reads, and PC link registers—ensuring correct register write-address alignment.

### **3.10. test\_risc.v (System-Level Testbench)**

* **Architectural Role**: Simulates the system-level environment, providing instruction memory and serial peripheral loopbacks.  
* **Special Features & Competitive Advantages**:  
  * **Simulated Clock-Level Handshaking & Peripheral Loopback**: Rather than simple clock tick assertions, this testbench dynamically monitors and validates wait-state behavior, cache-miss penalties, and validates the SPI serial lines via dynamic functional loopbacks to ensure robust hardware-level verification.

## **4\. Advanced Engineering Solutions & Design Trade-offs**

During an interview, showcasing an understanding of microarchitectural trade-offs is essential. This design implements several deliberate trade-offs optimized for real-world constraints:

### **Early Branching vs. Critical Path Frequency**

* **Trade-off**: Resolving branches in the Decode stage (ID) reduces the branch misprediction penalty to 1 cycle, compared to 2 cycles when resolved in the Execute stage (EX).  
* **Implementation**: This optimization shifts the branch target calculation and comparison logic into the ID stage. Because comparison now depends on the output of the forwarding unit, this extends the combinatorial critical path of the ID stage. To mitigate potential timing closure issues, the register file bypass and early forwarding logic have been optimized to avoid unnecessary nested multiplexing.

### **Hardware-Managed Interlocking vs. Compiler-Inserted NOPs**

* **Trade-off**: Standard academic designs often offload hazard resolution to the compiler (by requiring NOP instructions).  
* **Implementation**: This core implements a hardware-managed interlock and forwarding unit. It combinationally resolves hazards, maximizing IPC (Instructions Per Cycle) and maintaining absolute binary compatibility with standard RISC-V toolchains.

### **Direct-Mapped L1 Cache vs. Multi-Cycle Stalls**

* **Trade-off**: Implementing an L1 Cache introduces multi-cycle stalls on cache misses, which complicates pipeline design.  
* **Implementation**: The pipeline utilizes a centralized memory stall signal (stall\_mem). When a cache miss occurs, the cache FSM asserts this stall, which freezes the previous stage registers while allowing the writeback stage to complete. This ensures that a stall in the memory system does not cause functional errors or lose pipeline state.

## **5\. Memory Map Specifications**

| Base Address Range | Target Device | Access Width | Description |
| :---- | :---- | :---- | :---- |
| 0x0000\_0000 \- 0x7FFF\_FFFF | Instruction/Data RAM | 32-bit | Primary execution and data space routed through the L1 Cache. |
| 0x8000\_0000 | SPI Data Register | 8-bit | Writes enqueue data to the TX FIFO; reads retrieve data from the RX FIFO. |
| 0x8000\_0004 | SPI Control/Status | 32-bit | Read/Write access to status flags and CPOL/CPHA configurations. |

### **SPI Control & Status Register Bit Mapping (0x8000\_0004):**

\[31:6\] Reserved (Hardwired to 0\)  
\[5\]    RX Valid (Read-Only)  
\[4\]    Busy Status (Read-Only)  
\[3\]    TX FIFO Empty (Read-Only)  
\[2\]    TX FIFO Full (Read-Only)  
\[1\]    CPOL (Clock Polarity, Read/Write)  
\[0\]    CPHA (Clock Phase, Read/Write)

## **6\. Compilation, Simulation, and Verification Guide**

The verification suite utilizes Icarus Verilog (iverilog) for architectural compilation, the vvp simulation runtime engine, and gtkwave for timing diagram and waveform analysis.

### **System Verification Prerequisites:**

* **Compiler**: Icarus Verilog (v10.0 or higher recommended)  
* **Waveform Viewer**: GTKWave

### **Verification Execution Pipeline:**

Execute the following commands in your terminal to compile the RTL, run the testbench verification suite, and open the waveform output:

\# Navigate to the project environment  

```bash
cd ~/Codes/verilog
```

\# Compile RTL, peripherals, and testbench, execute simulation run, and view waveforms  

```bash
iverilog -o RV32I/sim.out  
         RV32I/src/*.v  
         SPI/src/*.v  
         RV32I/test_risc.v &&  
vvp RV32I/sim.out &&  
gtkwave RV32I/dump_risc.vcd
```

This compilation flow ensures that all modules—including the core pipeline, hazard detection, memory subsystems, and SPI master—are compiled and verified.
