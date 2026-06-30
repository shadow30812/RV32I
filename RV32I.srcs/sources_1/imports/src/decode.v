/*
 * Decode Stage with Dynamic Mispredict Detection
 */

module decode #(
    parameter PC_WIDTH = 32
) (
    // Control Signals
    input wire clk,
    input wire rst_n,

    // Pipeline Control (from Hazard Unit)
    input wire stall,
    input wire flush,

    // IF/ID Pipeline Registers
    input wire [PC_WIDTH-1:0] if_id_pc,
    input wire [31:0] if_id_inst,
    input wire if_id_pred_taken,

    // Forwarded Register Data (from Hazard Unit)
    // Actual data redirected from Execute Stage directly
    input wire [31:0] rs1_data_fwd,
    input wire [31:0] rs2_data_fwd,

    // Register Numbers
    output wire [4:0] rs1_addr,
    output wire [4:0] rs2_addr,

    // Branch Resolution (to Fetch Stage)
    output wire actual_branch_valid,
    output wire actual_branch_taken,
    output wire [PC_WIDTH-1:0] actual_target,
    output wire [PC_WIDTH-1:0] actual_pc,
    output wire actual_mispredict,

    // ID/EX Pipeline Registers
    output reg [PC_WIDTH-1:0] id_ex_pc,
    output reg [31:0] id_ex_rs1_data,
    output reg [31:0] id_ex_rs2_data,
    output reg [31:0] id_ex_imm,
    output reg [4:0] id_ex_rd_addr,
    output reg [4:0] id_ex_rs1_addr,
    output reg [4:0] id_ex_rs2_addr,

    // Inter-stage signals (from ID)
    output reg [3:0] id_alu_op,     // ALU operation code
    output reg       id_alu_src,    // 0 = Reg, 1 = Imm for second ALU operand
    output reg       id_mem_read,   // Read from memory?
    output reg       id_mem_write,  // Write to memory?
    output reg       id_reg_write,  // Update register?
    output reg [1:0] id_wb_sel      // Writeback source 
                                    // 00 = ALU Result, 01 = Memory Data, 10 = PC+4
);

  // Instruction Unpacking
  //  31         25 24    20 19    15 14    12 11      7 6      0
  // +-------------+--------+--------+--------+---------+--------+
  // |   funct7    |  rs2   |  rs1   | funct3 |   rd    | opcode |
  // +-------------+--------+--------+--------+---------+--------+
  // |   7 bits    | 5 bits | 5 bits | 3 bits | 5 bits  | 7 bits |
  // +-------------+--------+--------+--------+---------+--------+
  //
  // or replaced by imm[11:0] within if_id_inst[31:20] if I-type

  wire [6:0] opcode = if_id_inst[6:0];
  wire [2:0] funct3 = if_id_inst[14:12];
  wire [6:0] funct7 = if_id_inst[31:25];

  assign rs1_addr = (opcode == 7'b0110111) ? 5'b0 : if_id_inst[19:15];  // Special case- LUI
  assign rs2_addr = if_id_inst[24:20];
  wire [ 4:0] rd_addr = if_id_inst[11:7];

  // Combinational Logic: Immediate Generation
  reg  [31:0] imm_val;
  localparam RV32I_NOA = 32'h0000_0000;

  always @(*) begin
    case (opcode)
      7'b0110111:  // U-Type (LUI)
      imm_val = {if_id_inst[31:12], 12'b0};
      7'b0010011:  // I-Type (ADDI, ANDI)
      imm_val = {{20{if_id_inst[31]}}, if_id_inst[31:20]};
      7'b0000011:  // I-Type (LW)
      imm_val = {{20{if_id_inst[31]}}, if_id_inst[31:20]};
      7'b0100011:  // S-Type (SW)
      imm_val = {{20{if_id_inst[31]}}, if_id_inst[31:25], if_id_inst[11:7]};
      7'b1100011:  // B-Type (BEQ, BNE)
      imm_val = {{20{if_id_inst[31]}}, if_id_inst[7], if_id_inst[30:25], if_id_inst[11:8], 1'b0};
      7'b1101111:  // J-Type (JAL)
      imm_val = {{12{if_id_inst[31]}}, if_id_inst[19:12], if_id_inst[20], if_id_inst[30:21], 1'b0};
      default:  // Failsafe
      imm_val = RV32I_NOA;
    endcase
  end

  // Combinational Logic: Control Unit
  // Stores decoded instructions before passing to Execute Stage @(posedge clk)
  reg ctrl_alu_src;
  reg ctrl_mem_read;
  reg ctrl_mem_write;
  reg ctrl_reg_write;
  reg [1:0] ctrl_wb_sel;
  reg [3:0] ctrl_alu_op;

  // 0000=ADD, 0001=SUB, 0010=AND, 0011=OR, 0100=XOR, 0101=SLT
  always @(*) begin
    ctrl_alu_src   = 1'b0;
    ctrl_mem_read  = 1'b0;
    ctrl_mem_write = 1'b0;
    ctrl_reg_write = 1'b1;
    ctrl_wb_sel    = 2'b00;
    ctrl_alu_op    = 4'b0000;

    case (opcode)
      7'b0110011: begin  // R-Type (Register-Register)
        ctrl_reg_write = 1'b1;
        case (funct3)
          3'b000:  ctrl_alu_op = (funct7[5]) ? 4'b0001 : 4'b0000;
          3'b111:  ctrl_alu_op = 4'b0010;
          3'b110:  ctrl_alu_op = 4'b0011;
          3'b100:  ctrl_alu_op = 4'b0100;
          3'b010:  ctrl_alu_op = 4'b0101;
          default: ctrl_alu_op = 4'b0000;
        endcase
      end

      7'b0010011: begin  // I-Type (Register-Immediate)
        ctrl_reg_write = 1'b1;
        ctrl_alu_src   = 1'b1;
        case (funct3)
          // Encodings map to R-variant of I-type instructions
          3'b000:  ctrl_alu_op = 4'b0000;
          3'b111:  ctrl_alu_op = 4'b0010;
          3'b110:  ctrl_alu_op = 4'b0011;
          3'b100:  ctrl_alu_op = 4'b0100;
          3'b010:  ctrl_alu_op = 4'b0101;
          default: ctrl_alu_op = 4'b0000;
        endcase
      end

      7'b0000011: begin  // LW (Load Word)
        ctrl_reg_write = 1'b1;
        ctrl_alu_src   = 1'b1;
        ctrl_mem_read  = 1'b1;
        ctrl_wb_sel    = 2'b01;
        ctrl_alu_op    = 4'b0000; // Calculate address using ADD
      end

      7'b0100011: begin  // SW (Store Word)
        ctrl_reg_write = 1'b0;
        ctrl_alu_src   = 1'b1;
        ctrl_mem_write = 1'b1;
        ctrl_alu_op    = 4'b0000; // Calculate address using ADD
      end

      7'b1101111: begin  // JAL (Jump and Link)
        ctrl_reg_write = 1'b1;
        ctrl_wb_sel    = 2'b10;
      end

      7'b1100011: begin  // B-Type (Branches– BEQ, BNE, BLT, BGE)
                         // Branch comparisons are evaluated independently
        ctrl_reg_write = 1'b0;
        ctrl_alu_src   = 1'b0;
      end

      7'b0110111: begin  // LUI (Load Upper Immediate)
        ctrl_reg_write = 1'b1;
        ctrl_alu_src   = 1'b1;     // Use immediate
        ctrl_alu_op    = 4'b0000;  // ADD (x0 + imm)
      end

      default: ctrl_reg_write = 1'b0;
    endcase
  end


  // 1-cycle branch resolution logic
  wire is_branch = (opcode == 7'b1100011);
  wire is_jal = (opcode == 7'b1101111);

  wire eq = (rs1_data_fwd == rs2_data_fwd);
  wire neq = !eq;

  // Signed comparisons for BLT/BGE
  wire signed [31:0] s_rs1 = rs1_data_fwd;
  wire signed [31:0] s_rs2 = rs2_data_fwd;
  wire lt = (s_rs1 < s_rs2);
  wire ge = !lt;

  wire branch_condition_met = (funct3 == 3'b000) ? eq :  // BEQ
  (funct3 == 3'b001) ? neq :  // BNE
  (funct3 == 3'b100) ? lt :  // BLT
  (funct3 == 3'b101) ? ge :  // BGE
  1'b0;  // Default

  assign actual_branch_valid = is_branch || is_jal;
  assign actual_branch_taken = (is_branch && branch_condition_met) || is_jal;
  assign actual_target = if_id_pc + imm_val;
  assign actual_pc = if_id_pc;
  assign actual_mispredict    = actual_branch_valid && (if_id_pred_taken != actual_branch_taken) && !stall;
  // B-Type and JAL targets are PC-relative constants for RV32I
  // so correctness of direction and BTB tag guarantess correctness

  // Sequential Logic: ID/EX Pipeline Register Update
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      id_ex_pc       <= 0;
      id_ex_rs1_data <= 0;
      id_ex_rs2_data <= 0;
      id_ex_imm      <= 0;
      id_ex_rd_addr  <= 0;
      id_ex_rs1_addr <= 0;
      id_ex_rs2_addr <= 0;
      id_alu_op      <= 0;
      id_alu_src     <= 0;
      id_mem_read    <= 0;
      id_mem_write   <= 0;
      id_reg_write   <= 0;
      id_wb_sel      <= 0;

    end else if (flush) begin
      // Insert NOP (Bubble) for flushing or misprediction
      id_ex_pc       <= 0;
      id_ex_rs1_data <= 0;
      id_ex_rs2_data <= 0;
      id_ex_imm      <= 0;
      id_ex_rd_addr  <= 0;
      id_ex_rs1_addr <= 0;
      id_ex_rs2_addr <= 0;
      id_alu_op      <= 0;
      id_alu_src     <= 0;
      id_mem_read    <= 0;
      id_mem_write   <= 0;
      id_reg_write   <= 0;
      id_wb_sel      <= 0;

    end else if (!stall) begin
      // Normal pipeline advance
      id_ex_pc       <= if_id_pc;
      id_ex_rs1_data <= rs1_data_fwd;
      id_ex_rs2_data <= rs2_data_fwd;
      id_ex_imm      <= imm_val;
      id_ex_rd_addr  <= rd_addr;
      id_ex_rs1_addr <= rs1_addr;
      id_ex_rs2_addr <= rs2_addr;
      id_alu_op      <= ctrl_alu_op;
      id_alu_src     <= ctrl_alu_src;
      id_mem_read    <= ctrl_mem_read;
      id_mem_write   <= ctrl_mem_write;
      id_reg_write   <= ctrl_reg_write;
      id_wb_sel      <= ctrl_wb_sel;
    end
  end

endmodule
