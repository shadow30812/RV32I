`timescale 1ns / 1ps

module tb_risc;

  reg clk;
  reg rst_n;

  wire [31:0] imem_addr;
  reg [31:0] imem_data;

  reg spi_miso;
  wire spi_mosi;
  wire spi_sclk;
  wire spi_cs_n;

  system u_system (
      .clk      (clk),
      .rst_n    (rst_n),
      .imem_addr(imem_addr),
      .imem_data(imem_data),
      .spi_miso (spi_miso),
      .spi_mosi (spi_mosi),
      .spi_sclk (spi_sclk),
      .spi_cs_n (spi_cs_n)
  );

  reg [31:0] imem[0:255];

  initial begin
    $readmemh("RV32I/imem.hex", imem);
  end

  always @(*) begin
    imem_data = imem[imem_addr>>2];
  end

  initial begin
    clk = 0;
    forever #5 clk = ~clk;
  end

  initial begin
    rst_n    = 0;
    spi_miso = 0;
    #20 rst_n = 1;
  end

  initial begin
    $dumpfile("RV32I/dump_risc.vcd");
    $dumpvars(0, tb_risc);

    #20000;
    $display("[FATAL] Simulation Timeout. Check for infinite loops or stalled FSMs.");
    $finish;
  end

  reg     [31:0] expected[0:31];
  reg            checked [0:31];
  integer        errors;
  integer        k;

  initial begin
    for (k = 0; k < 32; k = k + 1) begin
      expected[k] = 32'h0;
      checked[k]  = 1'b0;
    end
    expected[1] = 32'd5;
    expected[2] = 32'd10;
    expected[3] = 32'd15;
    expected[4] = 32'd5;
    expected[5] = 32'd0;
    expected[6] = 32'd15;
    expected[7] = 32'd15;
    expected[8] = 32'd1;
    expected[9] = 32'd15;
    expected[10] = 32'h123;
    expected[11] = 32'h122;
    expected[12] = 32'd1;
    expected[13] = 32'h40;
    expected[14] = 32'h123;
    expected[15] = 32'h123;
    expected[16] = 32'h124;
    expected[17] = 32'h123;
    expected[18] = 32'd7;
    expected[19] = 32'd0;
    expected[20] = 32'd1;
    expected[21] = 32'd2;
    expected[22] = 32'd0;
    expected[23] = 32'd9;
    expected[24] = 32'd4;
    expected[25] = 32'd0;
    expected[26] = 32'd5;
    expected[27] = 32'd6;
    expected[28] = 32'd0;
    expected[29] = 32'd152;
    expected[30] = 32'd9;
    expected[31] = 32'hABCDE01E;

    errors = 0;
  end

  wire        wb_we = u_system.wb_reg_write;
  wire [ 4:0] wb_addr = u_system.wb_rd_addr;
  wire [31:0] wb_data = u_system.wb_fwd_data;

  always @(posedge clk) begin
    if (rst_n && wb_we && wb_addr != 5'd0) begin
      $display("[WB] t=%0t  x%0d <= 0x%h", $time, wb_addr, wb_data);
    end
  end

  integer cycle_count;
  integer instr_count;
  integer branch_total;
  integer branch_mispredicts;

  wire branch_resolved = u_system.u_decode.actual_branch_valid;
  wire branch_mispredict = u_system.u_decode.actual_mispredict;
  wire pipeline_stalled = u_system.stall_id;
  wire pipeline_flushed = u_system.u_decode.flush;

  reg [31:0] wb_pc_prev;
  wire [31:0] wb_pc_cur = u_system.mem_wb_pc;

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      cycle_count        <= 0;
      instr_count        <= 0;
      branch_total       <= 0;
      branch_mispredicts <= 0;
      wb_pc_prev         <= 32'hFFFF_FFFF;
    end else begin
      cycle_count <= cycle_count + 1;
      wb_pc_prev  <= wb_pc_cur;

      if (branch_resolved) begin
        branch_total = branch_total + 1;
        if (branch_mispredict) branch_mispredicts = branch_mispredicts + 1;
      end

      if (u_system.mem_reg_write && (wb_pc_cur !== wb_pc_prev)) instr_count <= instr_count + 1;
      else if (u_system.ex_mem_write && !u_system.stall_mem) instr_count <= instr_count + 1;
    end
  end

  initial begin
    $display("=====================================================");
    $display("  Starting RV32I Pipeline Self-Checking Verification");
    $display("=====================================================");

    @(posedge rst_n);
    wait_for_completion;

    repeat (10) @(posedge clk);

    $display("-----------------------------------------------------");
    $display("  Architectural State Check (Final Register Values)");
    $display("-----------------------------------------------------");
    for (k = 1; k < 32; k = k + 1) begin
      check_register(k);
    end

    $display("-----------------------------------------------------");
    $display("  Performance Summary");
    $display("-----------------------------------------------------");
    $display("  Total Cycles            : %0d", cycle_count);
    $display("  Instructions Retired    : %0d", instr_count);
    if (cycle_count > 0)
      $display(
          "  IPC                     : %0d.%0d (x1000)",
          (instr_count * 1000) / cycle_count,
          ((instr_count * 1000) / cycle_count)
      );
    $display("  Branches Resolved       : %0d", branch_total);
    $display("  Branch Mispredicts      : %0d", branch_mispredicts);
    if (branch_total > 0)
      $display(
          "  Branch Predictor Accuracy: %0d%%",
          ((branch_total - branch_mispredicts) * 100) / branch_total
      );

    $display("-----------------------------------------------------");
    if (errors == 0) begin
      $display("  [SUCCESS] ALL CHECKS PASSED! 0 ERRORS.");
    end else begin
      $display("  [FAILURE] TEST SUITE FAILED WITH %0d ERRORS.", errors);
    end
    $display("=====================================================");

    $finish;
  end

  task check_register;
    input integer reg_idx;
    reg [31:0] actual;
    begin
      actual = u_system.u_regfile.registers[reg_idx];
      if (actual !== expected[reg_idx]) begin
        $display("[FAIL] x%0d : Expected 0x%h, Got 0x%h", reg_idx, expected[reg_idx], actual);
        errors = errors + 1;
      end else begin
        $display("[PASS] x%0d = 0x%h", reg_idx, actual);
      end
    end
  endtask

  task wait_for_completion;
    integer settle_cycles;
    begin
      settle_cycles = 0;
      while (settle_cycles < 5) begin
        @(posedge clk);
        if (imem_addr == 32'd192) settle_cycles = settle_cycles + 1;
        else settle_cycles = 0;
      end
    end
  endtask

endmodule
