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
    // Write buffer
    // --------------------------------------------------
    // Write hits are pushed here instead of being pulsed onto
    // the L2 bus directly, so a write is never lost just because
    // L2 wasn't ready the exact cycle of the hit. The buffer is
    // drained to L2 in the background (see the main always block)
    // whenever the bus isn't busy with a line fill.

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

            // The L2 bus is shared between line fills and write-buffer
            // drains, so only one of the branches below runs per cycle.
            // An in-progress fill always wins (it must not be
            // interrupted mid-burst); a drain-in-progress is next;
            // then a CPU hit (never stalled by a drain); then starting
            // a new drain if the buffer has something to send; and
            // finally starting a new miss fill.

            if (filling) begin

                // -------------------------------
                // CONTINUE LINE FILL
                // -------------------------------

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

                        // Read miss: done now. Write miss: don't
                        // complete yet -- next cycle this address
                        // now HITS (valid+tag match), so the
                        // write-hit path below applies
                        // cpu_write_data (write-allocate) instead
                        // of the write being silently dropped.
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

                // -------------------------------
                // CONTINUE WRITE-BUFFER DRAIN
                // -------------------------------

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

                // -------------------------------
                // CACHE HIT
                // -------------------------------

                if (cpu_write && buf_full) begin
                    // Write buffer is full -- stall this write and
                    // retry next cycle instead of dropping it.
                end
                else begin

                    cpu_hit <= 1'b1;
                    cpu_ready <= 1'b1;

                    if (cpu_write) begin

                        data[index][hit_way][word_offset] <=
                            cpu_write_data;

                        // Pushed into the write buffer via
                        // hit_write_accept above; drained to L2 in
                        // the background instead of sent directly.

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

                // -------------------------------
                // START WRITE-BUFFER DRAIN
                // -------------------------------

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

                // -------------------------------
                // START LINE FILL (CACHE MISS)
                // -------------------------------

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
