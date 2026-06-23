/*
 * Fetch Stage with Dynamic Branch Prediction
 */

module fetch #(
    parameter PC_WIDTH      = 32,  // Program Counter bit-length
    parameter BT_ADDR_WIDTH = 8    // 256 entry BHT/BTB 
) (
    // Control Signals
    input wire clk,
    input wire rst_n,

    // Pipeline Control (from Hazard Unit)
    input wire stall,  // Triggered for Data and Control Hazards
    input wire flush,  // Triggered on branch misprediction

    // Branch Resolution (from Decode Stage)
    input wire actual_branch_valid,
    input wire actual_branch_taken,
    input wire [PC_WIDTH-1:0] actual_target,
    input wire [PC_WIDTH-1:0] actual_pc,
    input wire actual_mispredict,

    // Instruction Memory Interface
    output wire [PC_WIDTH-1:0] imem_addr,
    input wire [31:0] imem_data,  // RISC-V ISA specifies 32-bit instructions

    // IF/ID Pipeline Registers
    output reg [PC_WIDTH-1:0] if_id_pc,
    output reg [31:0] if_id_inst,
    output reg if_id_pred_taken
);

  // Architectural constants
  localparam RV32I_NOA = 32'h0000_0000;  // No Action for resets
  localparam RV32I_NOP = 32'h00000013;  // Canonical NOP: addi x0, x0, 0
  localparam TAG_WIDTH = PC_WIDTH - BT_ADDR_WIDTH - 2;  // PC = [tag:index:alignment(00)]

  // PC states
  reg  [PC_WIDTH-1:0] pc_reg;
  wire [PC_WIDTH-1:0] next_pc;

  // Table arrays
  localparam BT_DEPTH = 1 << BT_ADDR_WIDTH;
  reg [          0:0] val_table[0:BT_DEPTH-1];  // Valid bits
  reg [          1:0] bht_table[0:BT_DEPTH-1];  // 2-bit saturating counters
  reg [ PC_WIDTH-1:0] btb_table[0:BT_DEPTH-1];  // Cached target addresses
  reg [TAG_WIDTH-1:0] tag_table[0:BT_DEPTH-1];  // Aliasing protection tags

  // 2-bit BHT states
  localparam SNT = 2'b00;
  localparam WNT = 2'b01;
  localparam WT = 2'b10;
  localparam ST = 2'b11;

  // Branch Prediction Logic
  wire [BT_ADDR_WIDTH-1:0] fetch_idx = pc_reg[BT_ADDR_WIDTH+1:2];
  wire [    TAG_WIDTH-1:0] fetch_tag = pc_reg[PC_WIDTH-1:BT_ADDR_WIDTH+2];

  wire [              0:0] current_val = val_table[fetch_idx];
  wire [              1:0] current_bht = bht_table[fetch_idx];
  wire [     PC_WIDTH-1:0] current_btb = btb_table[fetch_idx];
  wire [    TAG_WIDTH-1:0] current_tag = tag_table[fetch_idx];

  wire                     tag_match = (current_tag == fetch_tag);
  wire                     pred_taken = current_val && tag_match && current_bht[1];
  wire [     PC_WIDTH-1:0] pred_target = current_btb;

  // Priority Decoder for next PC and Instruction Fetching 
  assign imem_addr = pc_reg;
  assign next_pc   = actual_mispredict ? (actual_branch_taken ? actual_target : actual_pc + 4) : 
                     stall ? pc_reg : 
                     pred_taken ? pred_target : 
                     (pc_reg + 4);

  // Sequential Logic : PC Update and IF/ID Register
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      pc_reg           <= RV32I_NOA;
      if_id_pc         <= RV32I_NOA;
      if_id_inst       <= RV32I_NOP;
      if_id_pred_taken <= 1'b0;

    end else begin
      pc_reg <= next_pc;
      // Pipeline Register Update (if not flushed)
      if (flush) begin
        if_id_inst       <= RV32I_NOP;
        if_id_pred_taken <= 1'b0;

      end else if (!stall) begin
        // Hold state if stalling
        if_id_pc         <= pc_reg;
        if_id_inst       <= imem_data;
        if_id_pred_taken <= pred_taken;
      end
    end
  end

  // Sequential Logic : BHT/BTB/Tag Update (from Decode)
  wire    [BT_ADDR_WIDTH-1:0] update_idx = actual_pc[BT_ADDR_WIDTH+1:2];
  wire    [    TAG_WIDTH-1:0] update_tag = actual_pc[PC_WIDTH-1:BT_ADDR_WIDTH+2];
  integer                     i;

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      for (i = 0; i < BT_DEPTH; i = i + 1) begin
        bht_table[i] <= WNT;
        val_table[i] <= 1'b0;
        btb_table[i] <= RV32I_NOA;
        tag_table[i] <= {TAG_WIDTH{1'b0}};
      end

    end else if (actual_branch_valid) begin
      // Force override if tags don't match
      if (tag_table[update_idx] != update_tag) begin
        val_table[update_idx] <= 1'b1;
        btb_table[update_idx] <= actual_target;
        tag_table[update_idx] <= update_tag;
        bht_table[update_idx] <= actual_branch_taken ? WT : WNT;

      end else begin
        val_table[update_idx] <= 1'b1;
        btb_table[update_idx] <= actual_target;
        // Saturating Counter Machine
        case (bht_table[update_idx])
          SNT:     bht_table[update_idx] <= actual_branch_taken ? WNT : SNT;
          WNT:     bht_table[update_idx] <= actual_branch_taken ? WT : SNT;
          WT:      bht_table[update_idx] <= actual_branch_taken ? ST : WNT;
          ST:      bht_table[update_idx] <= actual_branch_taken ? ST : WT;
          default: bht_table[update_idx] <= WT;
        endcase
      end
    end
  end

endmodule
