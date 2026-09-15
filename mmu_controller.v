`timescale 1ns / 1ps
`include "address_decompose.v"
`include "l1_tlb.v"
`include "l2_tlb.v"
`include "segment.v"
`include "page_table.v"
`include "frame_table.v"

module mmu_controller #(
    parameter PID_WIDTH  = 3,            // Supports up to 8 processes (0 to 7)
    parameter NUM_FRAMES = 1024          // Number of physical frames
)(
    input  wire                  clk,
    input  wire                  rst_n,
    
    // CPU Interface
    input  wire                  start_translate,
    input  wire [31:0]           va_in,
    input  wire [PID_WIDTH-1:0]  current_pid,         // Active Process ID
    input  wire                  preempt_pulse,       // Synchronous flush on context switch
    
    // Translation Results
    output reg  [25:0]           pa_out,
    output reg                   pa_ready,
    output reg                   page_fault,
    output reg                   seg_fault,
    output reg                   busy,

    // OS Maintenance / Table Write Pass-Through Interface
    input  wire                  os_seg_write_en,
    input  wire [6:0]            os_write_seg_num,
    input  wire [15:0]           os_write_pt_base,
    input  wire                  os_seg_write_valid,

    input  wire                  os_page_write_en,
    input  wire [15:0]           os_write_page_pt_base,
    input  wire [14:0]           os_write_vpn,
    input  wire [15:0]           os_write_pfn,
    input  wire                  os_page_write_valid,

    // OS Frame Table Maintenance & Quota Query Interface
    input  wire                  os_frame_free_en,    // Pulse to deallocate/evict frame
    input  wire [15:0]           os_frame_free_pfn,   // Target frame to free
    input  wire [PID_WIDTH-1:0]  quota_query_pid,     // Query frame count for PID
    output wire [15:0]           quota_frame_count    // Total frames owned by query PID
);

    // =========================================================================
    // 1. Latched Input Address & Decomposition
    // =========================================================================
    reg [31:0] va_reg;
    wire [6:0]  seg_num;
    wire [14:0] vpn;
    wire [9:0]  offset;

    address_decompose decomp_inst (
        .va(va_reg),
        .seg_no(seg_num),
        .vpn(vpn),
        .offset(offset)
    );

    // =========================================================================
    // 2. Global Timestamp Counter (For LRU Tracking in Frame Table)
    // =========================================================================
    reg [31:0] global_timer;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            global_timer <= 32'd0;
        else
            global_timer <= global_timer + 1'b1;
    end

    // =========================================================================
    // 3. Submodule Interconnect Wires & Registers
    // =========================================================================
    // L1 TLB signals
    reg         l1_lookup_en;
    reg         l1_write_en;
    reg  [14:0] l1_write_vpn;
    reg  [15:0] l1_write_pfn;
    wire        l1_hit;
    wire [15:0] l1_pfn;

    // L2 TLB signals
    reg         l2_lookup_en;
    reg         l2_write_en;
    reg  [14:0] l2_write_vpn;
    reg  [15:0] l2_write_pfn;
    wire        l2_hit;
    wire [15:0] l2_pfn;

    // Segment Table signals
    reg         seg_read_en;
    wire [15:0] pt_base_addr;
    wire        seg_valid;
    wire        seg_fault_wire;

    // Page Table signals
    reg         pt_read_en;
    wire [15:0] page_pfn;
    wire        page_valid;
    wire        page_fault_wire;

    // Frame Table signals
    reg         ft_touch_en;
    reg  [15:0] ft_touch_pfn;

    // =========================================================================
    // 4. Submodule Instantiations
    // =========================================================================
    l1_tlb l1_tlb_inst (
        .clk(clk),
        .rst_n(rst_n),
        .flush(preempt_pulse),
        .lookup_en(l1_lookup_en),
        .vpn_in(vpn),
        .write_en(l1_write_en),
        .write_vpn(l1_write_vpn),
        .write_pfn(l1_write_pfn),
        .hit(l1_hit),
        .pfn_out(l1_pfn)
    );

    l2_tlb l2_tlb_inst (
        .clk(clk),
        .rst_n(rst_n),
        .flush(preempt_pulse),
        .lookup_en(l2_lookup_en),
        .vpn_in(vpn),
        .write_en(l2_write_en),
        .write_vpn(l2_write_vpn),
        .write_pfn(l2_write_pfn),
        .hit(l2_hit),
        .pfn_out(l2_pfn)
    );

    segment_table seg_table_inst (
        .clk(clk),
        .rst_n(rst_n),
        .read_en(seg_read_en),
        .seg_num(seg_num),
        .pt_base_addr(pt_base_addr),
        .seg_valid(seg_valid),
        .seg_fault(seg_fault_wire),
        .write_en(os_seg_write_en),
        .write_seg_num(os_write_seg_num),
        .write_pt_base(os_write_pt_base),
        .write_valid(os_seg_write_valid)
    );

    page_table page_table_inst (
        .clk(clk),
        .rst_n(rst_n),
        .read_en(pt_read_en),
        .pt_base_addr(pt_base_addr),
        .vpn(vpn),
        .pfn(page_pfn),
        .page_valid(page_valid),
        .page_fault(page_fault_wire),
        .write_en(os_page_write_en),
        .write_pt_base(os_write_page_pt_base),
        .write_vpn(os_write_vpn),
        .write_pfn(os_write_pfn),
        .write_valid(os_page_write_valid)
    );

    frame_table #(
        .PFN_WIDTH(16),
        .NUM_FRAMES(NUM_FRAMES),
        .PID_WIDTH(PID_WIDTH)
    ) frame_table_inst (
        .clk(clk),
        .rst_n(rst_n),
        .query_pfn(ft_touch_pfn),
        .query_frame_valid(),
        .query_frame_pid(),
        .query_last_used(),
        // Allocates frame to current_pid when the OS updates the page table
        .alloc_en(os_page_write_en),
        .alloc_pfn(os_write_pfn),
        .alloc_pid(current_pid),
        // Frees frame when evicted by the OS
        .free_en(os_frame_free_en),
        .free_pfn(os_frame_free_pfn),
        // Updates LRU timestamp on any hit
        .touch_en(ft_touch_en),
        .touch_pfn(ft_touch_pfn),
        .access_timestamp(global_timer),
        // Quota tracking
        .quota_query_pid(quota_query_pid),
        .quota_frame_count(quota_frame_count)
    );

    // =========================================================================
    // 5. Controller FSM Definition
    // =========================================================================
    localparam S_IDLE       = 3'd0,
               S_L1_CHECK   = 3'd1,
               S_L2_CHECK   = 3'd2,
               S_SEG_CHECK  = 3'd3,
               S_PAGE_CHECK = 3'd4,
               S_DONE       = 3'd5;

    reg [2:0] state;

    // Combinational enable assignments
    always @(*) begin
        l1_lookup_en = (state == S_L1_CHECK);
        l2_lookup_en = (state == S_L2_CHECK);
        seg_read_en  = (state == S_SEG_CHECK);
        pt_read_en   = (state == S_PAGE_CHECK);
    end

    // Sequential state machine
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state        <= S_IDLE;
            va_reg       <= 32'd0;
            pa_out       <= 26'd0;
            pa_ready     <= 1'b0;
            page_fault   <= 1'b0;
            seg_fault    <= 1'b0;
            busy         <= 1'b0;
            l1_write_en  <= 1'b0;
            l1_write_vpn <= 15'd0;
            l1_write_pfn <= 16'd0;
            l2_write_en  <= 1'b0;
            l2_write_vpn <= 15'd0;
            l2_write_pfn <= 16'd0;
            ft_touch_en  <= 1'b0;
            ft_touch_pfn <= 16'd0;
        end else begin
            case (state)
                S_IDLE: begin
                    pa_ready    <= 1'b0;
                    page_fault  <= 1'b0;
                    seg_fault   <= 1'b0;
                    l1_write_en <= 1'b0;
                    l2_write_en <= 1'b0;
                    ft_touch_en <= 1'b0;

                    if (start_translate) begin
                        va_reg <= va_in;
                        busy   <= 1'b1;
                        state  <= S_L1_CHECK;
                    end else begin
                        busy   <= 1'b0;
                    end
                end

                S_L1_CHECK: begin
                    if (l1_hit) begin
                        pa_out       <= {l1_pfn, offset};
                        pa_ready     <= 1'b1;
                        busy         <= 1'b0;
                        ft_touch_en  <= 1'b1;
                        ft_touch_pfn <= l1_pfn;
                        state        <= S_DONE;
                    end else begin
                        state        <= S_L2_CHECK;
                    end
                end

                S_L2_CHECK: begin
                    if (l2_hit) begin
                        pa_out       <= {l2_pfn, offset};
                        pa_ready     <= 1'b1;
                        busy         <= 1'b0;

                        l1_write_en  <= 1'b1;
                        l1_write_vpn <= vpn;
                        l1_write_pfn <= l2_pfn;

                        ft_touch_en  <= 1'b1;
                        ft_touch_pfn <= l2_pfn;

                        state        <= S_DONE;
                    end else begin
                        state        <= S_SEG_CHECK;
                    end
                end

                S_SEG_CHECK: begin
                    if (seg_fault_wire) begin
                        seg_fault <= 1'b1;
                        busy      <= 1'b0;
                        state     <= S_DONE;
                    end else if (seg_valid) begin
                        state     <= S_PAGE_CHECK;
                    end
                end

                S_PAGE_CHECK: begin
                    if (page_fault_wire) begin
                        page_fault <= 1'b1;
                        busy       <= 1'b0;
                        state      <= S_DONE;
                    end else if (page_valid) begin
                        pa_out       <= {page_pfn, offset};
                        pa_ready     <= 1'b1;
                        busy         <= 1'b0;

                        l1_write_en  <= 1'b1;
                        l1_write_vpn <= vpn;
                        l1_write_pfn <= page_pfn;

                        l2_write_en  <= 1'b1;
                        l2_write_vpn <= vpn;
                        l2_write_pfn <= page_pfn;

                        ft_touch_en  <= 1'b1;
                        ft_touch_pfn <= page_pfn;

                        state        <= S_DONE;
                    end
                end

                S_DONE: begin
                    pa_ready    <= 1'b0;
                    page_fault  <= 1'b0;
                    seg_fault   <= 1'b0;
                    l1_write_en <= 1'b0;
                    l2_write_en <= 1'b0;
                    ft_touch_en <= 1'b0;
                    state       <= S_IDLE;
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule