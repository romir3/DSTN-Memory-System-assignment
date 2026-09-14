module write_buffer #(
    parameter ENTRIES = 4,
    parameter ADDR_WIDTH = 26,
    parameter DATA_WIDTH = 32
)(
    input clk,
    input reset,

    // Add a write to the buffer
    input write_valid,
    input [ADDR_WIDTH-1:0] write_addr,
    input [DATA_WIDTH-1:0] write_data,

    output full,

    // Send oldest buffered write to L2
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

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            count <= 0;

            for (i = 0; i < ENTRIES; i = i + 1) begin
                address[i] <= 0;
                data[i] <= 0;
            end
        end
        else begin

            // Add new write
            if (write_valid && !full) begin
                address[count] <= write_addr;
                data[count] <= write_data;
                count <= count + 1;
            end

            // Remove oldest write
            if (consume && count != 0) begin

                for (i = 0; i < ENTRIES-1; i = i + 1) begin
                    address[i] <= address[i+1];
                    data[i] <= data[i+1];
                end

                count <= count - 1;
            end
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