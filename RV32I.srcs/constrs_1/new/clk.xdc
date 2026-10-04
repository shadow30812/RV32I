create_clock -period 6.666 [get_ports clk]

set_load 5.000 [all_outputs]
set_property LOAD 5 [get_ports spi_cs_n]
set_property LOAD 5 [get_ports spi_mosi]
set_property LOAD 5 [get_ports spi_sclk]
