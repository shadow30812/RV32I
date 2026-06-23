/*
 * 32 x 32-bit Register File with Internal Bypassing for same-cycle Read & Write
 */

module regfile (
    // Control Signals
    input wire clk,
    input wire rst_n,

    // Read Port 1 (Combinational)
    input  wire [ 4:0] rs1_addr,
    output wire [31:0] rs1_data,

    // Read Port 2 (Combinational)
    input  wire [ 4:0] rs2_addr,
    output wire [31:0] rs2_data,

    // Write Port (Synchronous)
    input wire        reg_write,
    input wire [ 4:0] rd_addr,
    input wire [31:0] rd_data
);

  // Register Array
  reg [31:0] registers[0:31];
  integer i;

  localparam x0 = 5'b00000;
  localparam zer0 = 32'h0000_0000;

  // Read Logic
  // x0 gives a constant zer0
  assign rs1_data = (rs1_addr == x0) ? zer0 :
                    (reg_write && (rs1_addr == rd_addr)) ? rd_data :
                    (registers[rs1_addr]);

  assign rs2_data = (rs2_addr == x0) ? zer0 :
                    (reg_write && (rs2_addr == rd_addr)) ? rd_data :
                    (registers[rs2_addr]);

  // Write Logic
  // x0 cannot be modified
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) for (i = 0; i < 32; i = i + 1) registers[i] <= zer0;
    else if (reg_write && (rd_addr != x0)) registers[rd_addr] <= rd_data;
  end

endmodule
