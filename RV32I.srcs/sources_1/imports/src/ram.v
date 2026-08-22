/*
 * Dual-Port Block RAM
 * Physical Main Memory- Harvard Architecture
 * Port A: L1 I-Cache
 * Port B: L1 D-Cache
 */

module ram #(
    parameter ADDR_WIDTH = 10,  // 1024 words = 4 KB RAM (addr [11:2])
    parameter DATA_WIDTH = 32,
    parameter INIT_HEX = "/home/shadow30812/LWL/Projects/RV32I/imem.hex"
) (
    // Control Signal
    input wire clk,

    // Port A: Instruction Cache Interface
    input wire ena,
    input wire [ADDR_WIDTH-1:0] addra,
    output reg [DATA_WIDTH-1:0] douta,
    output reg readya,

    // Port B: Data Cache Interface
    input wire enb,
    input wire web,
    input wire [ADDR_WIDTH-1:0] addrb,
    input wire [DATA_WIDTH-1:0] dinb,
    output reg [DATA_WIDTH-1:0] doutb,
    output reg readyb
);

  // Block RAM init
  localparam RAM_DEPTH = 1 << ADDR_WIDTH;
  (* ram_style = "block" *) reg [DATA_WIDTH-1:0] iram[0:RAM_DEPTH-1];
  (* ram_style = "block" *) reg [DATA_WIDTH-1:0] dram[0:RAM_DEPTH-1];

  integer i;
  initial begin
    for (i = 0; i < RAM_DEPTH; i = i + 1) begin
      iram[i] = {DATA_WIDTH{1'b0}};
      dram[i] = {DATA_WIDTH{1'b0}};
    end
    $readmemh(INIT_HEX, iram);
  end

  // Port A: Sync Read
  always @(posedge clk) begin
    if (ena) begin
      douta  <= iram[addra];
      readya <= 1'b1;
    end else readya <= 1'b0;
  end

  // Port B: Sync Read/Write
  always @(posedge clk) begin
    if (enb) begin
      if (web) dram[addrb] <= dinb;
      doutb  <= dram[addrb];
      readyb <= 1'b1;
    end else readyb <= 1'b0;
  end


endmodule
