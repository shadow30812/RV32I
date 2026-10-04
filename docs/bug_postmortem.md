# RV32I Bug Postmortem

Five defects in v1.0, found on Oct 4, 2026 with directed programs and fixed the same day. The legacy checksum benchmark passed throughout. It checks only final register values, and its access patterns never triggered any of them. Each defect has a regression program in `tests/programs/`. All of them fail on the pre-fix RTL and pass after the fix.

Run all of them with `tests/run_regression.sh`.

---

## 1. JAL link value forwarded from MEM is wrong

| | |
| :--- | :--- |
| **Symptom** | An instruction that reads the link register right after a correctly predicted JAL gets 0 instead of PC+4. In `bug1_jal_link_forward`, x2 = 0 and x12 = 16 (expected 16 and 48). |
| **Exposing test** | `tests/programs/bug1_jal_link_forward.s`: a JAL in a loop, so the BTB predicts it from the second iteration on, followed by `addi x2, x1, 0` at the target. |
| **Root cause** | For a JAL, `ex_mem_alu_result` held the ALU output. The JAL's rs1/rs2 fields are immediate bits, so that output was garbage (here x0 + x8). The MEM-stage forward (`mem_fwd_data = ex_mem_alu_result` in `system.v`) passed it on. Writeback was correct, because it selects `mem_wb_pc + 4`. |
| **Why it escaped** | The first execution of a JAL is mispredicted. The redirect bubble pushes the dependent instruction back to WB forwarding, which is correct. The benchmark never used a link register right after a predicted JAL. |
| **Fix** | `execute.v`: when `id_wb_sel == 2'b10`, the EX/MEM result register takes `id_ex_pc + 4`, so every forward of a JAL's result is the link value. JALR must reuse this path when it is added. |

## 2. D-cache write-through used the next instruction's address and data

| | |
| :--- | :--- |
| **Symptom** | After a store hit, main memory receives the wrong word, at the wrong address. A later conflict miss reloads stale data. In `bug2_dcache_writethrough`, RAM[0] becomes 0x0 instead of 0x222, and `lw x9, 0(x0)` after an eviction returns 0. |
| **Exposing test** | `tests/programs/bug2_dcache_writethrough.s`: a store miss, then a store hit to the same word, then a load to a conflicting address (256), then a reload of address 0. |
| **Root cause** | On a write hit, `dcache.v` registered `mem_req`/`mem_wr_en` for the next cycle, but drove `mem_addr = addr[11:2]` and `mem_wdata = wdata` combinationally. By the time RAM saw the request, the store had left MEM, and the address and data belonged to whatever came next (a bubble here, so address 0 and data 0). A second fault: `readyb` is just "enabled last cycle", not tied to a particular request. With the address fixed, a load miss right after a write-through could accept the write's `readyb` and capture data from the wrong address. |
| **Why it escaped** | The cache line itself was updated correctly, so every later hit read the right value. The corrupted RAM word only shows after a conflict eviction. The benchmark's few data words never conflict. |
| **Fix** | `dcache.v`: `mem_addr_r` and `mem_wdata_r` are latched in the same cycle as the request (write hits and misses) and drive the RAM port. A new `issued` flag makes FETCH ignore `mem_ready` in its first cycle, so only the response to its own request completes the fill. Miss latency is unchanged. |

## 3. Branch resolved on stale operands during a branch-data stall

| | |
| :--- | :--- |
| **Symptom** | A branch that depends on the instruction right before it can go the wrong way. In `bug3_stale_branch`, iterations 2 to 5 take the wrong path, giving x8 = 7 and x9 = 8 (expected 9 and 6). |
| **Exposing test** | `tests/programs/bug3_stale_branch.s`: `andi x5, x6, 1` followed directly by `beq x5, x0, even`, in a warm loop, so no I-cache stall masks the problem. |
| **Root cause** | While the branch waits in ID for its operand (`branch_stall`), its comparison uses the stale register-file value. `actual_mispredict` was masked only by `stall_id` (`stall_mem \|\| stall_icache`), not by the ID hazard stall. When the stale outcome disagreed with the prediction, decode flagged a mispredict. Fetch then replaced IF/ID with a NOP, which squashed the branch, and redirected down the stale path. |
| **Why it escaped** | On cold code, the I-cache miss for the next fetch raised `stall_icache` in the same cycle and masked the mispredict. The bug only appears in warm loops. In the benchmark's loops, the stale outcome happened to agree with the prediction. |
| **Fix** | `hazard.v` exports `id_hazard_stall`; `system.v` wires it to a new `hold` input on `decode.v`. A branch resolves only when `!stall && !hold`. The regression testbench also asserts this on every cycle. |

## 4. JAL immediate bits treated as source registers

| | |
| :--- | :--- |
| **Symptom** | False stalls. Combined with defect 3, a mispredicted JAL could be squashed and its link register never written. In `bug4_jal_false_dependency`, x1 = 0 and x20 = 0 (expected 16 and 16). |
| **Exposing test** | `tests/programs/bug4_jal_false_dependency.s`: `addi x8, ...` then `jal x1, tgt`, whose rs2 field encodes x8. The JAL runs for the first time (not yet predicted) while its fall-through line is already in the I-cache. |
| **Root cause** | Decode reported `rs1_addr`/`rs2_addr` straight from the instruction bits for every opcode, and the hazard unit's `id_is_branch` included JAL. A JAL's immediate bits therefore matched producer registers and raised `branch_stall`. The same raw fields caused false load-use stalls for I-type, LUI and JAL instructions. |
| **Why it escaped** | It needs a specific immediate encoding, a matching producer right before the JAL, and a warm fall-through line. |
| **Fix** | `decode.v`: `rs1_addr` is reported only when the instruction reads rs1 (not LUI or JAL), and `rs2_addr` only for R-type, SW and branches. Otherwise they are x0, which never creates a hazard. The hazard unit now takes a raw `id_is_ctrl` signal from decode, which also avoids a combinational loop with the qualified resolve signal. Instructions added later (JALR, AUIPC, shifts, loads, stores) must be added to these lists. |

## 5. Predictor trained on every cycle a branch sat in ID

| | |
| :--- | :--- |
| **Symptom** | The BHT/BTB was updated several times per branch, sometimes with stale outcomes. The testbench branch count was inflated in the same way: 85 reported against 43 real branches and jumps. That made the published accuracy 87% instead of 74%. |
| **Exposing test** | The `B` (branch-resolution count) line in every `.exp` file. The pre-fix RTL reports 83 on the benchmark against the expected 43. |
| **Root cause** | `actual_branch_valid` was `is_branch \|\| is_jal`: high on every cycle the branch sat in ID, including I-cache, memory and hazard stall cycles. `fetch.v` updates the tables whenever it is high. |
| **Fix** | `decode.v`: `actual_branch_valid = id_is_ctrl && !stall && !hold`, which pulses once per branch, in the cycle it resolves and leaves ID. `fetch.v` is unchanged. |

---

## Measurement corrections (not RTL defects)

- **Branch count:** `test_risc.v` now counts each branch or jump once, using the corrected `actual_branch_valid`.
- **Instruction count:** it now counts instructions as they leave ID, so branches are no longer left out. A new `ifid_valid` flag skips reset and flush NOPs.
- **Benchmark results:** 219 instructions, 43 branches and jumps, 11 mispredicts, 74% accuracy, IPC 0.408, 536 cycles. The instruction and branch counts match a reference ISS.

## Repository fixes

- **`ram.v`:** `INIT_HEX` defaulted to an absolute path that no longer existed after the project moved under `EE Core`. It now defaults to `imem.hex`, which Vivado resolves from the imported source.
- **`test_risc.v`:** overrides the hex path to `RV32I/imem.hex` for the documented flow.
- **`cmd.txt`:** now runs from `Projects/EE Core`.
