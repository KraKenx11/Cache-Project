`timescale 1ns/1ps

module memory
  #(parameter ADDRESS_WIDTH = 18,
    parameter BLOCK_SIZE = 256,
    parameter MEM_FILE = "mem_data.txt"
    )
   (
    input logic clock,
    input logic [BLOCK_SIZE - 1:0] din,
    input logic [ADDRESS_WIDTH - 1:0] address,
    input logic rden,
    input logic wren,
    output logic [BLOCK_SIZE -1:0] dout
    );
    
   localparam DEPTH = 2 ** ADDRESS_WIDTH;
   
   reg [BLOCK_SIZE-1:0] mem_array [0:DEPTH-1];
   integer i;

   initial begin
	// initializam cu 0
      for (i = 0; i < DEPTH; i = i + 1) begin
         mem_array[i] = {BLOCK_SIZE{1'b0}};
      end

      if (MEM_FILE != "") begin
         $display("Se incarca memoria din %s...", MEM_FILE);
         $readmemh(MEM_FILE, mem_array);
      end
   end

   always @(posedge clock) begin
      if (wren)
         mem_array[address] <= din;
   end

   always @(posedge clock) begin
      if (rden)
         dout <= mem_array[address];
   end

endmodule