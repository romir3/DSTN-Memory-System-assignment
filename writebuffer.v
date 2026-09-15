module write_buffer #(
    parameter ENTRIES = 4,
    parameter ADDR_WIDTH = 26,
    parameter DATA_WIDTH = 32
)(
    input clk,
    input reset,

    input write_valid,
    input [ADDR_WIDTH-1:0] write_addr,
    input [DATA_WIDTH-1:0] write_data,

    output full,

    input consume,
    output reg consume_valid,
    output reg [ADDR_WIDTH-1:0] consume_addr,
    output reg [DATA_WIDTH-1:0] consume_data
);

    reg [ADDR_WIDTH-1:0] address [0:ENTRIES-1];
    reg [DATA_WIDTH-1:0] data [0:ENTRIES-1];

    reg [2:0] count;

    integer i;

    assign full = (count == ENTRIES);

    wire [2:0] write_index = (consume && count != 0) ? count - 1 : count;

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            count <= 0;

            for (i = 0; i < ENTRIES; i = i + 1) begin
                address[i] <= 0;
                data[i] <= 0;
            end
        end
        else begin

            if (consume && count != 0) begin

                for (i = 0; i < ENTRIES-1; i = i + 1) begin
                    address[i] <= address[i+1];
                    data[i] <= data[i+1];
                end

            end

            if (write_valid && !full) begin
                address[write_index] <= write_addr;
                data[write_index] <= write_data;
            end

            if (write_valid && !full && consume && count != 0)
                count <= count;
            else if (write_valid && !full)
                count <= count + 1;
            else if (consume && count != 0)
                count <= count - 1;

        end
    end

    always @(*) begin
        if (count != 0) begin
            consume_valid = 1'b1;
            consume_addr = address[0];
            consume_data = data[0];
        end
        else begin
            consume_valid = 1'b0;
            consume_addr = 0;
            consume_data = 0;
        end
    end

endmodule
