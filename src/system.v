/*
 * RV32I System Top-Level integrating:
 * 5-Stage Core, Hazard Unit, L1 Data Cache, and external SPI Master
 */

module system (
    // Control Signals
    input wire clk,
    input wire rst_n,

    // Instruction Menory
    output wire [31:0] imem_addr,
    input  wire [31:0] imem_data,

    // External SPI Bus
    input  wire spi_miso,
    output wire spi_mosi,
    output wire spi_sclk,
    output wire spi_cs_n
);

  // Pipeline Interconnect Wires
  // IF/ID Pipeline Wires (Fetch -> Decode)
  wire [31:0] if_id_pc, if_id_inst;
  wire if_id_pred_taken;

  // Branch Resolution (Decode -> Fetch)
  wire [31:0] actual_target, actual_pc;
  wire actual_branch_valid, actual_branch_taken, actual_mispredict;

  // Decode -> RegFile (Combinational)
  wire [31:0] rs1_data, rs2_data;
  wire [4:0] rs1_addr, rs2_addr;

  // ID/EX Pipeline Wires (Decode -> Execute)
  wire [31:0] id_ex_pc, id_ex_rs1_data, id_ex_rs2_data, id_ex_imm;
  wire [4:0] id_ex_rd_addr, id_ex_rs1_addr, id_ex_rs2_addr;
  wire [3:0] id_alu_op;
  wire [1:0] id_wb_sel;
  wire id_alu_src, id_mem_read, id_mem_write, id_reg_write;

  // EX/MEM Pipeline Wires (Execute -> Memory)
  wire [31:0] ex_mem_pc, ex_mem_alu_result, ex_mem_rs2_data;
  wire [4:0] ex_mem_rd_addr;
  wire [1:0] ex_wb_sel;
  wire ex_mem_read, ex_mem_write, ex_reg_write;

  // MEM/WB Pipeline Wires (Memory -> Writeback)
  wire [31:0] mem_wb_pc, mem_wb_alu_result, mem_wb_read_data;
  wire [ 4:0] mem_wb_rd_addr;
  wire [ 1:0] mem_wb_sel;
  wire        mem_reg_write;

  // Writeback Wires (Writeback -> RegFile & Forwarding)
  wire [31:0] wb_fwd_data;
  wire [ 4:0] wb_rd_addr;
  wire        wb_reg_write;

  // Hazard Unit Controls & Forwarding Interconnects
  wire [31:0] rs1_data_fwd, rs2_data_fwd;
  wire [1:0] fwd_a, fwd_b;
  wire stall_if, stall_id, stall_ex, stall_mem, flush_ex;

  // Cache & MMIO Interfaces
  wire [31:0] cache_addr, cache_wdata, cache_rdata;
  wire cache_req, cache_wr_en, cache_hit;
  wire [31:0] mmio_addr, mmio_wdata, mmio_rdata;
  wire mmio_req, mmio_wr_en, mmio_ready;


  // Pipeline Stage Instantiations
  // 1. Fetch Stage
  fetch u_fetch (
      .clk                (clk),
      .rst_n              (rst_n),
      .stall              (stall_if),
      .flush              (actual_mispredict),
      .actual_branch_valid(actual_branch_valid),
      .actual_branch_taken(actual_branch_taken),
      .actual_target      (actual_target),
      .actual_pc          (actual_pc),
      .actual_mispredict  (actual_mispredict),
      .imem_addr          (imem_addr),
      .imem_data          (imem_data),
      .if_id_pc           (if_id_pc),
      .if_id_inst         (if_id_inst),
      .if_id_pred_taken   (if_id_pred_taken)
  );

  // 2. Decode Stage
  decode u_decode (
      .clk                (clk),
      .rst_n              (rst_n),
      .stall              (stall_id),
      .flush              (flush_ex),
      .if_id_pc           (if_id_pc),
      .if_id_inst         (if_id_inst),
      .if_id_pred_taken   (if_id_pred_taken),
      .rs1_data_fwd       (rs1_data_fwd),
      .rs2_data_fwd       (rs2_data_fwd),
      .rs1_addr           (rs1_addr),
      .rs2_addr           (rs2_addr),
      .actual_branch_valid(actual_branch_valid),
      .actual_branch_taken(actual_branch_taken),
      .actual_target      (actual_target),
      .actual_pc          (actual_pc),
      .actual_mispredict  (actual_mispredict),
      .id_ex_pc           (id_ex_pc),
      .id_ex_rs1_data     (id_ex_rs1_data),
      .id_ex_rs2_data     (id_ex_rs2_data),
      .id_ex_imm          (id_ex_imm),
      .id_ex_rd_addr      (id_ex_rd_addr),
      .id_ex_rs1_addr     (id_ex_rs1_addr),
      .id_ex_rs2_addr     (id_ex_rs2_addr),
      .id_alu_op          (id_alu_op),
      .id_alu_src         (id_alu_src),
      .id_mem_read        (id_mem_read),
      .id_mem_write       (id_mem_write),
      .id_reg_write       (id_reg_write),
      .id_wb_sel          (id_wb_sel)
  );

  // 3. Register File
  regfile u_regfile (
      .clk      (clk),
      .rst_n    (rst_n),
      .rs1_addr (rs1_addr),
      .rs1_data (rs1_data),
      .rs2_addr (rs2_addr),
      .rs2_data (rs2_data),
      .reg_write(wb_reg_write),
      .rd_addr  (wb_rd_addr),
      .rd_data  (wb_fwd_data)
  );

  // 4. Execute Stage
  execute u_execute (
      .clk              (clk),
      .rst_n            (rst_n),
      .stall            (stall_ex),
      .flush            (1'b0),
      .id_ex_pc         (id_ex_pc),
      .id_ex_rs1_data   (id_ex_rs1_data),
      .id_ex_rs2_data   (id_ex_rs2_data),
      .id_ex_imm        (id_ex_imm),
      .id_ex_rd_addr    (id_ex_rd_addr),
      .id_alu_op        (id_alu_op),
      .id_alu_src       (id_alu_src),
      .id_mem_read      (id_mem_read),
      .id_mem_write     (id_mem_write),
      .id_reg_write     (id_reg_write),
      .id_wb_sel        (id_wb_sel),
      .mem_fwd_data     (ex_mem_alu_result),  // Forwarded from EX/MEM boundary
      .wb_fwd_data      (wb_fwd_data),        // Forwarded from Writeback
      .fwd_a            (fwd_a),
      .fwd_b            (fwd_b),
      .ex_mem_pc        (ex_mem_pc),
      .ex_mem_alu_result(ex_mem_alu_result),
      .ex_mem_rs2_data  (ex_mem_rs2_data),
      .ex_mem_rd_addr   (ex_mem_rd_addr),
      .ex_mem_read      (ex_mem_read),
      .ex_mem_write     (ex_mem_write),
      .ex_reg_write     (ex_reg_write),
      .ex_wb_sel        (ex_wb_sel)
  );

  // 5. Memory Stage
  memory u_memory (
      .clk              (clk),
      .rst_n            (rst_n),
      .ex_mem_pc        (ex_mem_pc),
      .ex_mem_alu_result(ex_mem_alu_result),
      .ex_mem_rs2_data  (ex_mem_rs2_data),
      .ex_mem_rd_addr   (ex_mem_rd_addr),
      .ex_mem_read      (ex_mem_read),
      .ex_mem_write     (ex_mem_write),
      .ex_reg_write     (ex_reg_write),
      .ex_wb_sel        (ex_wb_sel),
      .cache_req        (cache_req),
      .cache_wr_en      (cache_wr_en),
      .cache_addr       (cache_addr),
      .cache_wdata      (cache_wdata),
      .cache_rdata      (cache_rdata),
      .cache_hit        (cache_hit),
      .mmio_req         (mmio_req),
      .mmio_wr_en       (mmio_wr_en),
      .mmio_addr        (mmio_addr),
      .mmio_wdata       (mmio_wdata),
      .mmio_rdata       (mmio_rdata),
      .mmio_ready       (mmio_ready),
      .stall_mem        (stall_mem),
      .mem_wb_pc        (mem_wb_pc),
      .mem_wb_alu_result(mem_wb_alu_result),
      .mem_wb_read_data (mem_wb_read_data),
      .mem_wb_rd_addr   (mem_wb_rd_addr),
      .mem_reg_write    (mem_reg_write),
      .mem_wb_sel       (mem_wb_sel)
  );

  // 6. Writeback Stage
  writeback u_writeback (
      .mem_wb_pc        (mem_wb_pc),
      .mem_wb_alu_result(mem_wb_alu_result),
      .mem_wb_read_data (mem_wb_read_data),
      .mem_wb_rd_addr   (mem_wb_rd_addr),
      .mem_reg_write    (mem_reg_write),
      .mem_wb_sel       (mem_wb_sel),
      .wb_fwd_data      (wb_fwd_data),
      .wb_rd_addr       (wb_rd_addr),
      .wb_reg_write     (wb_reg_write)
  );

  // 7. Hazard Unit
  hazard u_hazard (
      // Hazard itself
      .stall_mem(stall_mem),

      // ID Stage Inputs
      .id_ex_rs1_addr (rs1_addr),
      .id_ex_rs2_addr (rs2_addr),
      .id_is_branch   (actual_branch_valid),
      .id_rs1_data_reg(rs1_data),
      .id_rs2_data_reg(rs2_data),

      // EX Stage Inputs
      .ex_mem_rs1_addr(id_ex_rs1_addr),
      .ex_mem_rs2_addr(id_ex_rs2_addr),
      .ex_mem_rd_addr (id_ex_rd_addr),
      .ex_mem_read    (id_mem_read),
      .ex_reg_write   (id_reg_write),
      .ex_alu_result  (ex_mem_alu_result),

      // MEM Stage Inputs
      .mem_wb_rd_addr(ex_mem_rd_addr),
      .mem_reg_write (ex_reg_write),
      .mem_mem_read  (ex_mem_read),
      .mem_fwd_data  (ex_mem_alu_result),

      // WB Stage Inputs
      .wb_rd_addr  (mem_wb_rd_addr),
      .wb_reg_write(mem_reg_write),
      .wb_fwd_data (wb_fwd_data),

      // Outputs
      .fwd_a       (fwd_a),
      .fwd_b       (fwd_b),
      .rs1_data_fwd(rs1_data_fwd),
      .rs2_data_fwd(rs2_data_fwd),
      .stall_if    (stall_if),
      .stall_id    (stall_id),
      .stall_ex    (stall_ex),
      .flush_ex    (flush_ex)
  );

  // 8. L1 Data Cache
  cache u_cache (
      .clk  (clk),
      .rst_n(rst_n),
      .req  (cache_req),
      .wr_en(cache_wr_en),
      .addr (cache_addr),
      .wdata(cache_wdata),
      .rdata(cache_rdata),
      .hit  (cache_hit)
  );

  // 9. MMIO to SPI Master Bridge
  // Memory Map:
  // 0x8000_0000 : SPI TX Data (Write) / RX Data (Read)
  // 0x8000_0004 : SPI Status/Control (Read/Write CPOL & CPHA)

  wire spi_full, spi_empty, spi_busy, spi_rx_valid;
  wire [7:0] spi_rx_data;

  // Control Registers
  reg spi_cpol, spi_cpha;

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      spi_cpol <= 1'b0;
      spi_cpha <= 1'b0;

    end else if (mmio_req && mmio_wr_en && mmio_addr == 32'h8000_0004) begin
      // Write to bit 0 for CPHA, bit 1 for CPOL
      spi_cpha <= mmio_wdata[0];
      spi_cpol <= mmio_wdata[1];
    end
  end

  // Map CPU Write to SPI TX FIFO
  wire spi_wr_en = (mmio_req && mmio_wr_en && mmio_addr == 32'h8000_0000);

  // Map CPU Read from SPI Registers
  assign mmio_rdata = (mmio_addr == 32'h8000_0000) ? {24'h0, spi_rx_data} :
        ((mmio_addr == 32'h8000_0004) ? {
        26'h0, spi_rx_valid, spi_busy, spi_empty, spi_full, spi_cpol, spi_cpha
        } : 32'h0);

  assign mmio_ready = 1'b1;

  top #(
      .DATA_WIDTH(8),
      .ADDR_WIDTH(3),
      .CLK_DIV   (4)
  ) spi_ctrl (
      .clk     (clk),
      .rst_n   (rst_n),
      .wr_en   (spi_wr_en),
      .wr_data (mmio_wdata[7:0]),
      .full    (spi_full),
      .empty   (spi_empty),
      .cpol    (spi_cpol),
      .cpha    (spi_cpha),
      .miso    (spi_miso),
      .sclk    (spi_sclk),
      .mosi    (spi_mosi),
      .cs_n    (spi_cs_n),
      .rx_data (spi_rx_data),
      .rx_valid(spi_rx_valid),
      .busy    (spi_busy)
  );

endmodule
