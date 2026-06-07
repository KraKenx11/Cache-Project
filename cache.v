`timescale 1ns/1ps

module cache_32k_4way (
    input  wire        clk,
    input  wire        reset,

    // Interfața cu Procesorul (CPU)
    input  wire [20:0] cpu_addr,
    input  wire        cpu_read,
    input  wire        cpu_write,
    input  wire [31:0] cpu_wdata,
    output reg  [31:0] cpu_rdata,
    output reg         cpu_ready,

    // Interfața cu Memoria Principală
    output reg  [20:0]  mem_addr,
    output reg          mem_read,
    output reg          mem_write,
    output reg  [255:0] mem_wdata,
    input  wire [255:0] mem_rdata,
    input  wire         mem_ready
);

    // Definire stări FSM
    localparam IDLE       = 2'b00;
    localparam COMPARE    = 2'b01;
    localparam WRITE_BACK = 2'b10;
    localparam ALLOCATE   = 2'b11;

    reg [1:0] state;

    // Structura cache-ului
    reg [31:0] data_array  [0:255][0:3][0:7];
    reg [9:0]  tag_array   [0:255][0:3];
    reg        valid_array [0:255][0:3];
    reg        dirty_array [0:255][0:3];
    reg [1:0]  lru_array   [0:255][0:3];

    // Extragere câmpuri din adresă
    wire [2:0] offset;
    wire [7:0] index;
    wire [9:0] tag;
    
    assign offset = cpu_addr[2:0];
    assign index  = cpu_addr[10:3];
    assign tag    = cpu_addr[20:11];

    // Semnale interne combinatoare
    reg hit;
    reg [1:0] hit_way;
    reg [1:0] lru_way;

    // Variabile separate pentru a evita buclele infinite (Race Conditions)
    integer r_i, r_j; // pentru reset
    integer c_i;      // pentru block-ul combinator Hit
    integer l_i;      // pentru block-ul combinator LRU
    integer u_i;      // pentru actualizarea LRU

    // Logica de Hit
    always @(*) begin
        hit = 1'b0;
        hit_way = 2'b00;
        for (c_i = 0; c_i < 4; c_i = c_i + 1) begin
            if (valid_array[index][c_i] && (tag_array[index][c_i] == tag)) begin
                hit = 1'b1;
                hit_way = c_i[1:0];
            end
        end
    end

    // Găsirea blocului LRU
    always @(*) begin
        lru_way = 2'b00;
        for (l_i = 0; l_i < 4; l_i = l_i + 1) begin
            if (lru_array[index][l_i] == 2'b11) begin
                lru_way = l_i[1:0];
            end
        end
    end

    // FSM - Logica principală (Single-Always Block)
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            // Resetare array-uri (doar la reset)
            for (r_i = 0; r_i < 256; r_i = r_i + 1) begin
                for (r_j = 0; r_j < 4; r_j = r_j + 1) begin
                    valid_array[r_i][r_j] <= 1'b0;
                    dirty_array[r_i][r_j] <= 1'b0;
                    lru_array[r_i][r_j]   <= r_j[1:0];
                end
            end
            cpu_ready <= 1'b0;
            mem_read  <= 1'b0; 
            mem_write <= 1'b0;
            cpu_rdata <= 32'b0;
            mem_addr  <= 21'b0;
            mem_wdata <= 256'b0;
            state     <= IDLE;
        end else begin
            case (state)
                IDLE: begin
                    cpu_ready <= 1'b1;
                    if (cpu_read || cpu_write) begin
                        cpu_ready <= 1'b0;
                        state <= COMPARE;
                    end
                end

                COMPARE: begin
                    if (hit) begin
                        // Actualizare Date & Dirty Bit
                        if (cpu_read) begin
                            cpu_rdata <= data_array[index][hit_way][offset];
                        end else if (cpu_write) begin
                            data_array[index][hit_way][offset] <= cpu_wdata;
                            dirty_array[index][hit_way] <= 1'b1;
                        end

                        // Actualizare Politică LRU (0 devine MRU)
                        for (u_i = 0; u_i < 4; u_i = u_i + 1) begin
                            if (lru_array[index][u_i] < lru_array[index][hit_way])
                                lru_array[index][u_i] <= lru_array[index][u_i] + 1;
                        end
                        lru_array[index][hit_way] <= 2'b00;

                        state <= IDLE;
                    end else begin // Miss
                        if (valid_array[index][lru_way] && dirty_array[index][lru_way]) begin
                            state <= WRITE_BACK;
                        end else begin
                            state <= ALLOCATE;
                        end
                    end
                end

                WRITE_BACK: begin
                    mem_addr  <= {tag_array[index][lru_way], index, 3'b000};
                    mem_write <= 1'b1;
                    mem_wdata <= {data_array[index][lru_way][7], data_array[index][lru_way][6], 
                                  data_array[index][lru_way][5], data_array[index][lru_way][4], 
                                  data_array[index][lru_way][3], data_array[index][lru_way][2], 
                                  data_array[index][lru_way][1], data_array[index][lru_way][0]};
                    
                    if (mem_ready) begin
                        mem_write <= 1'b0;
                        state <= ALLOCATE;
                    end
                end

                ALLOCATE: begin
                    mem_addr <= {tag, index, 3'b000};
                    mem_read <= 1'b1;
                    
                    if (mem_ready) begin
                        mem_read <= 1'b0;
                        
                        data_array[index][lru_way][0] <= mem_rdata[31:0];
                        data_array[index][lru_way][1] <= mem_rdata[63:32];
                        data_array[index][lru_way][2] <= mem_rdata[95:64];
                        data_array[index][lru_way][3] <= mem_rdata[127:96];
                        data_array[index][lru_way][4] <= mem_rdata[159:128];
                        data_array[index][lru_way][5] <= mem_rdata[191:160];
                        data_array[index][lru_way][6] <= mem_rdata[223:192];
                        data_array[index][lru_way][7] <= mem_rdata[255:224];
                        
                        tag_array[index][lru_way]   <= tag;
                        valid_array[index][lru_way] <= 1'b1;
                        dirty_array[index][lru_way] <= 1'b0;

                        state <= COMPARE; 
                    end
                end
                
                default: state <= IDLE;
            endcase
        end
    end
endmodule