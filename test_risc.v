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

  reg [7:0] spi_rx_data;
  integer bit_cnt;

  always @(posedge spi_sclk or posedge spi_cs_n) begin
    if (spi_cs_n) begin
      bit_cnt <= 0;
      spi_rx_data <= 8'h00;
    end else begin
      spi_rx_data <= {spi_rx_data[6:0], spi_mosi};
      bit_cnt <= bit_cnt + 1;

      if (bit_cnt == 7) begin
        $display("[%0t] SPI Slave Received Data: 0x%h", $time, {spi_rx_data[6:0], spi_mosi});
      end
    end
  end

  initial begin
    rst_n = 0;
    spi_miso = 0;

    $dumpfile("RV32I/dump_risc.vcd");
    $dumpvars(0, tb_risc);

    #20 rst_n = 1;

    #5000;

    $display("Simulation Finished.");
    $finish;
  end

endmodule
