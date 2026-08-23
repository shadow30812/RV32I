`timescale 1ns / 1ps

module tb_risc;

  reg  clk;
  reg  rst_n;

  reg  spi_miso;
  wire spi_mosi;
  wire spi_sclk;
  wire spi_cs_n;

  integer log_file;

  system u_system (
      .clk     (clk),
      .rst_n   (rst_n),
      .spi_miso(spi_miso),
      .spi_mosi(spi_mosi),
      .spi_sclk(spi_sclk),
      .spi_cs_n(spi_cs_n)
  );

  initial begin
    log_file = $fopen("results.txt", "w");
    if (!log_file) begin
      $display("[ERROR] Could not open results.txt for writing.");
    end
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

    #50000;
    $display("[FATAL] Simulation Timeout. Check for infinite loops or stalled FSMs.");
    if (log_file) begin
      $fdisplay(log_file, "[FATAL] Simulation Timeout. Check for infinite loops or stalled FSMs.");
      $fclose(log_file);
    end
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
    expected[1] = 32'h0000000F;  // 15
    expected[2] = 32'h00000019;  // 25
    expected[3] = 32'h00000028;  // 40
    expected[4] = 32'h0000000A;  // 10
    expected[5] = 32'h00000016;  // 22
    expected[6] = 32'h00000009;  // 9
    expected[7] = 32'h0000001F;  // 31
    expected[8] = 32'h00000001;  // 1
    expected[9] = 32'h00000000;  // 0
    expected[10] = 32'h00000027;  // 39
    expected[11] = 32'h00000040;  // 64
    expected[12] = 32'h00000123;  // 291
    expected[13] = 32'h00000123;  // 291
    expected[14] = 32'h00000028;  // 40
    expected[15] = 32'h0000014B;  // 331
    expected[16] = 32'h00000090;  // 144
    expected[17] = 32'h000000E9;  // 233
    expected[18] = 32'h0000000E;  // 14
    expected[19] = 32'h0000000E;  // 14
    expected[20] = 32'h00000261;  // 609
    expected[21] = 32'h00000015;  // 21
    expected[22] = 32'h00000015;  // 21
    expected[23] = 32'h00000006;  // 6
    expected[24] = 32'h00000015;  // 21
    expected[25] = 32'h0000001B;  // 27
    expected[26] = 32'h000000CD;  // 205
    expected[27] = 32'h12345678;  // 0x12345678
    expected[28] = 32'h55555555;  // 0x55555555
    expected[29] = 32'h4761032D;  // 0x4761032D
    expected[30] = 32'h000001F4;  // 500
    expected[31] = 32'hAEEABACA;  // Checksum

    errors = 0;
  end

  wire        wb_we = u_system.wb_reg_write;
  wire [ 4:0] wb_addr = u_system.wb_rd_addr;
  wire [31:0] wb_data = u_system.wb_fwd_data;

  always @(posedge clk) begin
    if (rst_n && wb_we && wb_addr != 5'd0) begin
      $display("[WB] t=%0t  x%0d <= 0x%h", $time, wb_addr, wb_data);
      if (log_file) $fdisplay(log_file, "[WB] t=%0t  x%0d <= 0x%h", $time, wb_addr, wb_data);
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
    @(posedge rst_n);
    $display("=====================================================");
    $display("  Starting RV32I Pipeline Self-Checking Verification");
    $display("=====================================================");
    if (log_file) begin
      $fdisplay(log_file, "=====================================================");
      $fdisplay(log_file, "  Starting RV32I Pipeline Self-Checking Verification");
      $fdisplay(log_file, "=====================================================");
    end

    wait_for_completion;

    repeat (10) @(posedge clk);

    $display("-----------------------------------------------------");
    $display("  Architectural State Check (Final Register Values)");
    $display("-----------------------------------------------------");
    if (log_file) begin
      $fdisplay(log_file, "-----------------------------------------------------");
      $fdisplay(log_file, "  Architectural State Check (Final Register Values)");
      $fdisplay(log_file, "-----------------------------------------------------");
    end

    for (k = 1; k < 32; k = k + 1) begin
      check_register(k);
    end

    $display("-----------------------------------------------------");
    $display("  Performance Summary");
    $display("-----------------------------------------------------");
    $display("  Total Cycles              : %0d", cycle_count);
    $display("  Instructions Retired      : %0d", instr_count);
    if (log_file) begin
      $fdisplay(log_file, "-----------------------------------------------------");
      $fdisplay(log_file, "  Performance Summary");
      $fdisplay(log_file, "-----------------------------------------------------");
      $fdisplay(log_file, "  Total Cycles              : %0d", cycle_count);
      $fdisplay(log_file, "  Instructions Retired      : %0d", instr_count);
    end

    if (cycle_count > 0) begin
      $display("  IPC                       : %0d (x1000)", (instr_count * 1000) / cycle_count);
      if (log_file) $fdisplay(log_file, "  IPC                       : %0d (x1000)", (instr_count * 1000) / cycle_count);
    end

    $display("  Branches Resolved         : %0d", branch_total);
    $display("  Branch Mispredicts        : %0d", branch_mispredicts);
    if (log_file) begin
      $fdisplay(log_file, "  Branches Resolved         : %0d", branch_total);
      $fdisplay(log_file, "  Branch Mispredicts        : %0d", branch_mispredicts);
    end

    if (branch_total > 0) begin
      $display(
          "  Branch Predictor Accuracy : %0d%%",
          ((branch_total - branch_mispredicts) * 100) / branch_total
      );
      if (log_file) begin
        $fdisplay(
            log_file,
            "  Branch Predictor Accuracy : %0d%%",
            ((branch_total - branch_mispredicts) * 100) / branch_total
        );
      end
    end

    $display("-----------------------------------------------------");
    if (log_file) $fdisplay(log_file, "-----------------------------------------------------");

    if (errors == 0) begin
      $display("  [SUCCESS] ALL CHECKS PASSED! 0 ERRORS.");
      if (log_file) $fdisplay(log_file, "  [SUCCESS] ALL CHECKS PASSED! 0 ERRORS.");
    end else begin
      $display("  [FAILURE] TEST SUITE FAILED WITH %0d ERRORS.", errors);
      if (log_file) $fdisplay(log_file, "  [FAILURE] TEST SUITE FAILED WITH %0d ERRORS.", errors);
    end

    $display("=====================================================");
    if (log_file) begin
      $fdisplay(log_file, "=====================================================");
      $fclose(log_file);
    end

    $finish;
  end

  task check_register;
    input integer reg_idx;
    reg [31:0] actual;
    begin
      actual = u_system.u_regfile.registers[reg_idx];
      if (actual !== expected[reg_idx]) begin
        $display("[FAIL] x%0d : Expected 0x%h, Got 0x%h", reg_idx, expected[reg_idx], actual);
        if (log_file) $fdisplay(log_file, "[FAIL] x%0d : Expected 0x%h, Got 0x%h", reg_idx, expected[reg_idx], actual);
        errors = errors + 1;
      end else begin
        $display("[PASS] x%0d = 0x%h", reg_idx, actual);
        if (log_file) $fdisplay(log_file, "[PASS] x%0d = 0x%h", reg_idx, actual);
      end
    end
  endtask

  task wait_for_completion;
    integer settle_cycles;
    begin
      settle_cycles = 0;
      while (settle_cycles < 5) begin
        @(posedge clk);
        if (u_system.imem_addr >= 32'd356) settle_cycles = settle_cycles + 1;
        else settle_cycles = 0;
      end
    end
  endtask

endmodule
