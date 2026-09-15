`timescale 1ns / 1ps

module disk_memory #(
    parameter PAGE_SIZE_WORDS = 256
)(
    input wire        clk,
    input wire        reset,

    input wire        page_read,
    input wire [14:0] page_number,
    input wire        page_data_ready,

    output reg [31:0] page_data,
    output reg        page_data_valid,
    output reg        page_done,

    input wire        page_write_start,
    input wire [14:0] page_write_number,
    input wire [31:0] page_write_data,
    input wire        page_write_valid,
    output reg        page_write_ready,
    output reg        page_write_done,

    output reg        busy
);

    reg [31:0] disk_memory [0:32767][0:255];

    reg [7:0] word_counter;
    reg [14:0] active_page;

    localparam IDLE       = 2'd0;
    localparam READ       = 2'd1;
    localparam WRITE      = 2'd2;

    reg [1:0] state;

    always @(posedge clk) begin
        if (reset) begin
            state <= IDLE;

            word_counter <= 8'd0;
            active_page <= 15'd0;

            page_data <= 32'd0;
            page_data_valid <= 1'b0;
            page_done <= 1'b0;

            page_write_ready <= 1'b0;
            page_write_done <= 1'b0;

            busy <= 1'b0;
        end
        else begin
            page_data_valid <= 1'b0;
            page_done <= 1'b0;
            page_write_ready <= 1'b0;
            page_write_done <= 1'b0;

            case (state)

                IDLE: begin
                    busy <= 1'b0;

                    if (page_read) begin
                        active_page <= page_number;
                        word_counter <= 8'd0;
                        busy <= 1'b1;
                        state <= READ;
                    end
                    else if (page_write_start) begin
                        active_page <= page_write_number;
                        word_counter <= 8'd0;
                        busy <= 1'b1;
                        state <= WRITE;
                    end
                end

                READ: begin
                    busy <= 1'b1;

                    page_data <= disk_memory[active_page][word_counter];
                    page_data_valid <= 1'b1;

                    if (page_data_ready) begin
                        if (word_counter == PAGE_SIZE_WORDS - 1) begin
                            page_done <= 1'b1;
                            word_counter <= 8'd0;
                            busy <= 1'b0;
                            state <= IDLE;
                        end
                        else begin
                            word_counter <= word_counter + 1'b1;
                        end
                    end
                end

                WRITE: begin
                    busy <= 1'b1;
                    page_write_ready <= 1'b1;

                    if (page_write_valid) begin
                        disk_memory[active_page][word_counter] <= page_write_data;

                        if (word_counter == PAGE_SIZE_WORDS - 1) begin
                            page_write_done <= 1'b1;
                            word_counter <= 8'd0;
                            busy <= 1'b0;
                            state <= IDLE;
                        end
                        else begin
                            word_counter <= word_counter + 1'b1;
                        end
                    end
                end

                default: begin
                    state <= IDLE;
                    busy <= 1'b0;
                end

            endcase
        end
    end

endmodule