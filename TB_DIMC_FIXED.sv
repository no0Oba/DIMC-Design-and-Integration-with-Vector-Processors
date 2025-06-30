`timescale 1ns/1ps
module tb_DIMC_latency_fixed();

// Clock and Reset
logic RCK;
logic RESETn;

// DIMC I/O Signals
logic READYN;
logic COMPE;
logic FCSN;
logic [1:0] MODE;
logic [1:0] FA;
logic [255:0] FD;
logic [23:0] ADDIN;
logic SOUT;
logic [2:0] RES_OUT;
logic [23:0] PSOUT;
logic [255:0] Q;
logic [255:0] D;
logic [6:0] RA;
logic [6:0] WA;
logic RCSN, RCSN0, RCSN1, RCSN2, RCSN3;
logic WCK;
logic WCSN;
logic WEN;
logic [255:0] M;
logic [7:0] MCT;

// Instantiate DUT
DIMC_18_fixed dut (
    .RCK(RCK), .RESETn(RESETn), .READYN(READYN),
    .COMPE(COMPE), .FCSN(FCSN), .MODE(MODE),
    .FA(FA), .FD(FD), .ADDIN(ADDIN),
    .SOUT(SOUT), .RES_OUT(RES_OUT), .PSOUT(PSOUT),
    .Q(Q), .D(D), .RA(RA), .WA(WA),
    .RCSN(RCSN), .RCSN0(RCSN0), .RCSN1(RCSN1), .RCSN2(RCSN2), .RCSN3(RCSN3),
    .WCK(WCK), .WCSN(WCSN), .WEN(WEN),
    .M(M), .MCT(MCT)
);

// Clock generation (100MHz)
initial begin
    RCK = 0;
    WCK = 0;  // Initialize WCK
    forever begin
        #5 RCK = ~RCK;
        WCK = RCK;  // Mirror RCK for write clock
    end
end

// Reset initialization
initial begin
    RESETn = 0;
    RCK = 0;
    WCK = 0;
    COMPE = 0; FCSN = 1; MODE = 0;
    FA = 0; FD = 0; ADDIN = 0;
    D = 0; RA = 0; WA = 0;
    RCSN = 1; RCSN0 = 1; RCSN1 = 1; RCSN2 = 1; RCSN3 = 1;
    WCSN = 1; WEN = 1;
    M = 0; MCT = 0;
    
    #20 RESETn = 1;
    $display("[%0t] Reset released", $time);
end

// Main test sequence
initial begin
    wait(RESETn);
    #10;
    
    $display("\n===== TEST 1: Memory Mode Latency =====");
    test_memory_latency();
    
    $display("\n===== TEST 2: MAC Mode Initial Latency =====");
    test_mac_initial_latency();
    
    $display("\n===== TEST 3: MAC Mode Pipelining =====");
    test_mac_pipelining();
    
    $display("\n===== TEST 4: Pipeline Sequence =====");
    test_pipeline_sequence();
    
    $display("\n===== ALL LATENCY TESTS PASSED =====");
    #100 $finish;
end

// ==================================================
// Test Tasks
// ==================================================

// Test memory mode latency (1 cycle operations)
task test_memory_latency();
    real start_time, write_time, read_time;
    
    
    @(negedge RCK);                    // Align to clock midpoint
    M = '1;                            // Setup mask first

    // Align to clock edge
    @(posedge RCK);
    
    // Write operation (1 cycle)
    start_time = $time;
    WA = 0; D = 256'hA5A5A5A5A5A5A5A5A5A5A5A5A5A5A5A5; WCSN = 0; WEN = 0;
    @(posedge RCK);    WCSN = 1; WEN = 1;
    write_time = $time - start_time;
    $display("[MEM] Write operation took %0t ns", write_time);
    
    // Write to complete 
    //@(posedge RCK);

    // Read operation (1 cycle)
    start_time = $time;
    RA = 0; RCSN = 0;
    //@(posedge RCK);   
    @(posedge RCK);
    //#0.01; 
    @(Q); // wait for Q to change (if it's a signal-driven read) 
    RCSN = 1; 
    read_time = $time - start_time;
    $display("[MEM] Read operation took %0t ns", read_time);
   
    
   
    // Verify both operations took exactly 10ns (1 cycle)
    if (write_time != 10) 
        $error("Write latency incorrect! Expected 10ns, got %0t", write_time);
    else 
        $display("Write latency verified");
    
    if (read_time != 10) 
        $error("Read latency incorrect! Expected 10ns, got %0t", read_time);
    else 
        $display("Read latency verified");
    
    if (Q !== 1024'h00000000000000000000000000000000a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5) 
        $error("Read data mismatch! Expected A5A5A5A5, got %h", Q);
    else 
        $display("Data integrity verified");
    
    $display("[PASS] Memory mode latency test");
endtask

// Test MAC mode initial latency (4 cycles)
task test_mac_initial_latency();
    real start_time, latency;
    
    // Setup simple pattern
    write_kernel(0, 0, 256'h00010001); // 4-bit pattern
    write_kernel(0, 1, 256'h00010010);
    write_kernel(0, 2, 256'h00010100);
    write_kernel(0, 3, 256'h00011000);
    write_feature(0, 256'h00011111);
    
    // Start computation
    @(posedge RCK);
    start_time = $time;
    start_compute(0, 2'b10); // 4-bit MAC mode
    wait(READYN == 0);
    latency = $time - start_time;
    
    $display("[MAC] First result latency: %0t ns", latency);
    
    // Verify latency is 40ns (4 cycles)
    if (latency != 40) 
        $error("Initial latency incorrect! Expected 40ns, got %0t", latency);
    else 
        $display("[PASS] MAC initial latency verified");
endtask

// Test MAC mode pipelining (1 result/cycle after initial latency)
task test_mac_pipelining();
    real times[4];
    real delta;
    int i;
    
    // Start 4 consecutive computations
    @(posedge RCK);
    //for (i = 0; i < 4; i++) begin
    begin
        start_compute(0, 2'b00); // Start new computation //I edited 2'10
        #10; // Wait 1 cycle between starts
	start_compute(0, 2'b10); // Start new computation //I edited 2'10
        #10; // Wait 1 cycle between starts
	start_compute(0, 2'b00); // Start new computation //I edited 2'10
        #10; // Wait 1 cycle between starts
   	start_compute(0, 2'b10); // Start new computation //I edited 2'10
        #10; // Wait 1 cycle between starts
    end
    
    // Wait for first result (should appear at 40ns latency)
    #30; // Wait 3 cycles after last start
    
    // Measure timing of subsequent results
    for (i = 0; i < 4; i++) begin
        wait(READYN == 0);
        times[i] = $time;
        $display("[PIPE] Result %0d at %0t ns", i, times[i]);
        #10; // Prepare for next result
    end
    
    // Verify time between results is 10ns (1 cycle)
    for (i = 1; i < 4; i++) begin
        delta = times[i] - times[i-1];
        if (delta != 10) 
            $error("Result interval %0d incorrect! Expected 10ns, got %0t", i, delta);
        else 
            $display("Interval %0d verified: 10ns", i);
    end
    
    $display("[PASS] Pipelined throughput verified");
endtask

// Test pipeline sequence with continuous RCSN
task test_pipeline_sequence();
    int row;
    real times[5];
    
    $display("\nTesting continuous pipeline with RCSN held low");
    
    // Initialize pattern
    for (row = 0; row < 5; row++) begin
        for (int sec = 0; sec < 4; sec++) begin
            write_kernel(row, sec, '1);
        end
    end
    for (int sec = 0; sec < 4; sec++) begin
        write_feature(sec, '1);
    end
    
    // Start continuous computations with RCSN held low
    @(posedge RCK);
    RCSN = 0;  // Hold low for continuous operation
    for (row = 0; row < 5; row++) begin
        start_compute(row, 2'b00);  // 1-bit mode
        #10;  // Start new operation every cycle
    end
    RCSN = 1;
    
    // Wait for first result (should appear at 40ns)
    #35;
    
    // Capture result times
    for (int i = 0; i < 5; i++) begin
        wait(READYN == 0);
        times[i] = $time;
        $display("[PIPE] Result %0d (Row %0d) at %0t ns", i, i, times[i]);
        verify_result(1024, 4'b1111);
        #10;  // Next result each cycle
    end
    
    // Verify intervals
    for (int i = 1; i < 5; i++) begin
      automatic real delta = times[i] - times[i-1];
        if (delta != 10) 
            $error("Result %0d interval incorrect! Expected 10ns, got %0t", i, delta);
        else 
            $display("Result %0d interval verified: 10ns", i);
    end
    
    $display("[PASS] Pipeline sequence verified");
endtask

// Helper tasks
task write_kernel(input int row, input int sec, input [255:0] data);
    WA = {row[4:0], sec[1:0]};
    D = data;
    M = '1;
    WCSN = 0; WEN = 0;
    @(posedge RCK);
    WCSN = 1; WEN = 1;
    $display("[%0t] Wrote kernel row %0d sec %0d: %h", $time, row, sec, data);
endtask

task write_feature(input int sec, input [255:0] data);
    FA = sec;
    FD = data;
    FCSN = 0;
    @(posedge RCK);
    FCSN = 1;
    $display("[%0t] Wrote feature sec %0d: %h", $time, sec, data);
endtask

task start_compute(input int row, input [1:0] mode);
    COMPE = 1;
    MODE = mode;
    ADDIN = 0;
    RA = {row[4:0], 2'b00};
    RCSN = 0; RCSN0 = 0; RCSN1 = 0; RCSN2 = 0; RCSN3 = 0;
    @(posedge RCK);
    RCSN = 1; RCSN0 = 1; RCSN1 = 1; RCSN2 = 1; RCSN3 = 1;
    COMPE = 0;
    $display("[%0t] Started compute row %0d mode %b", $time, row, mode);
endtask

task verify_result(input [23:0] expected_psout, input [3:0] expected_out);
    logic [3:0] actual_out;
    actual_out = {RES_OUT, SOUT};
    
    if (PSOUT !== expected_psout) begin
        $error("PSOUT mismatch! Expected %0d, Got %0d", expected_psout, PSOUT);
    end
    else if (actual_out !== expected_out) begin
        $error("Output mismatch! Expected %b, Got %b", expected_out, actual_out);
    end
    else begin
        $display("Result verified: %0d -> %b", expected_psout, expected_out);
    end
endtask

// Monitor
always @(posedge RCK) begin
    if (READYN === 1'b0) begin
        $display("[%0t] OUTPUT: PSOUT=%0d RES_OUT=%b SOUT=%b", 
                $time, PSOUT, RES_OUT, SOUT);
    end
end

endmodule
