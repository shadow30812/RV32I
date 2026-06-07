_start:
    lui x5, 0x80000       # Load Base Address 0x8000_0000 into t0 (x5)
    
    # Configure SPI (CPOL = 0, CPHA = 0)
    addi x6, x0, 0        # Load 0 into t1 (x6)
    sw x6, 4(x5)          # Store to 0x8000_0004 (Control Register)
    
    # Send Data via SPI
    addi x7, x0, 0x5A     # Load payload (0x5A) into t2 (x7)
    sw x7, 0(x5)          # Store to 0x8000_0000 (TX Register)
    
end_loop:
    jal x0, end_loop      # Infinite loop to end program gracefully