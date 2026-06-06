/*
 * Writeback Stage with purely combinational data routing
 */

module writeback #(
    parameter PC_WIDTH = 32
) (
    // MEM/WB Pipeline Registers
    input wire [PC_WIDTH-1:0] mem_wb_pc,
    input wire [31:0] mem_wb_alu_result,
    input wire [31:0] mem_wb_read_data,
    input wire [4:0] mem_wb_rd_addr,

    // Inter-stage signals (from MEM) 
    input wire mem_reg_write,
    input wire [1:0] mem_wb_sel,

    // Inter-stage signals (from WB)
    output wire [31:0] wb_fwd_data,  // Data to write/forward
    output wire [ 4:0] wb_rd_addr,   // Register destination
    output wire        wb_reg_write  // Write enable
);

  // Combinational Logic: Writeback Data MUX
  reg [31:0] write_data;

  always @(*) begin
    case (mem_wb_sel)
      2'b00:   write_data = mem_alu_result;  // R-Type, I-Type (ALU)
      2'b01:   write_data = mem_read_data;  // LW (Memory Read)
      2'b10:   write_data = mem_pc + 4;  // JAL (Return Address)
      default: write_data = 32'h0;
    endcase
  end

  assign wb_fwd_data  = write_data;
  assign wb_rd_addr   = mem_rd_addr;
  assign wb_reg_write = mem_reg_write;

endmodule
