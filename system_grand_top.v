`timescale 1ns / 1ps

module system_grand_top #(
    parameter ADDR_WIDTH = 26,
    parameter DATA_WIDTH = 32,
    parameter PID_WIDTH  = 8,
    parameter NUM_FRAMES = 1024
)(
    input  wire                  clk,
    input  wire                  reset,

    input  wire                  cpu_req,
    input  wire                  cpu_write,
    input  wire [31:0]           cpu_va,
    input  wire [DATA_WIDTH-1:0] cpu_wdata,
    input  wire [PID_WIDTH-1:0]  cpu_pid,
    input  wire                  cpu_flush,

    output reg  [DATA_WIDTH-1:0] cpu_rdata,
    output reg                   cpu_ready,
    output wire                  cpu_hit,
    output wire [ADDR_WIDTH-1:0] cpu_pa,

    output wire                  page_fault_pulse,
    output wire                  fault_servicing,
    output wire                  fault_resolved,
    output wire                  seg_fault_flag,
    output wire                  system_busy
);

    wire [ADDR_WIDTH-1:0] mmu_pa_out;
    wire                  mmu_pa_ready;
    wire                  mmu_seg_fault;
    wire                  mmu_busy;
    wire                  mmu_page_fault;
    wire [14:0]           mmu_fault_page;
    wire [PID_WIDTH-1:0]  mmu_fault_pid;

    wire                  cache_mem_valid;
    wire                  cache_mem_write;
    wire [ADDR_WIDTH-1:0] cache_mem_addr;
    wire [DATA_WIDTH-1:0] cache_mem_wdata;
    wire [DATA_WIDTH-1:0] cache_mem_rdata;
    wire                  cache_mem_ready;

    wire                  ps_pt_invalidate;
    wire [PID_WIDTH-1:0]  ps_inv_pid;
    wire [14:0]           ps_inv_vpn;
    wire                  ps_pt_update;
    wire [PID_WIDTH-1:0]  ps_upd_pid;
    wire [14:0]           ps_upd_vpn;
    wire [15:0]           ps_upd_frame;
    wire                  ps_fault_done;
    wire                  ps_fault_stall;
    wire                  ps_fault_busy;

    wire                  l2_read_start;
    wire [ADDR_WIDTH-1:0] l2_read_addr;
    wire                  l2_read_ready;
    wire [31:0]           l2_read_data;
    wire [2:0]            l2_read_index;
    wire                  l2_read_valid;
    wire                  l2_read_done;

    wire                  l2_write_start;
    wire [ADDR_WIDTH-1:0] l2_write_addr;
    wire [31:0]           l2_write_data;
    wire                  l2_write_valid;
    wire                  l2_write_ready;
    wire                  l2_write_done;

    assign cpu_pa           = mmu_pa_out;
    assign page_fault_pulse = mmu_page_fault;
    assign fault_servicing  = ps_fault_busy | ps_fault_stall;
    assign fault_resolved   = ps_fault_done;
    assign seg_fault_flag   = mmu_seg_fault;
    assign system_busy      = mmu_busy | ps_fault_busy;

    localparam CPU_IDLE       = 3'd0,
               CPU_TRANSLATE  = 3'd1,
               CPU_WAIT_FAULT = 3'd2,
               CPU_CACHE_REQ  = 3'd3,
               CPU_CACHE_WAIT = 3'd4,
               CPU_DONE       = 3'd5;

    reg [2:0]  cpu_state;
    reg        mmu_start;
    reg [31:0] reg_va;
    reg [31:0] reg_wdata;
    reg        reg_write;
    reg [PID_WIDTH-1:0] reg_pid;

    reg        cache_valid;
    wire [31:0] cache_rdata_out;
    wire        cache_ready_out;
    wire        cache_hit_out;

    assign cpu_hit = cache_hit_out;

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            cpu_state   <= CPU_IDLE;
            mmu_start   <= 1'b0;
            reg_va      <= 32'd0;
            reg_wdata   <= 32'd0;
            reg_write   <= 1'b0;
            reg_pid     <= {PID_WIDTH{1'b0}};
            cache_valid <= 1'b0;
            cpu_ready   <= 1'b0;
            cpu_rdata   <= 32'd0;
        end else begin
            case (cpu_state)
                CPU_IDLE: begin
                    cpu_ready <= 1'b0;
                    if (cpu_req && !system_busy) begin
                        reg_va      <= cpu_va;
                        reg_wdata   <= cpu_wdata;
                        reg_write   <= cpu_write;
                        reg_pid     <= cpu_pid;
                        mmu_start   <= 1'b1;
                        cpu_state   <= CPU_TRANSLATE;
                    end
                end

                CPU_TRANSLATE: begin
                    mmu_start <= 1'b0;
                    if (mmu_seg_fault) begin
                        cpu_ready <= 1'b1;
                        cpu_state <= CPU_DONE;
                    end else if (mmu_page_fault) begin
                        cpu_state <= CPU_WAIT_FAULT;
                    end else if (mmu_pa_ready) begin
                        cache_valid <= 1'b1;
                        cpu_state   <= CPU_CACHE_REQ;
                    end
                end

                CPU_WAIT_FAULT: begin
                    if (ps_fault_done) begin
                        mmu_start <= 1'b1;
                        cpu_state <= CPU_TRANSLATE;
                    end
                end

                CPU_CACHE_REQ: begin
                    cache_valid <= 1'b0;
                    if (cache_ready_out) begin
                        cpu_rdata <= cache_rdata_out;
                        cpu_ready <= 1'b1;
                        cpu_state <= CPU_DONE;
                    end else begin
                        cpu_state <= CPU_CACHE_WAIT;
                    end
                end

                CPU_CACHE_WAIT: begin
                    if (cache_ready_out) begin
                        cpu_rdata <= cache_rdata_out;
                        cpu_ready <= 1'b1;
                        cpu_state <= CPU_DONE;
                    end
                end

                CPU_DONE: begin
                    cpu_ready <= 1'b0;
                    cpu_state <= CPU_IDLE;
                end

                default: cpu_state <= CPU_IDLE;
            endcase
        end
    end

    reg        mem_bridge_busy;
    reg [31:0] l2_read_buffer;

    assign l2_read_start   = cache_mem_valid & ~cache_mem_write & ~mem_bridge_busy;
    assign l2_read_addr    = cache_mem_addr;
    assign l2_read_ready   = 1'b1;
    assign cache_mem_rdata = l2_read_valid ? l2_read_data : l2_read_buffer;

    assign l2_write_start  = cache_mem_valid & cache_mem_write & ~mem_bridge_busy;
    assign l2_write_addr   = cache_mem_addr;
    assign l2_write_data   = cache_mem_wdata;
    assign l2_write_valid  = cache_mem_valid & cache_mem_write;

    assign cache_mem_ready = l2_read_done | l2_write_done;

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            mem_bridge_busy <= 1'b0;
            l2_read_buffer  <= 32'd0;
        end else begin
            if (l2_read_valid)
                l2_read_buffer <= l2_read_data;

            if (l2_read_start | l2_write_start)
                mem_bridge_busy <= 1'b1;
            else if (cache_mem_ready)
                mem_bridge_busy <= 1'b0;
        end
    end

    mmu_top #(
        .PID_WIDTH(PID_WIDTH),
        .NUM_FRAMES(NUM_FRAMES)
    ) u_mmu (
        .clk(clk),
        .reset(reset),

        .start_translate(mmu_start),
        .va_in(reg_va),
        .current_pid(reg_pid),
        .preempt_pulse(cpu_flush),

        .pa_out(mmu_pa_out),
        .pa_ready(mmu_pa_ready),
        .seg_fault(mmu_seg_fault),
        .busy(mmu_busy),

        .page_fault(mmu_page_fault),
        .fault_page(mmu_fault_page),
        .fault_pid(mmu_fault_pid),

        .page_table_invalidate(ps_pt_invalidate),
        .invalidate_pid(ps_inv_pid),
        .invalidate_vpn(ps_inv_vpn),

        .page_table_update(ps_pt_update),
        .update_pid(ps_upd_pid),
        .update_vpn(ps_upd_vpn),
        .update_frame(ps_upd_frame),

        .os_seg_write_en(1'b0),
        .os_write_seg_num(7'd0),
        .os_write_pt_base(16'd0),
        .os_seg_write_valid(1'b0)
    );

    top_cache #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH)
    ) u_cache (
        .clk(clk),
        .reset(reset),

        .mmu_valid(cache_valid),
        .mmu_write(reg_write),
        .mmu_addr(mmu_pa_out),
        .mmu_write_data(reg_wdata),

        .mmu_read_data(cache_rdata_out),
        .mmu_ready(cache_ready_out),
        .mmu_hit(cache_hit_out),

        .memory_valid(cache_mem_valid),
        .memory_write(cache_mem_write),
        .memory_addr(cache_mem_addr),
        .memory_write_data(cache_mem_wdata),

        .memory_read_data(cache_mem_rdata),
        .memory_ready(cache_mem_ready)
    );

    memory_subsystem_top #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .PID_WIDTH(PID_WIDTH)
    ) u_memory_subsystem (
        .clk(clk),
        .reset(reset),

        .page_fault(mmu_page_fault),
        .fault_page(mmu_fault_page),
        .fault_pid(mmu_fault_pid),

        .page_table_invalidate(ps_pt_invalidate),
        .invalidate_pid(ps_inv_pid),
        .invalidate_vpn(ps_inv_vpn),

        .page_table_update(ps_pt_update),
        .update_pid(ps_upd_pid),
        .update_vpn(ps_upd_vpn),
        .update_frame(ps_upd_frame),

        .fault_done(ps_fault_done),
        .fault_stall(ps_fault_stall),
        .fault_busy(ps_fault_busy),

        .l2_read_start(l2_read_start),
        .l2_read_addr(l2_read_addr),
        .l2_read_ready(l2_read_ready),
        .l2_read_data(l2_read_data),
        .l2_read_index(l2_read_index),
        .l2_read_valid(l2_read_valid),
        .l2_read_done(l2_read_done),

        .l2_write_start(l2_write_start),
        .l2_write_addr(l2_write_addr),
        .l2_write_data(l2_write_data),
        .l2_write_valid(l2_write_valid),
        .l2_write_ready(l2_write_ready),
        .l2_write_done(l2_write_done)
    );

endmodule