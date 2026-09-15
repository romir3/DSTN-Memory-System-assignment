`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 15.09.2026 11:13:08
// Design Name: 
// Module Name: page_fault_handler
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

module page_fault_handler #(
    parameter PID_WIDTH = 8
)(
    input wire                 clk,
    input wire                 reset,

    input wire                 page_fault,
    input wire [14:0]          fault_page,
    input wire [PID_WIDTH-1:0] fault_pid,

    output reg                 victim_request,

    input wire                 victim_valid,
    input wire [15:0]          victim_frame,
    input wire [PID_WIDTH-1:0] victim_pid,
    input wire                 victim_is_free,
    input wire                 no_victim,
    input wire                 lru_busy,

    output reg                 frame_release,
    output reg [15:0]          release_frame,
    output reg                 frame_allocate,
    
    output reg [15:0]          allocate_frame,
    output reg [PID_WIDTH-1:0]  allocate_pid,

    output reg                 page_read,
    output reg [14:0]          page_number,

    input wire [31:0]          page_data,
    input wire                 page_data_valid,
    input wire                 page_done,
    input wire                 disk_busy,

    output reg                 memory_valid,
    output reg                 memory_write,
    output reg [25:0]          memory_addr,
    output reg [31:0]          memory_write_data,

    input wire                 memory_ready,


    output reg                 fault_done,
    output reg                 fault_stall,
    output reg                 busy
);

    

    reg [14:0] fault_page_reg;
    reg [PID_WIDTH-1:0] fault_pid_reg;

    reg [15:0] selected_frame;
    reg [7:0]  word_counter;

 

    localparam IDLE            = 3'd0;
    localparam REQUEST_VICTIM  = 3'd1;
    localparam WAIT_VICTIM     = 3'd2;
    localparam START_DISK      = 3'd3;
    localparam LOAD_PAGE       = 3'd4;
    localparam FINISH          = 3'd5;
    localparam STALL           = 3'd6;

    reg [2:0] state;



    always @(posedge clk) begin

        if (reset) begin

            state            <= IDLE;

            fault_page_reg   <= 15'd0;
            fault_pid_reg    <= {PID_WIDTH{1'b0}};

            selected_frame   <= 16'd0;
            word_counter     <= 8'd0;

            victim_request   <= 1'b0;

            frame_release    <= 1'b0;
            release_frame    <= 16'd0;

            frame_allocate   <= 1'b0;
            allocate_frame   <= 16'd0;
            allocate_pid     <= {PID_WIDTH{1'b0}};

            page_read        <= 1'b0;
            page_number      <= 15'd0;

            fault_done       <= 1'b0;
            fault_stall      <= 1'b0;
            busy             <= 1'b0;
        end

        else begin


            victim_request <= 1'b0;
            frame_release  <= 1'b0;
            frame_allocate <= 1'b0;
            page_read      <= 1'b0;

            fault_done     <= 1'b0;
            fault_stall    <= 1'b0;


            case (state)



                IDLE: begin

                    busy <= 1'b0;
                    word_counter <= 8'd0;

                    if (page_fault) begin

                        fault_page_reg <= fault_page;
                        fault_pid_reg  <= fault_pid;

                        busy  <= 1'b1;
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
                        if (!victim_is_free) begin

                            frame_release <= 1'b1;
                            release_frame <= victim_frame;

                        end

                        word_counter <= 8'd0;

                        state <= START_DISK;
                    end
                end


                START_DISK: begin

                    busy <= 1'b1;

                    page_read   <= 1'b1;
                    page_number <= fault_page_reg;

                    state <= LOAD_PAGE;
                end


                LOAD_PAGE: begin

                    busy <= 1'b1;

                    if (page_data_valid) begin
                        word_counter <= word_counter + 1'b1;
                    end

                    if (page_done) begin
                        state <= FINISH;
                    end
                end

                FINISH: begin

                    busy <= 1'b1;

                    if (memory_ready) begin
                        frame_allocate <= 1'b1;
                        allocate_frame <= selected_frame;
                        allocate_pid   <= fault_pid_reg;

                        fault_done <= 1'b1;
                        busy       <= 1'b0;

                        state <= IDLE;
                    end
                end

                STALL: begin

                    busy        <= 1'b1;
                    fault_stall <= 1'b1;

                    if (!page_fault) begin
                        state <= IDLE;
                        busy  <= 1'b0;
                    end
                end


                default: begin
                    state <= IDLE;
                    busy  <= 1'b0;
                end

            endcase
        end
    end


    always @(*) begin

        // Defaults
        memory_valid     = 1'b0;
        memory_write     = 1'b0;
        memory_addr      = 26'd0;
        memory_write_data = 32'd0;

        if ((state == LOAD_PAGE) && page_data_valid) begin

            memory_valid      = 1'b1;
            memory_write      = 1'b1;
            memory_write_data = page_data;

            memory_addr =
                {selected_frame, 10'b0} +
                ({18'b0, word_counter} << 2);
        end
    end

endmodule
