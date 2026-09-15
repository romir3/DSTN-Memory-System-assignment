`timescale 1ns / 1ps

module memory_lru #(
    parameter NUM_FRAMES = 65536,
    parameter NUM_PROCESSES = 256,
    parameter PID_WIDTH = 8,
    parameter MIN_PAGES = 2,
    parameter BOOT_FRAME_0 = 16'h0010,
    parameter BOOT_FRAME_1 = 16'h0011
)(
    input wire clk,
    input wire reset,

    input wire access_valid,
    input wire [15:0] access_frame,

    input wire frame_allocate,
    input wire [15:0] allocate_frame,
    input wire [PID_WIDTH-1:0] allocate_pid,
    input wire [14:0] allocate_vpn,

    input wire dirty_update_valid,
    input wire [15:0] dirty_frame,

    input wire frame_release,
    input wire [15:0] release_frame,

    input wire victim_request,

    output reg victim_valid,
    output reg [15:0] victim_frame,
    output reg [PID_WIDTH-1:0] victim_pid,
    output reg [14:0] victim_vpn,
    output reg victim_dirty,
    output reg victim_is_free,
    output reg no_victim,
    output reg busy
);

    reg frame_valid [0:NUM_FRAMES-1];
    reg [PID_WIDTH-1:0] frame_pid [0:NUM_FRAMES-1];
    reg [31:0] last_used [0:NUM_FRAMES-1];
    reg [14:0] frame_vpn [0:NUM_FRAMES-1];
    reg frame_dirty [0:NUM_FRAMES-1];

    reg [15:0] process_page_count [0:NUM_PROCESSES-1];

    reg [31:0] lru_counter;

    reg [15:0] scan_frame;
    reg [15:0] best_frame;
    reg [31:0] best_timestamp;
    reg found_candidate;
    reg found_free;

    localparam IDLE = 2'd0;
    localparam SCAN = 2'd1;
    localparam DONE = 2'd2;

    reg [1:0] state;

    integer i;

    always @(posedge clk) begin
        if (reset) begin
            state <= IDLE;
            busy <= 1'b0;

            victim_valid <= 1'b0;
            victim_frame <= 16'd0;
            victim_pid <= {PID_WIDTH{1'b0}};
            victim_vpn <= 15'd0;
            victim_dirty <= 1'b0;
            victim_is_free <= 1'b0;
            no_victim <= 1'b0;

            scan_frame <= 16'd0;
            best_frame <= 16'd0;
            best_timestamp <= 32'hFFFFFFFF;
            found_candidate <= 1'b0;
            found_free <= 1'b0;

            lru_counter <= 32'd2;

            for (i = 0; i < NUM_FRAMES; i = i + 1) begin
                frame_valid[i] <= 1'b0;
                frame_pid[i] <= {PID_WIDTH{1'b0}};
                last_used[i] <= 32'd0;
                frame_vpn[i] <= 15'd0;
                frame_dirty[i] <= 1'b0;
            end

            for (i = 0; i < NUM_PROCESSES; i = i + 1) begin
                process_page_count[i] <= 16'd0;
            end

            frame_valid[BOOT_FRAME_0] <= 1'b1;
            frame_pid[BOOT_FRAME_0] <= 8'd0;
            last_used[BOOT_FRAME_0] <= 32'd0;
            frame_vpn[BOOT_FRAME_0] <= 15'd0;
            frame_dirty[BOOT_FRAME_0] <= 1'b0;

            frame_valid[BOOT_FRAME_1] <= 1'b1;
            frame_pid[BOOT_FRAME_1] <= 8'd0;
            last_used[BOOT_FRAME_1] <= 32'd1;
            frame_vpn[BOOT_FRAME_1] <= 15'd1;
            frame_dirty[BOOT_FRAME_1] <= 1'b0;

            process_page_count[0] <= 16'd2;
        end
        else begin
            victim_valid <= 1'b0;
            no_victim <= 1'b0;

            case (state)

                IDLE: begin
                    busy <= 1'b0;

                    if (access_valid && frame_valid[access_frame]) begin
                        last_used[access_frame] <= lru_counter;
                        lru_counter <= lru_counter + 1'b1;
                    end

                    if (frame_allocate) begin
                        frame_valid[allocate_frame] <= 1'b1;
                        frame_pid[allocate_frame] <= allocate_pid;
                        frame_vpn[allocate_frame] <= allocate_vpn;
                        frame_dirty[allocate_frame] <= 1'b0;
                        last_used[allocate_frame] <= lru_counter;

                        process_page_count[allocate_pid] <=
                            process_page_count[allocate_pid] + 1'b1;

                        lru_counter <= lru_counter + 1'b1;
                    end

                    if (dirty_update_valid && frame_valid[dirty_frame]) begin
                        frame_dirty[dirty_frame] <= 1'b1;
                    end

                    if (frame_release && frame_valid[release_frame]) begin
                        if (process_page_count[frame_pid[release_frame]] != 0)
                            process_page_count[frame_pid[release_frame]] <=
                                process_page_count[frame_pid[release_frame]] - 1'b1;

                        frame_valid[release_frame] <= 1'b0;
                        frame_dirty[release_frame] <= 1'b0;
                    end

                    if (victim_request) begin
                        scan_frame <= 16'd0;
                        best_frame <= 16'd0;
                        best_timestamp <= 32'hFFFFFFFF;
                        found_candidate <= 1'b0;
                        found_free <= 1'b0;
                        busy <= 1'b1;
                        state <= SCAN;
                    end
                end

                SCAN: begin
                    busy <= 1'b1;

                    if (!frame_valid[scan_frame]) begin
                        best_frame <= scan_frame;
                        found_free <= 1'b1;
                        state <= DONE;
                    end
                    else begin
                        if (process_page_count[frame_pid[scan_frame]] > MIN_PAGES) begin
                            if (!found_candidate) begin
                                best_frame <= scan_frame;
                                best_timestamp <= last_used[scan_frame];
                                found_candidate <= 1'b1;
                            end
                            else if (last_used[scan_frame] < best_timestamp) begin
                                best_frame <= scan_frame;
                                best_timestamp <= last_used[scan_frame];
                            end
                        end

                        if (scan_frame == NUM_FRAMES - 1) begin
                            state <= DONE;
                        end
                        else begin
                            scan_frame <= scan_frame + 1'b1;
                        end
                    end
                end

                DONE: begin
                    busy <= 1'b0;

                    if (found_free) begin
                        victim_frame <= best_frame;
                        victim_pid <= {PID_WIDTH{1'b0}};
                        victim_vpn <= 15'd0;
                        victim_dirty <= 1'b0;
                        victim_is_free <= 1'b1;
                        victim_valid <= 1'b1;
                        no_victim <= 1'b0;
                    end
                    else if (found_candidate) begin
                        victim_frame <= best_frame;
                        victim_pid <= frame_pid[best_frame];
                        victim_vpn <= frame_vpn[best_frame];
                        victim_dirty <= frame_dirty[best_frame];
                        victim_is_free <= 1'b0;
                        victim_valid <= 1'b1;
                        no_victim <= 1'b0;
                    end
                    else begin
                        victim_valid <= 1'b0;
                        victim_is_free <= 1'b0;
                        no_victim <= 1'b1;
                    end

                    state <= IDLE;
                end

                default: begin
                    state <= IDLE;
                    busy <= 1'b0;
                end

            endcase
        end
    end

endmodule