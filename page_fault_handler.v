`timescale 1ns / 1ps

module page_fault_handler #(
    parameter PID_WIDTH = 8
)(
    input wire                  clk,
    input wire                  reset,

    input wire                  page_fault,
    input wire [14:0]           fault_page,
    input wire [PID_WIDTH-1:0]  fault_pid,

    output reg                  victim_request,

    input wire                  victim_valid,
    input wire [15:0]           victim_frame,
    input wire [PID_WIDTH-1:0]  victim_pid,
    input wire [14:0]           victim_vpn,
    input wire                  victim_dirty,
    input wire                  victim_is_free,
    input wire                  no_victim,

    output reg                  page_writeback_start,
    output reg [15:0]           page_writeback_frame,
    output reg [PID_WIDTH-1:0]  page_writeback_pid,
    output reg [14:0]           page_writeback_number,
    input wire                  page_writeback_done,

    output reg                  page_load_start,
    output reg [15:0]           page_load_frame,
    output reg [14:0]           page_load_number,
    input wire                  page_load_done,

    output reg                  frame_release,
    output reg [15:0]           release_frame,

    output reg                  frame_allocate,
    output reg [15:0]           allocate_frame,
    output reg [PID_WIDTH-1:0]  allocate_pid,

    output reg                  page_table_invalidate,
    output reg [PID_WIDTH-1:0]  invalidate_pid,
    output reg [14:0]           invalidate_vpn,

    output reg                  page_table_update,
    output reg [PID_WIDTH-1:0]  update_pid,
    output reg [14:0]           update_vpn,
    output reg [15:0]           update_frame,

    output reg                  fault_done,
    output reg                  fault_stall,
    output reg                  busy
);

    localparam IDLE           = 4'd0;
    localparam REQUEST_VICTIM = 4'd1;
    localparam WAIT_VICTIM    = 4'd2;
    localparam WRITEBACK      = 4'd3;
    localparam RELEASE        = 4'd4;
    localparam LOAD_PAGE      = 4'd5;
    localparam UPDATE         = 4'd6;
    localparam FINISH         = 4'd7;
    localparam STALL          = 4'd8;

    reg [3:0] state;

    reg [14:0] fault_page_reg;
    reg [PID_WIDTH-1:0] fault_pid_reg;

    reg [15:0] selected_frame;
    reg [PID_WIDTH-1:0] selected_pid;
    reg [14:0] selected_vpn;
    reg selected_dirty;
    reg selected_is_free;

    always @(posedge clk) begin
        if (reset) begin
            state <= IDLE;

            fault_page_reg <= 15'd0;
            fault_pid_reg <= {PID_WIDTH{1'b0}};

            selected_frame <= 16'd0;
            selected_pid <= {PID_WIDTH{1'b0}};
            selected_vpn <= 15'd0;
            selected_dirty <= 1'b0;
            selected_is_free <= 1'b0;

            victim_request <= 1'b0;

            page_writeback_start <= 1'b0;
            page_writeback_frame <= 16'd0;
            page_writeback_pid <= {PID_WIDTH{1'b0}};
            page_writeback_number <= 15'd0;

            page_load_start <= 1'b0;
            page_load_frame <= 16'd0;
            page_load_number <= 15'd0;

            frame_release <= 1'b0;
            release_frame <= 16'd0;

            frame_allocate <= 1'b0;
            allocate_frame <= 16'd0;
            allocate_pid <= {PID_WIDTH{1'b0}};

            page_table_invalidate <= 1'b0;
            invalidate_pid <= {PID_WIDTH{1'b0}};
            invalidate_vpn <= 15'd0;

            page_table_update <= 1'b0;
            update_pid <= {PID_WIDTH{1'b0}};
            update_vpn <= 15'd0;
            update_frame <= 16'd0;

            fault_done <= 1'b0;
            fault_stall <= 1'b0;
            busy <= 1'b0;
        end
        else begin
            victim_request <= 1'b0;
            page_writeback_start <= 1'b0;
            page_load_start <= 1'b0;
            frame_release <= 1'b0;
            frame_allocate <= 1'b0;
            page_table_invalidate <= 1'b0;
            page_table_update <= 1'b0;
            fault_done <= 1'b0;
            fault_stall <= 1'b0;

            case (state)

                IDLE: begin
                    busy <= 1'b0;

                    if (page_fault) begin
                        fault_page_reg <= fault_page;
                        fault_pid_reg <= fault_pid;

                        busy <= 1'b1;
                        state <= REQUEST_VICTIM;
                    end
                end

                REQUEST_VICTIM: begin
                    busy <= 1'b1;
                    victim_request <= 1'b1;

                    state <= WAIT_VICTIM;
                end

                WAIT_VICTIM: begin
                    busy <= 1'b1;

                    if (no_victim) begin
                        state <= STALL;
                    end
                    else if (victim_valid) begin
                        selected_frame <= victim_frame;
                        selected_pid <= victim_pid;
                        selected_vpn <= victim_vpn;
                        selected_dirty <= victim_dirty;
                        selected_is_free <= victim_is_free;

                        if (victim_is_free) begin
                            state <= LOAD_PAGE;
                        end
                        else if (victim_dirty) begin
                            page_writeback_frame <= victim_frame;
                            page_writeback_pid <= victim_pid;
                            page_writeback_number <= victim_vpn;

                            state <= WRITEBACK;
                        end
                        else begin
                            state <= RELEASE;
                        end
                    end
                end

                WRITEBACK: begin
                    busy <= 1'b1;
                    page_writeback_start <= 1'b1;

                    if (page_writeback_done) begin
                        state <= RELEASE;
                    end
                end

                RELEASE: begin
                    busy <= 1'b1;

                    frame_release <= 1'b1;
                    release_frame <= selected_frame;

                    page_table_invalidate <= 1'b1;
                    invalidate_pid <= selected_pid;
                    invalidate_vpn <= selected_vpn;

                    state <= LOAD_PAGE;
                end

                LOAD_PAGE: begin
                    busy <= 1'b1;

                    page_load_start <= 1'b1;
                    page_load_frame <= selected_frame;
                    page_load_number <= fault_page_reg;

                    if (page_load_done) begin
                        state <= UPDATE;
                    end
                end

                UPDATE: begin
                    busy <= 1'b1;

                    frame_allocate <= 1'b1;
                    allocate_frame <= selected_frame;
                    allocate_pid <= fault_pid_reg;

                    page_table_update <= 1'b1;
                    update_pid <= fault_pid_reg;
                    update_vpn <= fault_page_reg;
                    update_frame <= selected_frame;

                    state <= FINISH;
                end

                FINISH: begin
                    busy <= 1'b0;
                    fault_done <= 1'b1;

                    state <= IDLE;
                end

                STALL: begin
                    busy <= 1'b1;
                    fault_stall <= 1'b1;

                    if (!page_fault) begin
                        busy <= 1'b0;
                        state <= IDLE;
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