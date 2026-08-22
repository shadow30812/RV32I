/*
 * L1 Data Cache with 64-entry Direct-Mapped architecture
 */

module dcache #(
    parameter PC_WIDTH        = 32,
    parameter CACHE_ADDR_BITS = 6    // 64 entries (2^6)
) (
    // Control Signals
    input wire clk,
    input wire rst_n,

    // Core Pipeline Interface (From MEM)
    input wire req,
    input wire wr_en,
    input wire  [31:0] addr,
    input wire  [31:0] wdata,
    output wire [31:0] rdata,
    output wire hit,     // High when data is ready

    // Port B Interface
    output reg mem_req,
    output reg mem_wr_en,
    output wire [9:0] mem_addr,
    output wire [31:0] mem_wdata,
    input wire [31:0] mem_rdata,
    input wire mem_ready
);

  // Architectural Constants
  localparam CACHE_DEPTH = 1 << CACHE_ADDR_BITS;
  localparam TAG_BITS = PC_WIDTH - CACHE_ADDR_BITS - 2;  // -2 for alignment bits (00)

  // Physical Cache Arrays
  (* ram_style = "distributed" *) reg [31:0] data_array[0:CACHE_DEPTH-1];
  (* ram_style = "distributed" *) reg [TAG_BITS-1:0] tag_array[0:CACHE_DEPTH-1];
  reg valid_array[0:CACHE_DEPTH-1];

  // Address Decoding
  wire [CACHE_ADDR_BITS-1:0] index = addr[CACHE_ADDR_BITS+1:2];
  wire [TAG_BITS-1:0] tag = addr[31:CACHE_ADDR_BITS+2];

  // Combinational Logic: Read & Hit/Miss
  wire valid_match = valid_array[index];
  wire tag_match = (tag_array[index] == tag);
  wire is_hit = req && valid_match && tag_match;

  // FSM States for Cache
  localparam STATE_IDLE  = 2'b00;
  localparam STATE_FETCH = 2'b01;
  localparam STATE_READY = 2'b10;

  reg [1:0] state;

  // Memory wrapper sees a hit either instantly (is_hit), or
  // when the Main Memory fetch is complete (STATE_READY).
  assign hit = is_hit || (req && state == STATE_READY);
  assign rdata = data_array[index];
  assign mem_addr = addr[11:2];
  assign mem_wdata = wdata;

  // Sequential Logic: Cache Update
  integer i;
  always @(posedge clk) begin
    if (state == STATE_IDLE && req && wr_en && is_hit) begin
      // CACHE HIT: Update self & Write-Through
      data_array[index] <= wdata;

    end else if (state == STATE_FETCH && mem_ready) begin
      tag_array[index]  <= tag;
      data_array[index] <= (wr_en) ? wdata : mem_rdata;
    end
  end

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state    <= STATE_IDLE;
      mem_req   <= 1'b0;
      mem_wr_en <= 1'b0;
      for (i = 0; i < CACHE_DEPTH; i = i + 1) valid_array[i] <= 1'b0;

    end else begin
      case (state)

        STATE_IDLE: begin
          if (req && !is_hit) begin
            // CACHE MISS: Read or Write from/to Main Memory
            state     <= STATE_FETCH;
            mem_req   <= 1'b1;
            mem_wr_en <= wr_en;

          end else if (req && wr_en && is_hit) begin
            mem_req   <= 1'b1;
            mem_wr_en <= 1'b1;

          end else begin
            // De-assert En next cycle
            mem_req   <= 1'b0;
            mem_wr_en <= 1'b0;
          end
        end

        STATE_FETCH: begin
          if (mem_ready) begin
            // Allocate cache line from physical memory
            valid_array[index] <= 1'b1;
            mem_req            <= 1'b0;
            mem_wr_en          <= 1'b0;
            state              <= STATE_READY;
          end
        end

        STATE_READY: begin
          // Hold the hit signal high for 1 clock cycle so the stalled
          // pipeline registers can latch the data, then return to IDLE
          state <= STATE_IDLE;
        end

        default: state <= STATE_IDLE;
      endcase
    end
  end

endmodule
