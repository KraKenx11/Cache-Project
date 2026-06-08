`timescale 1ns/1ps

module cache_controller
  #(
    parameter BLOCK_SIZE = 256,
    parameter ADDRESS_WIDTH = 21,
    parameter INDEX_WIDTH = 8,
    parameter TAG_WIDTH = 10,
    parameter OFFSET_WIDTH = 3,
    parameter WORD_SIZE = 32,
    parameter SETS = 256,
    parameter WAYS = 4
)
   (
    input logic                                  clock,
    input logic                                  rst_n,
    input logic [ADDRESS_WIDTH - 1:0]            caddress,
    input logic [WORD_SIZE - 1:0]                cdin,
    input logic                                  rden,
    input logic                                  wren,
    output logic                                 hit,
    output logic [WORD_SIZE - 1:0]               cdout,
    input logic [BLOCK_SIZE - 1:0]               mdin,
    output logic [BLOCK_SIZE - 1:0]              mdout,
    output logic [TAG_WIDTH + INDEX_WIDTH - 1:0] maddress,
    output logic                                 mrden,
    output logic                                 mwren
    );

   typedef enum logic [2:0] {
      STATE_IDLE, STATE_READ_HIT, STATE_READ_MISS, STATE_WRITE_HIT,
      STATE_WRITE_MISS, STATE_REPLACE, STATE_FETCH, STATE_FILL
   } state_t;

   state_t current_state, next_state;

   localparam TAG_MSB           = 20;
   localparam TAG_LSB           = 11;
   localparam INDEX_MSB         = 10;
   localparam INDEX_LSB         = 3;
   localparam BLOCK_OFFSET_MSB  = 2;
   localparam BLOCK_OFFSET_LSB  = 0;

   logic                         cache_valid [0:SETS - 1][0:WAYS - 1];
   logic                         cache_dirty [0:SETS - 1][0:WAYS - 1];
   logic [TAG_WIDTH - 1:0]       cache_tag   [0:SETS - 1][0:WAYS - 1];
   logic [BLOCK_SIZE - 1:0]      cache_mem   [0:SETS - 1][0:WAYS - 1];
   logic [1:0]                   cache_lru   [0:SETS - 1][0:WAYS - 1];

   logic [ADDRESS_WIDTH - 1:0]   req_addr;
   logic                         req_read;
   logic                         req_write;
   logic [WORD_SIZE - 1:0]       req_wdata;

   logic [ADDRESS_WIDTH - 1:0]   active_addr;
   logic [INDEX_WIDTH - 1:0]     active_index;
   logic [TAG_WIDTH - 1:0]       active_tag;
   logic [OFFSET_WIDTH - 1:0]    active_offset;

   logic                         lookup_hit;
   logic [1:0]                   hit_way;
   logic [1:0]                   lru_way;
   logic [1:0]                   active_way;

   function automatic logic [WORD_SIZE - 1:0] block_get_word(
      input logic [BLOCK_SIZE - 1:0] block,
      input logic [OFFSET_WIDTH - 1:0] word_offset
   );
      return block[32 * word_offset +: WORD_SIZE];
   endfunction

   function automatic logic [BLOCK_SIZE - 1:0] block_set_word(
      input logic [BLOCK_SIZE - 1:0] block,
      input logic [OFFSET_WIDTH - 1:0] word_offset,
      input logic [WORD_SIZE - 1:0] word
   );
      logic [BLOCK_SIZE - 1:0] result;
      result = block;
      result[32 * word_offset +: WORD_SIZE] = word;
      return result;
   endfunction

   assign active_addr = (current_state == STATE_IDLE) ? caddress : req_addr;
   assign active_index   = active_addr[INDEX_MSB:INDEX_LSB];
   assign active_tag     = active_addr[TAG_MSB:TAG_LSB];
   assign active_offset  = active_addr[BLOCK_OFFSET_MSB:BLOCK_OFFSET_LSB];

   always_comb begin
      lookup_hit = 1'b0; hit_way = 2'd0; lru_way = 2'd0;
      for (int i = 0; i < WAYS; i++) begin
         if (cache_valid[active_index][i] && (cache_tag[active_index][i] == active_tag)) begin
            lookup_hit = 1'b1; hit_way = 2'(i);
         end
         if (cache_lru[active_index][i] == 2'd3) lru_way = 2'(i);
      end
   end

   assign hit = lookup_hit && (current_state == STATE_IDLE);

   always_comb begin
      next_state = current_state;
      cdout = '0; mdout = '0; maddress = '0; mrden = 1'b0; mwren = 1'b0;

      case (current_state)
         STATE_IDLE: begin
            if (rden && lookup_hit)       next_state = STATE_READ_HIT;
            else if (rden)                next_state = STATE_READ_MISS;
            else if (wren && lookup_hit)  next_state = STATE_WRITE_HIT;
            else if (wren)                next_state = STATE_WRITE_MISS;
         end
         STATE_READ_HIT: begin
            cdout = block_get_word(cache_mem[active_index][active_way], active_offset);
            next_state = STATE_IDLE;
         end
         STATE_READ_MISS, STATE_WRITE_MISS: begin
            if (cache_dirty[active_index][active_way]) next_state = STATE_REPLACE;
            else next_state = STATE_FETCH;
         end
         STATE_REPLACE: begin
            mwren = 1'b1;
            maddress = {cache_tag[active_index][active_way], active_index};
            mdout = cache_mem[active_index][active_way];
            next_state = STATE_FETCH;
         end
         STATE_FETCH: begin
            mrden = 1'b1;
            maddress = {active_tag, active_index};
            next_state = STATE_FILL;
         end
         STATE_FILL: begin
            if (req_read) next_state = STATE_READ_HIT;
            else if (req_write) next_state = STATE_WRITE_HIT;
            else next_state = STATE_IDLE;
         end
         STATE_WRITE_HIT: next_state = STATE_IDLE;
         default: next_state = STATE_IDLE;
      endcase
   end

   integer s, w, i;
   always_ff @(posedge clock) begin
      if (!rst_n) begin
         current_state <= STATE_IDLE; req_read <= 1'b0; req_write <= 1'b0; active_way <= 2'b00;
         for (s = 0; s < SETS; s = s + 1) begin
            for (w = 0; w < WAYS; w = w + 1) begin
               cache_valid[s][w] <= 1'b0; cache_dirty[s][w] <= 1'b0;
               cache_tag[s][w] <= '0; cache_mem[s][w] <= '0;
               cache_lru[s][w] <= 2'(3 - w);
            end
         end
      end else begin
         current_state <= next_state;
         if (current_state == STATE_IDLE && (rden || wren)) begin
            req_addr <= caddress; req_read <= rden; req_write <= wren; req_wdata <= cdin;
            active_way <= lookup_hit ? hit_way : lru_way;
         end

         if (current_state == STATE_READ_HIT || current_state == STATE_WRITE_HIT) begin
            for (i = 0; i < WAYS; i++) begin
               if (i == active_way) cache_lru[active_index][i] <= 2'd0;
               else if (cache_lru[active_index][i] < cache_lru[active_index][active_way])
                  cache_lru[active_index][i] <= cache_lru[active_index][i] + 1;
            end
         end

         if (current_state == STATE_FILL) begin
            cache_mem[active_index][active_way] <= mdin;
            cache_tag[active_index][active_way] <= active_tag;
            cache_valid[active_index][active_way] <= 1'b1;
            cache_dirty[active_index][active_way] <= 1'b0;
         end

         if (current_state == STATE_WRITE_HIT) begin
            cache_mem[active_index][active_way] <= block_set_word(cache_mem[active_index][active_way], active_offset, req_wdata);
            cache_dirty[active_index][active_way] <= 1'b1;
         end
      end
   end

endmodule
