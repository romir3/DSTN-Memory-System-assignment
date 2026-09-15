`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 15.09.2026 11:03:11
// Design Name: 
// Module Name: disk_memory
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module disk_memory #(
    parameter PAGE_SIZE_WORDS = 256
)(
    input  wire        clk,
    input  wire        reset,

    input  wire        page_read,
    input  wire [14:0] page_number,

    output reg [31:0]  page_data,
    output reg         page_data_valid,
    output reg         page_done,
    output reg         busy
);

 reg [7:0] word_counter;

    // Page currently being serviced
    reg [14:0] active_page;

    localparam IDLE = 1'b0;
    localparam READ = 1'b1;

    reg state;

    always @(posedge clk) begin
        if (reset) begin
            state           <= IDLE;
            word_counter    <= 8'd0;
            active_page     <= 15'd0;

            page_data       <= 32'd0;
            page_data_valid <= 1'b0;
            page_done       <= 1'b0;
            busy            <= 1'b0;
        end
        else begin
            // Default: these are pulse signals
            page_data_valid <= 1'b0;
            page_done       <= 1'b0;

            case (state)

                // ---------------------------------------------
                // Disk is idle and waiting for a page request
                // ---------------------------------------------
                IDLE: begin
                    busy <= 1'b0;

                    if (page_read) begin
                        active_page  <= page_number;
                        word_counter <= 8'd0;
                        busy         <= 1'b1;
                        state        <= READ;
                    end
                end

                // ---------------------------------------------
                // Stream one 32-bit word every cycle
                // ---------------------------------------------
                READ: begin
                    busy            <= 1'b1;
                    page_data_valid <= 1'b1;

                    // Deterministic test data
                    page_data <= {
                        active_page,
                        1'b0,
                        word_counter,
                        8'b0
                    };

                    if (word_counter == PAGE_SIZE_WORDS - 1) begin
                        page_done    <= 1'b1;
                        busy         <= 1'b0;
                        word_counter <= 8'd0;
                        state        <= IDLE;
                    end
                    else begin
                        word_counter <= word_counter + 1'b1;
                    end
                end

                default: begin
                    state <= IDLE;
                    busy  <= 1'b0;
                end

            endcase
        end
    end

endmodule
