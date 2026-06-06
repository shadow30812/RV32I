/*
 * Memory Stage with MMIO Decoding and L1 Cache
 */

module memory #(
    parameter PC_WIDTH = 32,
    parameter MMIO_BASE_ADDR = 32'h8000_0000  // Top-half of RAM is reserved for 
                                              // Memory-Mapped I/O device protocols
) (
    // Control Signals
    input wire clk,
    input wire rst_n,

    // EX/MEM Pipeline Registers
    input wire [PC_WIDTH-1:0] ex_mem_pc,
    input wire [31:0] ex_mem_alu_result,
    input wire [31:0] ex_mem_rs2_data,  // Data to be written (for SW)
    input wire [4:0] ex_mem_rd_addr,

    // Inter-stage signals (from EX)
    input wire ex_mem_read,
    input wire ex_mem_write,
    input wire ex_reg_write,
    input wire [1:0] ex_wb_sel,

    // Interfaces to L1 Data Cache
    output wire cache_req,
    output wire cache_we,
    output wire [31:0] cache_addr,
    output wire [31:0] cache_wdata,
    input wire [31:0] cache_rdata,
    input wire cache_hit,  // High when Cache data is ready

    // Interfaces to MMIO Controller
    output wire mmio_req,
    output wire mmio_we,
    output wire [31:0] mmio_addr,
    output wire [31:0] mmio_wdata,
    input wire [31:0] mmio_rdata,
    input wire mmio_ready,  // High when MMIO op completes

    // MEM/WB Pipeline Registers
    output reg [PC_WIDTH-1:0] mem_wb_pc,
    output reg [31:0] mem_wb_alu_result,
    output reg [31:0] mem_wb_read_data,
    output reg [4:0] mem_wb_rd_addr,

    // Inter-stage signals (from MEM)
    output reg mem_reg_write,
    output reg [1:0] mem_wb_sel,
    output wire stall_mem
);

  // Combinational Logic: Address Decoding and Routing
  wire is_mem_access = ex_mem_read || ex_mem_write;
  wire is_mmio = is_mem_access && ex_mem_alu_result[31];  // Only MSB differs for MMIO
  wire is_cache = is_mem_access && !is_mmio;

  // Route to L1 Cache
  assign cache_req   = is_cache;
  assign cache_wr_en = is_cache ? ex_mem_write : 1'b0;  // Write-enable for Cache
  assign cache_addr  = ex_mem_alu_result;
  assign cache_wdata = ex_mem_rs2_data;

  // Route to MMIO Peripheral Controller
  assign mmio_req    = is_mmio;
  assign mmio_wr_en  = is_mmio ? ex_mem_write : 1'b0;   // Write-enable for MMIO
  assign mmio_addr   = ex_mem_alu_result;
  assign mmio_wdata  = ex_mem_rs2_data;

  wire [31:0] read_data_mux = is_mmio ? mmio_rdata : cache_rdata;  // MUX for MMIO/Cache

  // Stall Generation for Cache / MMIO Miss
  assign stall_mem = (is_cache && !cache_hit) || (is_mmio && !mmio_ready);

  // Sequential Logic: MEM/WB Pipeline Registers
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      mem_wb_pc         <= 32'h0;
      mem_wb_alu_result <= 32'h0;
      mem_wb_read_data  <= 32'h0;
      mem_wb_rd_addr    <= 5'h0;
      mem_reg_write     <= 1'b0;
      mem_wb_sel        <= 2'b00;

    end else if (!stall_mem) begin
      mem_wb_pc         <= ex_pc;
      mem_wb_alu_result <= ex_alu_result;
      mem_wb_read_data  <= read_data_mux;
      mem_wb_rd_addr    <= ex_rd_addr;
      mem_reg_write     <= ex_reg_write;
      mem_wb_sel        <= ex_wb_sel;
    end
  end

endmodule
