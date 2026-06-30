/*
 * L1 Data Cache with 64-entry Direct-Mapped architecture
 */

module cache #(
    parameter PC_WIDTH        = 32,
    parameter CACHE_ADDR_BITS = 6,   // 64 entries (2^6)
    parameter MEM_LATENCY     = 1    // Simulated clock cycles delay
                                     // to fetch data from Main Memory
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
    output wire hit     // High when data is ready
);

  // Architectural Constants
  localparam CACHE_DEPTH = 1 << CACHE_ADDR_BITS;
  localparam TAG_BITS = PC_WIDTH - CACHE_ADDR_BITS - 2;  // -2 for alignment bits (00)
  localparam zer0 = 32'h0;

  // Physical Cache Arrays
  reg [31:0] data_array[0:CACHE_DEPTH-1];
  reg [TAG_BITS-1:0] tag_array[0:CACHE_DEPTH-1];
  reg valid_array[0:CACHE_DEPTH-1];

  // Address Decoding
  wire [CACHE_ADDR_BITS-1:0] index = addr[CACHE_ADDR_BITS+1:2];
  wire [TAG_BITS-1:0] tag = addr[31:CACHE_ADDR_BITS+2];

  // Combinational Logic: Read & Hit/Miss
  wire valid_match = valid_array[index];
  wire tag_match = (tag_array[index] == tag);
  wire is_hit = req && valid_match && tag_match;

  // FSM States for Cache
  localparam STATE_IDLE = 2'b00;
  localparam STATE_FETCH = 2'b01;
  localparam STATE_READY = 2'b10;

  reg [1:0] state;

  // Memory wrapper sees a hit either instantly (is_hit), or when
  // the simulated Main Memory fetch is complete (STATE_READY).
  assign hit   = is_hit || (req && state == STATE_READY);
  assign rdata = data_array[index];

  // Sequential Logic: Cache Update & Main Memory Simulator
  reg [7:0] wait_cnt;
  integer i;
  always @(posedge clk or negedge rst_n) begin

    if (!rst_n) begin
      state    <= STATE_IDLE;
      wait_cnt <= 0;

      for (i = 0; i < CACHE_DEPTH; i = i + 1) begin
        valid_array[i] <= 1'b0;
        tag_array[i]   <= {TAG_BITS{1'b0}};
        data_array[i]  <= zer0;
      end

    end else begin
      case (state)

        STATE_IDLE: begin
          if (req && !is_hit) begin
            // CACHE MISS
            state    <= STATE_FETCH;
            wait_cnt <= MEM_LATENCY;

          end else if (req && wr_en && is_hit)
            // CACHE HIT
            data_array[index] <= wdata;
        end

        STATE_FETCH: begin
          if (wait_cnt > 1) begin
            wait_cnt <= wait_cnt - 1;  // Pipeline stalled
          end else begin

            // Allocate data from main memory
            valid_array[index] <= 1'b1;
            tag_array[index]   <= tag;

            // Simulate loading the cache line
            if (wr_en) data_array[index] <= wdata;
            else data_array[index] <= ~addr;
            state <= STATE_READY;
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
