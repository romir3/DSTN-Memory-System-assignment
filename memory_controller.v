`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 15.09.2026 12:02:30
// Design Name: 
// Module Name: memory_controller
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

module memory_controller #(
    parameter PID_WIDTH = 8
)(
    input wire clk,
    input wire reset,

    // ============================================================
    // CPU INTERFACE
    // ============================================================

    input wire        cpu_valid,
    input wire        cpu_write,
    input wire [31:0] cpu_va,
    input wire [31:0] cpu_write_data,
    input wire [PID_WIDTH-1:0] current_pid,

    output reg        cpu_ready,
    output reg [31:0] cpu_read_data,

    // ============================================================
    // MMU INTERFACE
    // ============================================================

    output reg        start_translate,
    output reg [31:0]  va_in,

    input wire [25:0]  pa_out,
    input wire         pa_ready,
    input wire         page_fault,
    input wire         seg_fault,
    input wire         mmu_busy,

    // MMU page-table update interface
    output reg         os_page_write_en,
    output reg [15:0]  os_write_page_pt_base,
    output reg [14:0]  os_write_vpn,
    output reg [15:0]  os_write_pfn,
    output reg         os_page_write_valid,

    // ============================================================
    // L2 CACHE INTERFACE
    // ============================================================

    output reg         l2_valid,
    output reg         l2_write,
    output reg [25:0]  l2_addr,
    output reg [31:0]  l2_write_data,

    input wire [31:0]  l2_read_data,
    input wire         l2_ready,

    // ============================================================
    // MAIN MEMORY INTERFACE
    // ============================================================

    output reg         memory_valid,
    output reg         memory_write,
    output reg [25:0]  memory_addr,
    output reg [31:0]  memory_write_data,

    input wire [31:0]  memory_read_data,
    input wire         memory_ready,

    // ============================================================
    // PAGE FAULT HANDLER
    // ============================================================

    output reg                 pf_start,
    output reg [14:0]          pf_page,
    output reg [PID_WIDTH-1:0] pf_pid,

    input wire                 pf_done,
    input wire                 pf_stall,
    input wire                 pf_busy

);

    // ============================================================
    // Latched CPU request
    // ============================================================

    reg        pending_valid;
    reg        pending_write;
    reg [31:0] pending_va;
    reg [31:0] pending_write_data;
    reg [PID_WIDTH-1:0] pending_pid;

    // ============================================================
    // State machine
    // ============================================================

    localparam S_IDLE        = 4'd0;
    localparam S_TRANSLATE  = 4'd1;
    localparam S_L2_ACCESS   = 4'd2;
    localparam S_PAGE_FAULT = 4'd3;
    localparam S_WAIT_FAULT = 4'd4;
    localparam S_RETRY       = 4'd5;
    localparam S_COMPLETE    = 4'd6;
    localparam S_SEG_FAULT   = 4'd7;
    localparam S_STALL       = 4'd8;

    reg [3:0] state;

    // ============================================================
    // Combinational output logic
    // ============================================================

    always @(*) begin

        // Defaults
        start_translate = 1'b0;
        va_in           = pending_va;

        l2_valid        = 1'b0;
        l2_write        = 1'b0;
        l2_addr         = pa_out;
        l2_write_data   = pending_write_data;

        memory_valid    = 1'b0;
        memory_write    = 1'b0;
        memory_addr     = 26'd0;
        memory_write_data = 32'd0;

        pf_start        = 1'b0;
        pf_page         = pending_va[24:10];
        pf_pid          = pending_pid;

        cpu_ready       = 1'b0;

        // Page-table update
        os_page_write_en    = 1'b0;
        os_write_page_pt_base = 16'd0;
        os_write_vpn        = pending_va[24:10];
        os_write_pfn        = pa_out[25:10];
        os_page_write_valid = 1'b0;

        case (state)

            // ====================================================
            // NORMAL L2 ACCESS
            // ====================================================

            S_L2_ACCESS: begin

                l2_valid      = 1'b1;
                l2_write      = pending_write;
                l2_addr       = pa_out;
                l2_write_data = pending_write_data;

            end


            // ====================================================
            // START PAGE FAULT HANDLER
            // ====================================================

            S_PAGE_FAULT: begin

                pf_start = 1'b1;
                pf_page  = pending_va[24:10];
                pf_pid   = pending_pid;

            end


            // ====================================================
            // RETRY AFTER PAGE FAULT
            // ====================================================

            S_RETRY: begin

                start_translate = 1'b1;
                va_in           = pending_va;

            end


            // ====================================================
            // SEGMENTATION FAULT
            // ====================================================

            S_SEG_FAULT: begin

                cpu_ready = 1'b1;

            end


            // ====================================================
            // STALL
            // ====================================================

            S_STALL: begin

                cpu_ready = 1'b0;

            end

        endcase

    end


    // ============================================================
    // Controller FSM
    // ============================================================

    always @(posedge clk or posedge reset) begin

        if (reset) begin

            state <= S_IDLE;

            pending_valid      <= 1'b0;
            pending_write      <= 1'b0;
            pending_va         <= 32'd0;
            pending_write_data <= 32'd0;
            pending_pid        <= {PID_WIDTH{1'b0}};

            cpu_read_data <= 32'd0;

        end

        else begin

            case (state)

                // =================================================
                // IDLE
                // =================================================

                S_IDLE: begin

                    if (cpu_valid) begin

                        pending_valid      <= 1'b1;
                        pending_write      <= cpu_write;
                        pending_va         <= cpu_va;
                        pending_write_data <= cpu_write_data;
                        pending_pid        <= current_pid;

                        state <= S_TRANSLATE;

                    end
                end


                // =================================================
                // TRANSLATION
                // =================================================

                S_TRANSLATE: begin

                    start_translate <= 1'b1;
                    va_in           <= pending_va;

                    /*
                     * MMU has finished translation.
                     */
                    if (seg_fault) begin

                        state <= S_SEG_FAULT;

                    end

                    else if (page_fault) begin

                        state <= S_PAGE_FAULT;

                    end

                    else if (pa_ready) begin

                        state <= S_L2_ACCESS;

                    end

                end


                // =================================================
                // L2 CACHE ACCESS
                // =================================================

                S_L2_ACCESS: begin

                    if (l2_ready) begin

                        cpu_read_data <= l2_read_data;

                        state <= S_COMPLETE;

                    end

                end


                // =================================================
                // START PAGE FAULT HANDLER
                // =================================================

                S_PAGE_FAULT: begin

                    /*
                     * pf_start is asserted combinationally.
                     * Wait for the handler to accept the request.
                     */
                    state <= S_WAIT_FAULT;

                end


                // =================================================
                // WAIT FOR PAGE FAULT HANDLER
                // =================================================

                S_WAIT_FAULT: begin

                    if (pf_stall) begin

                        state <= S_STALL;

                    end

                    else if (pf_done) begin

                        /*
                         * Page is now resident.
                         *
                         * Re-run translation so the page table
                         * supplies the newly assigned PFN.
                         */
                        state <= S_RETRY;

                    end

                end


                // =================================================
                // RETRY TRANSLATION
                // =================================================

                S_RETRY: begin

                    /*
                     * Give MMU another translation request.
                     */
                    state <= S_TRANSLATE;

                end


                // =================================================
                // COMPLETE
                // =================================================

                S_COMPLETE: begin

                    pending_valid <= 1'b0;

                    state <= S_IDLE;

                end


                // =================================================
                // SEGMENTATION FAULT
                // =================================================

                S_SEG_FAULT: begin

                    pending_valid <= 1'b0;

                    state <= S_IDLE;

                end


                // =================================================
                // STALL
                // =================================================

                S_STALL: begin

                    /*
                     * For now remain stalled until the CPU drops
                     * its request.
                     */
                    if (!cpu_valid) begin
                        state <= S_IDLE;
                    end

                end


                default: begin

                    state <= S_IDLE;

                end

            endcase

        end

    end

endmodule