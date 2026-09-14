module lru_square_matrix #(
    parameter WAYS = 4
)(
    input clk,
    input reset,

    // Way which was accessed recently
    input access_valid,
    input [1:0] access_way,

    // Way selected for replacement
    output reg [1:0] lru_way
);

    reg matrix [0:WAYS-1][0:WAYS-1];

    integer i, j;

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            for (i = 0; i < WAYS; i = i + 1) begin
                for (j = 0; j < WAYS; j = j + 1) begin
                    matrix[i][j] <= 1'b0;
                end
            end
        end
        else if (access_valid) begin

            // Accessed way becomes newer than every other way
            for (j = 0; j < WAYS; j = j + 1) begin
                if (j != access_way) begin
                    matrix[access_way][j] <= 1'b1;
                    matrix[j][access_way] <= 1'b0;
                end
            end

            matrix[access_way][access_way] <= 1'b0;
        end
    end

    // A true LRU way has 0 in every column of its row
    always @(*) begin
        lru_way = 0;

        for (i = 0; i < WAYS; i = i + 1) begin
            if ((matrix[i][0] == 0) &&
                (matrix[i][1] == 0) &&
                (matrix[i][2] == 0) &&
                (matrix[i][3] == 0)) begin
                lru_way = i[1:0];
            end
        end
    end

endmodule