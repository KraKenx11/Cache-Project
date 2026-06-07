`timescale 1ns/1ps

module tb_cache;

    reg clk;
    reg reset;

    // CPU Sigs
    reg  [20:0] cpu_addr;
    reg         cpu_read;
    reg         cpu_write;
    reg  [31:0] cpu_wdata;
    wire [31:0] cpu_rdata;
    wire        cpu_ready;

    // Mem Sigs
    wire [20:0]  mem_addr;
    wire         mem_read;
    wire         mem_write;
    wire [255:0] mem_wdata;
    reg  [255:0] mem_rdata;
    reg          mem_ready;

    // Instanțiere Cache
    cache_32k_4way uut (
        .clk(clk), .reset(reset),
        .cpu_addr(cpu_addr), .cpu_read(cpu_read), .cpu_write(cpu_write),
        .cpu_wdata(cpu_wdata), .cpu_rdata(cpu_rdata), .cpu_ready(cpu_ready),
        .mem_addr(mem_addr), .mem_read(mem_read), .mem_write(mem_write),
        .mem_wdata(mem_wdata), .mem_rdata(mem_rdata), .mem_ready(mem_ready)
    );

    // Emulare asincronă corectă a Memoriei Principale
    initial mem_ready = 1'b0;
    always begin
        // Așteaptă o cerere de la Cache
        wait(mem_read || mem_write);
        #20; // Întârziere simulată de 20ns
        
        if (mem_read) mem_rdata = {256{1'b1}}; // Date dummy
        mem_ready = 1'b1;
        
        // Așteaptă ca Cache-ul să retragă semnalul după ce a citit/scris
        wait(!mem_read && !mem_write);
        mem_ready = 1'b0;
    end

    // Generare Ceas
    always #5 clk = ~clk;

    // Scenariu de Test
    initial begin
        clk = 0; reset = 1;
        cpu_addr = 0; cpu_read = 0; cpu_write = 0; cpu_wdata = 0;
        
        #15 reset = 0;

        // Test 1: Write Miss
        wait(cpu_ready);
        @(posedge clk);
        cpu_addr = 21'h00000A;
        cpu_wdata = 32'hDEADBEEF;
        cpu_write = 1;
        
        wait(!cpu_ready);
        @(posedge clk); cpu_write = 0;
        
        // Test 2: Read Hit la aceeași adresă
        wait(cpu_ready);
        @(posedge clk);
        cpu_addr = 21'h00000A;
        cpu_read = 1;
        
        wait(!cpu_ready);
        @(posedge clk); cpu_read = 0;

        // Test 3: Provocare Write-Back
        wait(cpu_ready);
        
        @(posedge clk); cpu_addr = 21'h000808; cpu_write = 1; cpu_wdata = 32'hAAAAAAAA; wait(!cpu_ready); @(posedge clk); cpu_write = 0; wait(cpu_ready);
        @(posedge clk); cpu_addr = 21'h001008; cpu_write = 1; cpu_wdata = 32'hBBBBBBBB; wait(!cpu_ready); @(posedge clk); cpu_write = 0; wait(cpu_ready);
        @(posedge clk); cpu_addr = 21'h001808; cpu_write = 1; cpu_wdata = 32'hCCCCCCCC; wait(!cpu_ready); @(posedge clk); cpu_write = 0; wait(cpu_ready);
        @(posedge clk); cpu_addr = 21'h002008; cpu_write = 1; cpu_wdata = 32'hDDDDDDDD; wait(!cpu_ready); @(posedge clk); cpu_write = 0; wait(cpu_ready);

        #50;
        $stop;
    end

endmodule