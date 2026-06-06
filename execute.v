/*
 * Execute Stage with Integrated Forwarding Network MUXes
 */

module execute #(
    parameter PC_WIDTH = 32
) (
    // Control Signals
    input wire clk,
    input wire rst_n,

    // Pipeline Control (from Hazard Unit)
    input wire stall,
    input wire flush,

    // ID/EX Pipeline Registers
    input wire [PC_WIDTH-1:0] id_ex_pc,
    input wire [31:0] id_ex_rs1_data,
    input wire [31:0] id_ex_rs2_data,
    input wire [31:0] id_ex_imm,
    input wire [4:0] id_ex_rd_addr,

    // Inter-stage signals (from ID)
    input wire [3:0] id_alu_op,
    input wire id_alu_src,
    input wire id_mem_read,
    input wire id_mem_write,
    input wire id_reg_write,
    input wire [1:0] id_wb_sel,

    // Forwarding Data (from MEM and WB stages)
    input wire [31:0] mem_fwd_data,
    input wire [31:0] wb_fwd_data,

    // Forwarding Control (from Hazard Unit)
    // 00 = Normal (from RegFile), 01 = Forward from WB, 10 = Forward from MEM
    input wire [1:0] fwd_a,
    input wire [1:0] fwd_b,

    // Outputs to EX/MEM Pipeline Register
    output reg [PC_WIDTH-1:0] ex_mem_pc,
    output reg [31:0] ex_mem_alu_result,
    output reg [31:0] ex_mem_rs2_data,  // for SW downstream
    output reg [4:0] ex_mem_rd_addr,

    // Inter-stage signals (from EX)
    output reg ex_mem_read,
    output reg ex_mem_write,
    output reg ex_reg_write,
    output reg [1:0] ex_wb_sel
);

  // Combinational Logic: Forwarding Multiplexers
  reg [31:0] fwd_rs1;
  reg [31:0] fwd_rs2;

  always @(*) begin
    case (fwd_a)
      2'b10:   fwd_rs1 = mem_fwd_data;  // Youngest older instruction
      2'b01:   fwd_rs1 = wb_fwd_data;  // Oldest older instruction
      default: fwd_rs1 = id_ex_rs1_data;
    endcase

    case (fwd_b)
      2'b10:   fwd_rs2 = mem_fwd_data;
      2'b01:   fwd_rs2 = wb_fwd_data;
      default: fwd_rs2 = id_ex_rs2_data;
    endcase
  end

  // ALU
  wire [31:0] alu_in1 = fwd_rs1;
  wire [31:0] alu_in2 = id_alu_src ? id_imm : forwarded_rs2;
  reg  [31:0] alu_out;

  localparam RV32I_NOA = 32'h0;

  wire signed [31:0] s_alu_in1 = alu_in1;
  wire signed [31:0] s_alu_in2 = alu_in2;

  always @(*) begin
    case (id_alu_op)
      4'b0000: alu_out = alu_in1 + alu_in2;
      4'b0001: alu_out = alu_in1 - alu_in2;
      4'b0010: alu_out = alu_in1 & alu_in2;
      4'b0011: alu_out = alu_in1 | alu_in2;
      4'b0100: alu_out = alu_in1 ^ alu_in2;
      4'b0101: alu_out = (s_alu_in1 < s_alu_in2) ? 1 : 0;
      default: alu_out = RV32I_NOA;
    endcase
  end

  // Sequential Logic: EX/MEM Pipeline Register
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      ex_mem_pc         <= RV32I_NOA;
      ex_mem_alu_result <= RV32I_NOA;
      ex_mem_rs2_data   <= RV32I_NOA;
      ex_mem_rd_addr    <= 5'h0;
      ex_mem_read       <= 1'b0;
      ex_mem_write      <= 1'b0;
      ex_reg_write      <= 1'b0;
      ex_wb_sel         <= 2'b00;

    end else if (flush) begin
      ex_mem_pc         <= RV32I_NOA;
      ex_mem_alu_result <= RV32I_NOA;
      ex_mem_rs2_data   <= RV32I_NOA;
      ex_mem_rd_addr    <= 5'h0;
      ex_mem_read       <= 1'b0;
      ex_mem_write      <= 1'b0;
      ex_reg_write      <= 1'b0;
      ex_wb_sel         <= 2'b00;

    end else if (!stall) begin
      ex_mem_pc         <= id_ex_pc;
      ex_mem_alu_result <= alu_out;
      ex_mem_rs2_data   <= fwd_rs2;
      ex_mem_rd_addr    <= id_ex_rd_addr;
      ex_mem_read       <= id_mem_read;
      ex_mem_write      <= id_mem_write;
      ex_reg_write      <= id_reg_write;
      ex_wb_sel         <= id_wb_sel;
    end
  end

endmodule
