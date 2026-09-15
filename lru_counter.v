module lru_counter #(
    parameter WAYS = 8
)(
    input clk,
    input reset,

    input access_valid,
    input [2:0] access_way,

    output reg [2:0] lru_way
);

    reg [2:0] counter [0:WAYS-1];

    integer i;

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            for (i = 0; i < WAYS; i = i + 1)
                counter[i] <= i;
        end
        else if (access_valid) begin

            for (i = 0; i < WAYS; i = i + 1) begin

                if (i == access_way)
                    counter[i] <= 0;

                else if (counter[i] < counter[access_way])
                    counter[i] <= counter[i] + 1;

            end
        end
    end

    always @(*) begin
        lru_way = 0;

        for (i = 1; i < WAYS; i = i + 1) begin
            if (counter[i] > counter[lru_way])
                lru_way = i[2:0];
        end
    end

endmodule