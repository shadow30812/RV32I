`timescale 1ns / 1ps

// Regression testbench: runs one program and checks its final state.
//
//   +hex=<file>  program image (asm.py output), loaded into instruction RAM
//   +chk=<file>  checks generated from the program's .exp by run_regression.sh,
//                one "<kind> <index> <value>" line each, value in hex:
//                  0 <reg>  <value>   register
//                  1 <word> <value>   data RAM word (byte address / 4)
//                  2 0      <count>   branch/JAL resolutions
//
// A program ends in "jal x0, <self>" (0x0000006F). The run stops counting when that halt
// jump resolves, lets the pipeline drain, then checks. The testbench also fails if a branch
// or JAL ever resolves during an ID hazard stall, or in the event of a timeout.

module tb_regress;

  localparam HALT_INST = 32'h0000006F;
  localparam MAX_CYCLES = 20000;
  localparam DRAIN_CYCLES = 20;

  reg clk;
  reg rst_n;
  reg spi_miso;
  wire spi_mosi, spi_sclk, spi_cs_n;

  system u_system (
      .clk     (clk),
      .rst_n   (rst_n),
      .spi_miso(spi_miso),
      .spi_mosi(spi_mosi),
      .spi_sclk(spi_sclk),
      .spi_cs_n(spi_cs_n)
  );

  initial begin
    clk = 0;
    forever #5 clk = ~clk;
  end

  // Program image: ram.v's $readmemh runs at time 0, load later
  reg [1023:0] hex_file;
  reg [1023:0] chk_file;

  initial begin
    rst_n    = 0;
    spi_miso = 0;
    if (!$value$plusargs("hex=%s", hex_file) || !$value$plusargs("chk=%s", chk_file)) begin
      $display("[FAIL] usage: vvp <sim> +hex=<program.hex> +chk=<program.chk>");
      $finish;
    end
    #1 $readmemh(hex_file, u_system.u_ram.iram);
    #19 rst_n = 1;
  end

  // Branch resolution and hazard probes
  wire           branch_resolved = u_system.u_decode.actual_branch_valid;
  wire           branch_mispredict = u_system.u_decode.actual_mispredict;
  wire           id_hazard_stall = u_system.u_hazard.id_hazard_stall;
  wire    [31:0] id_inst = u_system.if_id_inst;
  wire           halt_resolved = branch_resolved && (id_inst == HALT_INST);

  integer        cycle_count;
  integer        branch_total;
  integer        branch_mispredicts;
  integer        stall_violations;
  reg            halted;

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      cycle_count        <= 0;
      branch_total       <= 0;
      branch_mispredicts <= 0;
      stall_violations   <= 0;
      halted             <= 1'b0;
    end else begin
      cycle_count <= cycle_count + 1;

      if (branch_resolved && id_hazard_stall) begin
        if (stall_violations == 0)
          $display(
              "[FAIL] t=%0t: branch at PC 0x%h resolved during an ID hazard stall",
              $time,
              u_system.u_decode.actual_pc
          );
        stall_violations <= stall_violations + 1;
      end

      if (halt_resolved) halted <= 1'b1;
      else if (!halted) begin
        if (branch_resolved) branch_total <= branch_total + 1;
        if (branch_mispredict) branch_mispredicts <= branch_mispredicts + 1;
      end
    end
  end

  integer errors;
  integer checks;
  integer fd;
  integer n;
  integer kind;
  integer idx;
  reg [31:0] value;
  reg [31:0] actual;

  initial begin
    errors = 0;
    checks = 0;
    @(posedge rst_n);

    while (!halted && cycle_count < MAX_CYCLES) @(posedge clk);
    if (!halted) begin
      $display("[FAIL] timeout: halt loop not reached after %0d cycles", MAX_CYCLES);
      errors = errors + 1;
    end
    repeat (DRAIN_CYCLES) @(posedge clk);

    fd = $fopen(chk_file, "r");
    if (fd == 0) begin
      $display("[FAIL] cannot open %0s", chk_file);
      $finish;
    end

    n = $fscanf(fd, "%d %d %h\n", kind, idx, value);
    while (n == 3) begin
      checks = checks + 1;
      case (kind)
        0: begin
          actual = u_system.u_regfile.registers[idx];
          if (actual !== value) begin
            $display("[FAIL] x%0d: expected 0x%h, got 0x%h", idx, value, actual);
            errors = errors + 1;
          end
        end
        1: begin
          actual = u_system.u_ram.dram[idx];
          if (actual !== value) begin
            $display("[FAIL] RAM[0x%h]: expected 0x%h, got 0x%h", idx * 4, value, actual);
            errors = errors + 1;
          end
        end
        2: begin
          if (branch_total != value) begin
            $display("[FAIL] branch resolutions: expected %0d, got %0d", value, branch_total);
            errors = errors + 1;
          end
        end
        default: begin
          $display("[FAIL] bad check kind %0d in %0s", kind, chk_file);
          errors = errors + 1;
        end
      endcase
      n = $fscanf(fd, "%d %d %h\n", kind, idx, value);
    end
    $fclose(fd);

    if (checks == 0) begin
      $display("[FAIL] no checks read from %0s", chk_file);
      errors = errors + 1;
    end
    if (stall_violations != 0) errors = errors + 1;

    $display("  %0d checks, %0d cycles, %0d branches, %0d mispredicts", checks, cycle_count,
             branch_total, branch_mispredicts);
    if (errors == 0) $display("RESULT: PASS");
    else $display("RESULT: FAIL (%0d errors)", errors);
    $finish;
  end

endmodule
