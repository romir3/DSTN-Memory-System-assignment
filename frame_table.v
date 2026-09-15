`timescale 1ns / 1ps

module frame_table #(
    parameter PFN_WIDTH  = 16,
    parameter NUM_FRAMES = 1024,
    parameter PID_WIDTH  = 3
)(
    input  wire                  clk,
    input  wire                  rst_n,

    input  wire [PFN_WIDTH-1:0]  query_pfn,
    output wire                  query_frame_valid,
    output wire [PID_WIDTH-1:0]  query_frame_pid,
    output wire [31:0]           query_last_used,

    input  wire                  alloc_en,
    input  wire [PFN_WIDTH-1:0]  alloc_pfn,
    input  wire [PID_WIDTH-1:0]  alloc_pid,

    input  wire                  free_en,
    input  wire [PFN_WIDTH-1:0]  free_pfn,

    input  wire                  touch_en,
    input  wire [PFN_WIDTH-1:0]  touch_pfn,
    input  wire [31:0]           access_timestamp,

    input  wire [PID_WIDTH-1:0]  quota_query_pid,
    output reg  [15:0]           quota_frame_count
);

    reg                   frame_valid [0:NUM_FRAMES-1];
    reg [PID_WIDTH-1:0]   frame_pid   [0:NUM_FRAMES-1];
    reg [31:0]            last_used   [0:NUM_FRAMES-1];

    integer i;

    assign query_frame_valid = (query_pfn < NUM_FRAMES) ? frame_valid[query_pfn] : 1'b0;
    assign query_frame_pid   = (query_pfn < NUM_FRAMES) ? frame_pid[query_pfn]   : {PID_WIDTH{1'b0}};
    assign query_last_used   = (query_pfn < NUM_FRAMES) ? last_used[query_pfn]   : 32'd0;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (i = 0; i < NUM_FRAMES; i = i + 1) begin
                frame_valid[i] <= 1'b0;
                frame_pid[i]   <= {PID_WIDTH{1'b0}};
                last_used[i]   <= 32'd0;
            end
        end else begin

            if (free_en && (free_pfn < NUM_FRAMES)) begin
                frame_valid[free_pfn] <= 1'b0;
                frame_pid[free_pfn]   <= {PID_WIDTH{1'b0}};
                last_used[free_pfn]   <= 32'd0;
            end

            if (alloc_en && (alloc_pfn < NUM_FRAMES)) begin
                frame_valid[alloc_pfn] <= 1'b1;
                frame_pid[alloc_pfn]   <= alloc_pid;
                last_used[alloc_pfn]   <= access_timestamp;
            end

            if (touch_en && (touch_pfn < NUM_FRAMES)) begin
                last_used[touch_pfn]   <= access_timestamp;
            end
        end
    end

    always @(*) begin
        quota_frame_count = 16'd0;
        for (i = 0; i < NUM_FRAMES; i = i + 1) begin
            if (frame_valid[i] && (frame_pid[i] == quota_query_pid)) begin
                quota_frame_count = quota_frame_count + 1'b1;
            end
        end
    end

endmodule
