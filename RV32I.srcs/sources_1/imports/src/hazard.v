/*
 * Hazard Detection & Forwarding Unit with 1-cycle stall for interlocking
 */

module hazard (
    // Global Memory Control
    input wire stall_mem,  // High when Cache or MMIO is busy

    // ID Stage Inputs
    input wire [ 4:0] id_ex_rs1_addr,
    input wire [ 4:0] id_ex_rs2_addr,
    input wire        id_is_branch,     // From Decode (act_branch_valid)
    input wire [31:0] id_rs1_data_reg,  // Raw data from Register File
    input wire [31:0] id_rs2_data_reg,

    // EX Stage Inputs
    input wire [4:0] ex_mem_rs1_addr,
    input wire [4:0] ex_mem_rs2_addr,
    input wire [4:0] ex_mem_rd_addr,
    input wire ex_mem_read,
    input wire ex_reg_write,
    input wire [31:0] ex_alu_result,

    // MEM Stage Inputs
    input wire [4:0] mem_wb_rd_addr,
    input wire mem_reg_write,
    input wire mem_mem_read,
    input wire [31:0] mem_fwd_data,  // Data from MEM stage (ALU or Read Data)

    // WB Stage Inputs
    input wire [4:0] wb_rd_addr,
    input wire wb_reg_write,
    input wire [31:0] wb_fwd_data,  // Final writeback data

    // Forwarding to EX Stage (ALU)
    output reg [1:0] fwd_a,
    output reg [1:0] fwd_b,

    // Forwarding directly to ID Stage (Branch Condition Logic)
    output reg [31:0] rs1_data_fwd,
    output reg [31:0] rs2_data_fwd,

    // Pipeline Stalls & Flushes
    output wire stall_if,
    output wire stall_id,
    output wire stall_ex,
    output wire flush_ex
);

  // Forwarding to EX Stage (ALU Operands)
  // 00 = RegFile (No Hazard), 01 = WB Stage, 10 = MEM Stage
  always @(*) begin
    // Forward A (rs1)
    if (mem_reg_write && (mem_wb_rd_addr != 0) && (mem_wb_rd_addr == ex_mem_rs1_addr))
      fwd_a = 2'b10;
    else if (wb_reg_write && (wb_rd_addr != 0) && (wb_rd_addr == ex_mem_rs1_addr)) fwd_a = 2'b01;
    else fwd_a = 2'b00;

    // Forward B (rs2)
    if (mem_reg_write && (mem_wb_rd_addr != 0) && (mem_wb_rd_addr == ex_mem_rs2_addr))
      fwd_b = 2'b10;
    else if (wb_reg_write && (wb_rd_addr != 0) && (wb_rd_addr == ex_mem_rs2_addr)) fwd_b = 2'b01;
    else fwd_b = 2'b00;
  end

  // Forwarding to ID Stage (Branch Resolution)
  always @(*) begin
    // Forward rs1
    if (mem_reg_write && (mem_wb_rd_addr != 0) && (mem_wb_rd_addr == id_ex_rs1_addr))
      rs1_data_fwd = mem_fwd_data;
    else if (wb_reg_write && (wb_rd_addr != 0) && (wb_rd_addr == id_ex_rs1_addr))
      rs1_data_fwd = wb_fwd_data;
    else rs1_data_fwd = id_rs1_data_reg;

    // Forward rs2
    if (mem_reg_write && (mem_wb_rd_addr != 0) && (mem_wb_rd_addr == id_ex_rs2_addr))
      rs2_data_fwd = mem_fwd_data;
    else if (wb_reg_write && (wb_rd_addr != 0) && (wb_rd_addr == id_ex_rs2_addr))
      rs2_data_fwd = wb_fwd_data;
    else rs2_data_fwd = id_rs2_data_reg;
  end

  // Interlocking (Stalls and Flushes)
  // A. Standard Load-Use Hazard
  wire load_use_stall = ex_mem_read && (ex_mem_rd_addr != 0) && 
    ((ex_mem_rd_addr == id_ex_rs1_addr) || (ex_mem_rd_addr == id_ex_rs2_addr));

  // B. Branch Data Hazard
  // ID -> EX is not possible combinationally for branches, wait till MEM
  // Load from MEM is not allowed, wait till WB
  wire branch_stall = id_is_branch && (
    (ex_reg_write && (ex_mem_rd_addr != 0) && ((ex_mem_rd_addr == id_ex_rs1_addr) || 
        (ex_mem_rd_addr == id_ex_rs2_addr))) || 
    (mem_mem_read && (mem_wb_rd_addr != 0) && ((mem_wb_rd_addr == id_ex_rs1_addr) || 
        (mem_wb_rd_addr == id_ex_rs2_addr)))
    );

  wire id_hazard_stall = load_use_stall || branch_stall;  // Stall for either hazard

  // Global Control Line Assignments
  assign stall_if = stall_mem || id_hazard_stall;
  assign stall_id = stall_mem || id_hazard_stall;
  assign stall_ex = stall_mem;
  assign flush_ex = id_hazard_stall && !stall_mem;

endmodule
