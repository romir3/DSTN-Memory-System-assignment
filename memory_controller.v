`timescale 1ns / 1ps

module memory_controller #(
    parameter ADDR_WIDTH = 26
)(
    input wire                  clk,
    input wire                  reset,

    input wire                  l2_write_start,
    input wire [ADDR_WIDTH-1:0] l2_write_addr,
    input wire [31:0]           l2_write_data,
    input wire                  l2_write_valid,
    output reg                  l2_write_ready,
    output reg                  l2_write_done,

    input wire                  l2_read_start,
    input wire [ADDR_WIDTH-1:0] l2_read_addr,
    output reg [31:0]           l2_read_data,
    output reg [2:0]            l2_read_index,
    output reg                  l2_read_valid,
    input wire                  l2_read_ready,
    output reg                  l2_read_done,

    input wire                  page_load_start,
    input wire [15:0]           page_load_frame,
    input wire [14:0]           page_load_number,
    output reg                  page_load_done,

    input wire                  page_writeback_start,
    input wire [15:0]            page_writeback_frame,
    input wire [14:0]            page_writeback_number,
    output reg                  page_writeback_done,

    output reg                  disk_page_read,
    output reg [14:0]            disk_page_number,
    input wire [31:0]            disk_page_data,
    input wire                   disk_page_data_valid,
    output reg                   disk_page_data_ready,

    output reg                  disk_page_write,
    output reg [14:0]            disk_write_page_number,
    output reg [31:0]            disk_write_data,
    output reg                   disk_write_valid,
    input wire                   disk_write_ready,

    output reg                  memory_valid,
    output reg                  memory_write,
    output reg [ADDR_WIDTH-1:0] memory_addr,
    output reg [31:0]            memory_write_data,
    input wire [31:0]             memory_read_data,
    input wire                    memory_ready,

    output reg                  access_valid,
    output reg [15:0]            access_frame,
    output reg                  dirty_update_valid,
    output reg [15:0]            dirty_frame
);

    localparam IDLE                  = 4'd0;
    localparam L2_READ_REQ           = 4'd1;
    localparam L2_READ_WAIT          = 4'd2;
    localparam L2_READ_SEND          = 4'd3;
    localparam L2_WRITE_WAIT         = 4'd4;
    localparam L2_WRITE_REQ          = 4'd5;
    localparam L2_WRITE_WAITMEM      = 4'd6;
    localparam PAGE_LOAD_START       = 4'd7;
    localparam PAGE_LOAD_WAIT        = 4'd8;
    localparam PAGE_LOAD_WRITE       = 4'd9;
    localparam PAGE_LOAD_WAITMEM     = 4'd10;
    localparam PAGE_WRITEBACK_START  = 4'd11;
    localparam PAGE_WRITEBACK_READ   = 4'd12;
    localparam PAGE_WRITEBACK_WAIT   = 4'd13;
    localparam PAGE_WRITEBACK_SEND   = 4'd14;

    reg [3:0] state;

    reg [ADDR_WIDTH-1:0] l2_read_base_addr;
    reg [2:0]            l2_read_count;
    reg [31:0]           l2_read_word;

    reg [ADDR_WIDTH-1:0] l2_write_current_addr;
    reg [31:0]           l2_write_word;
    reg [2:0]            l2_write_count;

    reg [15:0] page_load_frame_reg;
    reg [14:0] page_load_number_reg;
    reg [7:0]  page_load_count;
    reg [31:0] page_load_word;

    reg [15:0] page_writeback_frame_reg;
    reg [14:0] page_writeback_number_reg;
    reg [7:0]  page_writeback_count;
    reg [31:0] page_writeback_word;

    always @(*) begin
        l2_write_ready = 1'b0;

        l2_read_data = l2_read_word;
        l2_read_index = l2_read_count;
        l2_read_valid = 1'b0;

        disk_page_read = 1'b0;
        disk_page_number = page_load_number_reg;
        disk_page_data_ready = 1'b0;

        disk_page_write = 1'b0;
        disk_write_page_number = page_writeback_number_reg;
        disk_write_data = page_writeback_word;
        disk_write_valid = 1'b0;

        memory_valid = 1'b0;
        memory_write = 1'b0;
        memory_addr = {ADDR_WIDTH{1'b0}};
        memory_write_data = 32'd0;

        access_valid = 1'b0;
        access_frame = 16'd0;
        dirty_update_valid = 1'b0;
        dirty_frame = 16'd0;

        case (state)

            L2_READ_REQ: begin
                memory_valid = 1'b1;
                memory_write = 1'b0;
                memory_addr = l2_read_base_addr +
                              (l2_read_count * 26'd4);
                access_valid = 1'b1;
                access_frame = memory_addr[25:10];
            end

            L2_READ_SEND: begin
                l2_read_valid = 1'b1;
                l2_read_data = l2_read_word;
                l2_read_index = l2_read_count;
            end

            L2_WRITE_WAIT: begin
                l2_write_ready = 1'b1;
            end

            L2_WRITE_REQ: begin
                memory_valid = 1'b1;
                memory_write = 1'b1;
                memory_addr = l2_write_current_addr;
                memory_write_data = l2_write_word;

                access_valid = 1'b1;
                access_frame = memory_addr[25:10];

                dirty_update_valid = 1'b1;
                dirty_frame = memory_addr[25:10];
            end

            PAGE_LOAD_START: begin
                disk_page_read = 1'b1;
                disk_page_number = page_load_number_reg;
            end

            PAGE_LOAD_WAIT: begin
                disk_page_data_ready = 1'b1;
            end

            PAGE_LOAD_WRITE: begin
                memory_valid = 1'b1;
                memory_write = 1'b1;
                memory_addr = {page_load_frame_reg, 10'b0} +
                              (page_load_count * 26'd4);
                memory_write_data = page_load_word;
            end

            PAGE_WRITEBACK_START: begin
                disk_page_write = 1'b1;
                disk_write_page_number = page_writeback_number_reg;
            end

            PAGE_WRITEBACK_READ: begin
                memory_valid = 1'b1;
                memory_write = 1'b0;
                memory_addr = {page_writeback_frame_reg, 10'b0} +
                              (page_writeback_count * 26'd4);
            end

            PAGE_WRITEBACK_SEND: begin
                disk_write_page_number = page_writeback_number_reg;
                disk_write_data = page_writeback_word;
                disk_write_valid = 1'b1;
            end

            default: begin
            end

        endcase
    end

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            state <= IDLE;

            l2_read_base_addr <= 26'd0;
            l2_read_count <= 3'd0;
            l2_read_word <= 32'd0;

            l2_write_current_addr <= 26'd0;
            l2_write_word <= 32'd0;
            l2_write_count <= 3'd0;

            page_load_frame_reg <= 16'd0;
            page_load_number_reg <= 15'd0;
            page_load_count <= 8'd0;
            page_load_word <= 32'd0;

            page_writeback_frame_reg <= 16'd0;
            page_writeback_number_reg <= 15'd0;
            page_writeback_count <= 8'd0;
            page_writeback_word <= 32'd0;

            l2_read_done <= 1'b0;
            l2_write_done <= 1'b0;
            page_load_done <= 1'b0;
            page_writeback_done <= 1'b0;
        end
        else begin
            l2_read_done <= 1'b0;
            l2_write_done <= 1'b0;
            page_load_done <= 1'b0;
            page_writeback_done <= 1'b0;

            case (state)

                IDLE: begin
                    if (page_load_start) begin
                        page_load_frame_reg <= page_load_frame;
                        page_load_number_reg <= page_load_number;
                        page_load_count <= 8'd0;
                        state <= PAGE_LOAD_START;
                    end
                    else if (page_writeback_start) begin
                        page_writeback_frame_reg <= page_writeback_frame;
                        page_writeback_number_reg <= page_writeback_number;
                        page_writeback_count <= 8'd0;
                        state <= PAGE_WRITEBACK_START;
                    end
                    else if (l2_read_start) begin
                        l2_read_base_addr <=
                            {l2_read_addr[ADDR_WIDTH-1:5], 5'b0};
                        l2_read_count <= 3'd0;
                        state <= L2_READ_REQ;
                    end
                    else if (l2_write_start) begin
                        l2_write_current_addr <=
                            {l2_write_addr[ADDR_WIDTH-1:5], 5'b0};
                        l2_write_count <= 3'd0;
                        state <= L2_WRITE_WAIT;
                    end
                end

                L2_READ_REQ: begin
                    state <= L2_READ_WAIT;
                end

                L2_READ_WAIT: begin
                    if (memory_ready) begin
                        l2_read_word <= memory_read_data;
                        state <= L2_READ_SEND;
                    end
                end

                L2_READ_SEND: begin
                    if (l2_read_ready) begin
                        if (l2_read_count == 3'd7) begin
                            l2_read_done <= 1'b1;
                            state <= IDLE;
                        end
                        else begin
                            l2_read_count <= l2_read_count + 3'd1;
                            state <= L2_READ_REQ;
                        end
                    end
                end

                L2_WRITE_WAIT: begin
                    if (l2_write_valid && l2_write_ready) begin
                        l2_write_word <= l2_write_data;
                        state <= L2_WRITE_REQ;
                    end
                end

                L2_WRITE_REQ: begin
                    state <= L2_WRITE_WAITMEM;
                end

                L2_WRITE_WAITMEM: begin
                    if (memory_ready) begin
                        if (l2_write_count == 3'd7) begin
                            l2_write_done <= 1'b1;
                            state <= IDLE;
                        end
                        else begin
                            l2_write_count <= l2_write_count + 3'd1;
                            l2_write_current_addr <=
                                l2_write_current_addr + 26'd4;
                            state <= L2_WRITE_WAIT;
                        end
                    end
                end

                PAGE_LOAD_START: begin
                    state <= PAGE_LOAD_WAIT;
                end

                PAGE_LOAD_WAIT: begin
                    if (disk_page_data_valid &&
                        disk_page_data_ready) begin
                        page_load_word <= disk_page_data;
                        state <= PAGE_LOAD_WRITE;
                    end
                end

                PAGE_LOAD_WRITE: begin
                    state <= PAGE_LOAD_WAITMEM;
                end

                PAGE_LOAD_WAITMEM: begin
                    if (memory_ready) begin
                        if (page_load_count == 8'd255) begin
                            page_load_done <= 1'b1;
                            state <= IDLE;
                        end
                        else begin
                            page_load_count <= page_load_count + 8'd1;
                            state <= PAGE_LOAD_WAIT;
                        end
                    end
                end

                PAGE_WRITEBACK_START: begin
                    state <= PAGE_WRITEBACK_READ;
                end

                PAGE_WRITEBACK_READ: begin
                    state <= PAGE_WRITEBACK_WAIT;
                end

                PAGE_WRITEBACK_WAIT: begin
                    if (memory_ready) begin
                        page_writeback_word <= memory_read_data;
                        state <= PAGE_WRITEBACK_SEND;
                    end
                end

                PAGE_WRITEBACK_SEND: begin
                    if (disk_write_valid && disk_write_ready) begin
                        if (page_writeback_count == 8'd255) begin
                            page_writeback_done <= 1'b1;
                            state <= IDLE;
                        end
                        else begin
                            page_writeback_count <=
                                page_writeback_count + 8'd1;
                            state <= PAGE_WRITEBACK_READ;
                        end
                    end
                end

                default: begin
                    state <= IDLE;
                end

            endcase
        end
    end

endmodule