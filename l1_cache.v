module l1_cache #(
    parameter ADDR_WIDTH = 26,
    parameter DATA_WIDTH = 32,

    parameter SETS = 128,
    parameter WAYS = 4,
    parameter BLOCK_BYTES = 16
)(
    input clk,
    input reset,

    input cpu_valid,
    input cpu_write,
    input [ADDR_WIDTH-1:0] cpu_addr,
    input [DATA_WIDTH-1:0] cpu_write_data,

    output reg [DATA_WIDTH-1:0] cpu_read_data,
    output reg cpu_ready,
    output reg cpu_hit,

    output reg l2_valid,
    output reg l2_write,
    output reg [ADDR_WIDTH-1:0] l2_addr,
    output reg [DATA_WIDTH-1:0] l2_write_data,

    input [DATA_WIDTH-1:0] l2_read_data,
    input l2_ready
);

    reg [14:0] tag [0:SETS-1][0:WAYS-1];
    reg valid [0:SETS-1][0:WAYS-1];

    reg [DATA_WIDTH-1:0] data [0:SETS-1][0:WAYS-1][0:3];

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

    // Address division

    wire [3:0] offset = cpu_addr[3:0];
    wire [6:0] index = cpu_addr[10:4];
    wire [14:0] tag_value = cpu_addr[25:11];

    wire [1:0] word_offset = cpu_addr[3:2];

    reg [1:0] hit_way;
    reg hit_found;

    integer i;

    // Line fill (miss) state

    reg filling;
    reg [1:0] fill_word;

    wire [1:0] cur_fill_word = filling ? fill_word : 2'b00;

    // Write buffer
    reg draining;
    reg buf_consume;

    wire buf_full;
    wire buf_consume_valid;
    wire [ADDR_WIDTH-1:0] buf_consume_addr;
    wire [DATA_WIDTH-1:0] buf_consume_data;

    wire hit_write_accept = cpu_valid && hit_found && cpu_write && !buf_full;

    write_buffer #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH)
    ) l1_wb (
        .clk(clk),
        .reset(reset),
        .write_valid(hit_write_accept),
        .write_addr(cpu_addr),
        .write_data(cpu_write_data),
        .full(buf_full),
        .consume(buf_consume),
        .consume_valid(buf_consume_valid),
        .consume_addr(buf_consume_addr),
        .consume_data(buf_consume_data)
    );

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

            draining <= 1'b0;
            buf_consume <= 1'b0;

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
            buf_consume <= 0;

            if (filling) begin

                l2_valid <= 1'b1;
                l2_write <= 1'b0;
                l2_addr <= {cpu_addr[ADDR_WIDTH-1:4], cur_fill_word, 2'b00};

                if (l2_ready) begin

                    tag[index][lru_way] <= tag_value;
                    data[index][lru_way][cur_fill_word] <= l2_read_data;

                    if (cur_fill_word == word_offset)
                        cpu_read_data <= l2_read_data;

                    if (cur_fill_word == 2'b11) begin

                        valid[index][lru_way] <= 1'b1;
                        filling <= 1'b0;

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

            else if (draining) begin

                l2_valid <= 1'b1;
                l2_write <= 1'b1;
                l2_addr <= buf_consume_addr;
                l2_write_data <= buf_consume_data;

                if (l2_ready) begin
                    draining <= 1'b0;
                    buf_consume <= 1'b1;
                end

            end

            else if (cpu_valid && hit_found) begin

                // cache hit

                if (cpu_write && buf_full) begin
                    // stall
                end
                else begin

                    cpu_hit <= 1'b1;
                    cpu_ready <= 1'b1;

                    if (cpu_write) begin

                        data[index][hit_way][word_offset] <=
                            cpu_write_data;

                    end
                    else begin

                        cpu_read_data <=
                            data[index][hit_way][word_offset];

                    end

                    lru_access_valid <= 1'b1;
                    lru_access_way <= hit_way;

                end

            end

            else if (buf_consume_valid) begin

                draining <= 1'b1;

                l2_valid <= 1'b1;
                l2_write <= 1'b1;
                l2_addr <= buf_consume_addr;
                l2_write_data <= buf_consume_data;

                if (l2_ready) begin
                    draining <= 1'b0;
                    buf_consume <= 1'b1;
                end

            end

            else if (cpu_valid && !hit_found) begin

                filling <= 1'b1;

                l2_valid <= 1'b1;
                l2_write <= 1'b0;
                l2_addr <= {cpu_addr[ADDR_WIDTH-1:4], cur_fill_word, 2'b00};

                if (l2_ready) begin

                    tag[index][lru_way] <= tag_value;
                    data[index][lru_way][cur_fill_word] <= l2_read_data;

                    if (cur_fill_word == word_offset)
                        cpu_read_data <= l2_read_data;

                    if (cur_fill_word == 2'b11) begin

                        valid[index][lru_way] <= 1'b1;
                        filling <= 1'b0;

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

endmodule
