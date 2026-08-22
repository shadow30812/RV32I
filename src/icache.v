/*
 * L1 Instruction Cache with 64-entry Direct-Mapped architecture
 */

module icache #(
    parameter PC_WIDTH        = 32,
    parameter CACHE_ADDR_BITS = 6    // 64 entries (2^6)
) (
    // Control Signals
    input wire clk,
    input wire rst_n,

    // Core Pipeline Interface (From Fetch Stage)
    input  wire        req,
    input  wire [31:0] addr,
    output wire [31:0] rdata,
    output wire        hit,

    // Interface to Physical Main Memory (Port A)
    output reg         mem_req,
    output wire [ 9:0] mem_addr,
    input  wire [31:0] mem_rdata,
    input  wire        mem_ready
);
  localparam CACHE_DEPTH = 1 << CACHE_ADDR_BITS;
  localparam TAG_BITS = PC_WIDTH - CACHE_ADDR_BITS - 2;

  reg                        valid_array                              [0:CACHE_DEPTH-1];

  // Block RAM Arrays for Cache Storage
  (* ram_style = "distributed" *)reg  [               31:0] data_array                               [0:CACHE_DEPTH-1];
  (* ram_style = "distributed" *)reg  [       TAG_BITS-1:0] tag_array                                [0:CACHE_DEPTH-1];

  // Address Breakdown
  wire [CACHE_ADDR_BITS-1:0] index = addr[CACHE_ADDR_BITS+1:2];
  wire [       TAG_BITS-1:0] tag = addr[31:CACHE_ADDR_BITS+2];


  // Tag & Hit Comparison
  wire                       valid_match = valid_array[index];
  wire                       tag_match = (tag_array[index] == tag);
  wire                       is_hit = req && valid_match && tag_match;

  // FSM States
  localparam STATE_IDLE  = 2'b00;
  localparam STATE_FETCH = 2'b01;
  localparam STATE_READY = 2'b10;

  reg [1:0] state;

  assign hit      = is_hit || (req && state == STATE_READY);
  assign rdata    = data_array[index];
  assign mem_addr = addr[11:2];

  integer i;
  always @(posedge clk) begin
    if (state == STATE_FETCH && mem_ready) begin
      data_array[index] <= mem_rdata;
      tag_array[index]  <= tag;
    end
  end

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state   <= STATE_IDLE;
      mem_req <= 1'b0;
      for (i = 0; i < CACHE_DEPTH; i = i + 1) valid_array[i] <= 1'b0;

    end else begin
      case (state)

        STATE_IDLE: begin
          if (req && !is_hit) begin
            // CACHE MISS: Fetch instruction from Main Memory
            state   <= STATE_FETCH;
            mem_req <= 1'b1;
          end else mem_req <= 1'b0;
        end

        STATE_FETCH: begin
          if (mem_ready) begin
            valid_array[index] <= 1'b1;
            mem_req            <= 1'b0;
            state              <= STATE_READY;
          end
        end

        STATE_READY: state <= STATE_IDLE;
        default: state <= STATE_IDLE;

      endcase
    end
  end

endmodule
