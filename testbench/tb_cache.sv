`timescale 1ns/1ps

module tb_cache;

   localparam BLOCK_SIZE     = 256;
   localparam ADDRESS_WIDTH  = 21;
   localparam INDEX_WIDTH    = 8;
   localparam TAG_WIDTH      = 10;
   localparam OFFSET_WIDTH   = 3;
   localparam WORD_SIZE      = 32;
   localparam SETS           = 256;
   localparam WAYS           = 4;

   localparam int CLK_PERIOD = 200;

   logic                                 clock;
   logic                                 rst_n;
   logic [ADDRESS_WIDTH - 1:0]           caddress;
   logic [WORD_SIZE - 1:0]               cdin;
   logic [BLOCK_SIZE - 1:0]              mdin;
   logic                                 rden;
   logic                                 wren;
   logic                                 hit;
   logic [WORD_SIZE - 1:0]               cdout;
   logic [BLOCK_SIZE - 1:0]              mdout;
   logic [TAG_WIDTH + INDEX_WIDTH - 1:0] maddress;
   logic                                 mrden;
   logic                                 mwren;

   int fd_log;

   // instantiere controller Cache L1
   cache_controller #(
      .BLOCK_SIZE(BLOCK_SIZE), .ADDRESS_WIDTH(ADDRESS_WIDTH), .INDEX_WIDTH(INDEX_WIDTH),
      .TAG_WIDTH(TAG_WIDTH), .OFFSET_WIDTH(OFFSET_WIDTH), .WORD_SIZE(WORD_SIZE),
      .SETS(SETS), .WAYS(WAYS)
   ) DUT_CACHE ( .* );

   // instantierea main memory
   memory #(
      .ADDRESS_WIDTH(TAG_WIDTH + INDEX_WIDTH), .BLOCK_SIZE(BLOCK_SIZE), .MEM_FILE("mem_data.txt")
   ) DUT_MEM (
      .clock(clock), .din(mdout), .address(maddress),
      .rden(mrden), .wren(mwren), .dout(mdin)
   );

   always #(CLK_PERIOD / 2) clock = ~clock;

   task automatic wait_cycles(input int n);
      repeat (n) @(posedge clock);
   endtask

   task automatic perform_cache_op(input logic [ADDRESS_WIDTH-1:0] addr, input logic [WORD_SIZE-1:0] data, input logic is_write);
      caddress <= addr;
      cdin     <= data;
      rden     <= !is_write;
      wren     <= is_write;
      
      @(posedge clock);
      rden     <= 1'b0;
      wren     <= 1'b0;
      
      // fortam asteptarea unui ciclu complet pentru ca fsm-ul sa apuce sa paraseasca IDLE
      @(posedge clock);
      
      // asteptam intr-o bucla pana cand fsm-ul isi termina toate stările intermediare
      // si revine in starea IDLE.
      while (DUT_CACHE.current_state != DUT_CACHE.STATE_IDLE) begin
         @(posedge clock);
      end
   endtask

   initial begin
      fd_log = $fopen("cache_controller_tb.log", "w");
      $fdisplay(fd_log, "VCD info: dumpfile cache_controller_tb.vcd opened for output.");
      
      $fmonitor(fd_log, "time=%5d | addr=%06x | hit=%b | cdout=%08x | cache[0][0]=%064x", 
                $time, caddress, hit, cdout, DUT_CACHE.cache_mem[0][0]);

      clock = 1'b1; rst_n = 1'b0; caddress = '0; cdin = '0; rden = 1'b0; wren = 1'b0;

      $dumpfile("cache_controller_tb.vcd");
      $dumpvars;

      wait_cycles(2);
      rst_n = 1'b1;
      wait_cycles(1);

      // SIMULARE
      
      // 1. Read Miss pe adresa 21'h000800 -> aduce blocul corespunzator din mem_data.txt direct in Way 0
      perform_cache_op(21'h000800, 32'h0, 1'b0); 
      
      // 2. Read Hit pe aceeasi adresa pentru a confirma stocarea stabila
      perform_cache_op(21'h000800, 32'h0, 1'b0);
      
      // 3. ocupam controlat si celelalte 3 cai ramase libere din Setul 0
      perform_cache_op(21'h001000, 32'hAAAA_1111, 1'b1); // Way 1
      perform_cache_op(21'h001800, 32'hBBBB_2222, 1'b1); // Way 2
      perform_cache_op(21'h002000, 32'hCCCC_3333, 1'b1); // Way 3 (set 0 plin)
      
      // 4. generam un Conflict Miss
      // LRU va selecta cea mai veche cale (Way 0), ii va evacua datele si va pune noua valoare
      perform_cache_op(21'h002800, 32'hEEEE_5555, 1'b1); 
      
      // 5. Read Hit final de verificare pe noul bloc alocat
      perform_cache_op(21'h002800, 32'h0, 1'b0);

      wait_cycles(5);
      $fclose(fd_log);
      $finish;
   end

endmodule