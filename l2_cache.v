module l2_cache #(
    parameter ADDR_WIDTH = 26,
    parameter DATA_WIDTH = 32,

    parameter SETS = 128,
    parameter WAYS = 8,
    parameter BLOCK_BYTES = 32
)(
    input clk,
    input reset,

    // L1 interface
    input upper_valid,
    input upper_write,
    input [ADDR_WIDTH-1:0] upper_addr,
    input [DATA_WIDTH-1:0] upper_write_data,

    output reg [DATA_WIDTH-1:0] upper_read_data,
    output reg upper_ready,

    // Main memory interface
    output reg memory_valid,
    output reg memory_write,
    output reg [ADDR_WIDTH-1:0] memory_addr,
    output reg [DATA_WIDTH-1:0] memory_write_data,

    input [DATA_WIDTH-1:0] memory_read_data,
    input memory_ready
);

    // Cache storage

    reg [13:0] tag [0:SETS-1][0:WAYS-1];
    reg valid [0:SETS-1][0:WAYS-1];
    reg dirty [0:SETS-1][0:WAYS-1];

    // 32 byte block = 8 words
    reg [DATA_WIDTH-1:0] data [0:SETS-1][0:WAYS-1][0:7];

    // LRU Counter

    reg lru_access_valid;
    reg [2:0] lru_access_way;

    wire [2:0] lru_way;

    lru_counter l2_lru (
        .clk(clk),
        .reset(reset),
        .access_valid(lru_access_valid),
        .access_way(lru_access_way),
        .lru_way(lru_way)
    );

    // Address divisin

    wire [4:0] offset = upper_addr[4:0];
    wire [6:0] index = upper_addr[11:5];
    wire [13:0] tag_value = upper_addr[25:12];

    wire [2:0] word_offset = upper_addr[4:2];

    reg hit_found;
    reg [2:0] hit_way;

    integer i;

    // Miss state: dirty-victim writeback + line fill

    reg evicting;
    reg filling;
    reg [2:0] fill_word;

    wire need_writeback = dirty[index][lru_way];
    wire in_evict = evicting || ((!evicting && !filling) && need_writeback);
    wire [2:0] cur_beat = (evicting || filling) ? fill_word : 3'b000;

  // L2 search

    always @(*) begin

        hit_found = 1'b0;
        hit_way = 0;

        for (i = 0; i < WAYS; i = i + 1) begin

            if (valid[index][i] &&
                tag[index][i] == tag_value) begin

                hit_found = 1'b1;
                hit_way = i[2:0];

            end

        end

    end

    always @(posedge clk or posedge reset) begin

        if (reset) begin

            upper_ready <= 0;
            upper_read_data <= 0;

            memory_valid <= 0;
            memory_write <= 0;

            lru_access_valid <= 0;

            evicting <= 1'b0;
            filling <= 1'b0;
            fill_word <= 3'b000;

            for (i = 0; i < SETS; i = i + 1) begin

                valid[i][0] <= 0;
                valid[i][1] <= 0;
                valid[i][2] <= 0;
                valid[i][3] <= 0;
                valid[i][4] <= 0;
                valid[i][5] <= 0;
                valid[i][6] <= 0;
                valid[i][7] <= 0;

                dirty[i][0] <= 0;
                dirty[i][1] <= 0;
                dirty[i][2] <= 0;
                dirty[i][3] <= 0;
                dirty[i][4] <= 0;
                dirty[i][5] <= 0;
                dirty[i][6] <= 0;
                dirty[i][7] <= 0;

            end

        end
        else begin

            upper_ready <= 0;
            memory_valid <= 0;
            lru_access_valid <= 0;

            if (upper_valid) begin

                //Hit

                if (hit_found) begin

                    upper_ready <= 1'b1;

                    if (upper_write) begin

                        data[index][hit_way][word_offset] <=
                            upper_write_data;
                            
                        dirty[index][hit_way] <= 1'b1;

                    end
                    else begin

                        upper_read_data <=
                            data[index][hit_way][word_offset];

                    end

                    lru_access_valid <= 1'b1;
                    lru_access_way <= hit_way;

                end

                //L2 Miss

                else begin

                    if (in_evict) begin

                        memory_valid <= 1'b1;
                        memory_write <= 1'b1;
                        memory_addr <= {tag[index][lru_way], index, cur_beat, 2'b00};
                        memory_write_data <= data[index][lru_way][cur_beat];

                        if (memory_ready) begin
                            if (cur_beat == 3'd7) begin
                                evicting <= 1'b0;
                                filling <= 1'b1;
                                fill_word <= 3'd0;
                            end
                            else begin
                                evicting <= 1'b1;
                                fill_word <= cur_beat + 1'b1;
                            end
                        end
                        else begin
                            evicting <= 1'b1;
                        end

                    end
                    else begin

                        //Fetch from MM
                        filling <= 1'b1;

                        memory_valid <= 1'b1;
                        memory_write <= 1'b0;
                        memory_addr <= {tag_value, index, cur_beat, 2'b00};

                        if (memory_ready) begin

                            tag[index][lru_way] <= tag_value;
                            data[index][lru_way][cur_beat] <= memory_read_data;

                            if (cur_beat == word_offset)
                                upper_read_data <= memory_read_data;

                            if (cur_beat == 3'd7) begin

                                valid[index][lru_way] <= 1'b1;
                                dirty[index][lru_way] <= 1'b0;
                                filling <= 1'b0;

                                if (!upper_write) begin
                                    upper_ready <= 1'b1;
                                    lru_access_valid <= 1'b1;
                                    lru_access_way <= lru_way;
                                end

                            end
                            else begin
                                fill_word <= cur_beat + 1'b1;
                            end

                        end

                    end

                end

            end
        end
    end

endmodule
