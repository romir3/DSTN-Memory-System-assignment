`timescale 1ns / 1ps

module frame_table #(
    parameter PFN_WIDTH  = 16,            // 16-bit PFN (up to 65,536 frames)
    parameter NUM_FRAMES = 1024,          // Scalable depth (e.g., 1024 for sim, 65536 for full 64MB)
    parameter PID_WIDTH  = 3              // Up to 8 concurrent processes (P0 to P7)
)(
    input  wire                  clk,
    input  wire                  rst_n,

    // -------------------------------------------------------------
    // 1. Frame Lookup / Query Interface
    // -------------------------------------------------------------
    input  wire [PFN_WIDTH-1:0]  query_pfn,
    output wire                  query_frame_valid,
    output wire [PID_WIDTH-1:0]  query_frame_pid,
    output wire [31:0]           query_last_used,

    // -------------------------------------------------------------
    // 2. Frame Allocation Interface (Page Fault / Initial Loading)
    // -------------------------------------------------------------
    input  wire                  alloc_en,
    input  wire [PFN_WIDTH-1:0]  alloc_pfn,
    input  wire [PID_WIDTH-1:0]  alloc_pid,

    // -------------------------------------------------------------
    // 3. Frame Eviction / Free Interface (Page Replacement)
    // -------------------------------------------------------------
    input  wire                  free_en,
    input  wire [PFN_WIDTH-1:0]  free_pfn,

    // -------------------------------------------------------------
    // 4. Access / Touch Interface (For Sarath's LRU Timestamping)
    // -------------------------------------------------------------
    input  wire                  touch_en,
    input  wire [PFN_WIDTH-1:0]  touch_pfn,
    input  wire [31:0]           access_timestamp,

    // -------------------------------------------------------------
    // 5. Process Quota Status (Counts frames owned by a specific PID)
    // -------------------------------------------------------------
    input  wire [PID_WIDTH-1:0]  quota_query_pid,
    output reg  [15:0]           quota_frame_count
);

    // Metadata Storage Arrays
    reg                   frame_valid [0:NUM_FRAMES-1];
    reg [PID_WIDTH-1:0]   frame_pid   [0:NUM_FRAMES-1];
    reg [31:0]            last_used   [0:NUM_FRAMES-1];

    integer i;

    // Combinational Read Output for query_pfn
    assign query_frame_valid = (query_pfn < NUM_FRAMES) ? frame_valid[query_pfn] : 1'b0;
    assign query_frame_pid   = (query_pfn < NUM_FRAMES) ? frame_pid[query_pfn]   : {PID_WIDTH{1'b0}};
    assign query_last_used   = (query_pfn < NUM_FRAMES) ? last_used[query_pfn]   : 32'd0;

    // Sequential Updates: Allocations, Deallocations, and LRU Touches
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (i = 0; i < NUM_FRAMES; i = i + 1) begin
                frame_valid[i] <= 1'b0;
                frame_pid[i]   <= {PID_WIDTH{1'b0}};
                last_used[i]   <= 32'd0;
            end
        end else begin
            // 1. Eviction / Freeing a frame to the disk
            if (free_en && (free_pfn < NUM_FRAMES)) begin
                frame_valid[free_pfn] <= 1'b0;
                frame_pid[free_pfn]   <= {PID_WIDTH{1'b0}};
                last_used[free_pfn]   <= 32'd0;
            end

            // 2. Allocating a new frame to a process from the disk
            if (alloc_en && (alloc_pfn < NUM_FRAMES)) begin
                frame_valid[alloc_pfn] <= 1'b1;
                frame_pid[alloc_pfn]   <= alloc_pid;
                last_used[alloc_pfn]   <= access_timestamp;
            end

            // 3. Updating LRU timestamp upon an active read/write hit
            if (touch_en && (touch_pfn < NUM_FRAMES)) begin
                last_used[touch_pfn]   <= access_timestamp;
            end
        end
    end

    // Combinational Logic to compute how many pages currently belong to quota_query_pid
    always @(*) begin
        quota_frame_count = 16'd0;
        for (i = 0; i < NUM_FRAMES; i = i + 1) begin
            if (frame_valid[i] && (frame_pid[i] == quota_query_pid)) begin
                quota_frame_count = quota_frame_count + 1'b1;
            end
        end
    end

endmodule