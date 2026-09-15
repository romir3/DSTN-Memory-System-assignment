module l1_cache #(
    parameter ADDR_WIDTH = 26,
    parameter DATA_WIDTH = 32,

    parameter SETS = 128,
    parameter WAYS = 4,
    parameter BLOCK_BYTES = 16
)(
    input clk,
    input reset,

    // CPU interface
    input cpu_valid,
    input cpu_write,
    input [ADDR_WIDTH-1:0] cpu_addr,
    input [DATA_WIDTH-1:0] cpu_write_data,

    output reg [DATA_WIDTH-1:0] cpu_read_data,
    output reg cpu_ready,
    output reg cpu_hit,

    // L2 interface
    output reg l2_valid,
    output reg l2_write,
    output reg [ADDR_WIDTH-1:0] l2_addr,
    output reg [DATA_WIDTH-1:0] l2_write_data,

    input [DATA_WIDTH-1:0] l2_read_data,
    input l2_ready
);

    // --------------------------------------------------
    // Cache storage
    // --------------------------------------------------

    reg [14:0] tag [0:SETS-1][0:WAYS-1];
    reg valid [0:SETS-1][0:WAYS-1];

    // One 32-bit word per location.
    // 16-byte block = 4 words.
    reg [DATA_WIDTH-1:0] data [0:SETS-1][0:WAYS-1][0:3];

    // --------------------------------------------------
    // LRU
    // --------------------------------------------------

    reg lru_access_valid;
    reg [1:0] lru_access_way;
    wire [1:0] lru_way;

    lru_square_matrix l1_lru (
        .clk(clk),
        .reset(reset),
        .access_valid(lru_access_valid),
        .access_way(lru_access_way),
        .lru_way(lru_way)
    );

    // --------------------------------------------------
    // Address fields
    // --------------------------------------------------

    wire [3:0] offset = cpu_addr[3:0];
    wire [6:0] index = cpu_addr[10:4];
    wire [14:0] tag_value = cpu_addr[25:11];

    wire [1:0] word_offset = cpu_addr[3:2];

    reg [1:0] hit_way;
    reg hit_found;

    integer i;

    // --------------------------------------------------
    // Line fill (miss) state
    // --------------------------------------------------
    // A miss now fetches the WHOLE line from L2, one word
    // per cycle (fill_word = 0..3), instead of only the
    // single requested word. This fixes stale/garbage data
    // being left in the other words of a newly-allocated line.

    reg filling;
    reg [1:0] fill_word;

    wire [1:0] cur_fill_word = filling ? fill_word : 2'b00;

    // --------------------------------------------------
    // Search cache
    // --------------------------------------------------

    always @(*) begin

        hit_found = 1'b0;
        hit_way = 0;

        for (i = 0; i < WAYS; i = i + 1) begin
            if (valid[index][i] &&
                tag[index][i] == tag_value) begin

                hit_found = 1'b1;
                hit_way = i[1:0];

            end
        end

    end

    // --------------------------------------------------
    // Main cache operation
    // --------------------------------------------------

    always @(posedge clk or posedge reset) begin

        if (reset) begin

            cpu_ready <= 0;
            cpu_hit <= 0;
            cpu_read_data <= 0;

            l2_valid <= 0;
            l2_write <= 0;

            lru_access_valid <= 0;

            filling <= 1'b0;
            fill_word <= 2'b00;

            for (i = 0; i < SETS; i = i + 1) begin
                valid[i][0] <= 0;
                valid[i][1] <= 0;
                valid[i][2] <= 0;
                valid[i][3] <= 0;
            end

        end
        else begin

            cpu_ready <= 0;
            cpu_hit <= 0;
            l2_valid <= 0;
            lru_access_valid <= 0;

            if (cpu_valid) begin

                // -------------------------------
                // CACHE HIT
                // -------------------------------

                if (hit_found) begin

                    cpu_hit <= 1'b1;
                    cpu_ready <= 1'b1;

                    if (cpu_write) begin

                        data[index][hit_way][word_offset] <=
                            cpu_write_data;

                        // Send write to L2 through write path
                        l2_valid <= 1'b1;
                        l2_write <= 1'b1;
                        l2_addr <= cpu_addr;
                        l2_write_data <= cpu_write_data;

                    end
                    else begin

                        cpu_read_data <=
                            data[index][hit_way][word_offset];

                    end

                    lru_access_valid <= 1'b1;
                    lru_access_way <= hit_way;

                end

                // -------------------------------
                // CACHE MISS
                // -------------------------------

                else begin

                    filling <= 1'b1;

                    l2_valid <= 1'b1;
                    l2_write <= 1'b0;
                    l2_addr <= {cpu_addr[ADDR_WIDTH-1:4], cur_fill_word, 2'b00};

                    // Wait for L2
                    if (l2_ready) begin

                        // Fill this word of the line
                        tag[index][lru_way] <= tag_value;
                        data[index][lru_way][cur_fill_word] <= l2_read_data;

                        if (cur_fill_word == word_offset)
                            cpu_read_data <= l2_read_data;

                        if (cur_fill_word == 2'b11) begin

                            // Whole line is now valid
                            valid[index][lru_way] <= 1'b1;
                            filling <= 1'b0;

                            // Read miss: done now. Write miss: don't
                            // complete yet -- next cycle this address
                            // now HITS (valid+tag match), so the
                            // write-hit path above applies
                            // cpu_write_data and forwards it to L2
                            // (write-allocate), instead of the write
                            // being silently dropped.
                            if (!cpu_write) begin
                                cpu_ready <= 1'b1;
                                lru_access_valid <= 1'b1;
                                lru_access_way <= lru_way;
                            end

                        end
                        else begin
                            fill_word <= cur_fill_word + 1'b1;
                        end

                    end

                end
            end
        end
    end

endmodule
