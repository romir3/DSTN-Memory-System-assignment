`timescale 1ns / 1ps

module memory_subsystem_top #(
    parameter ADDR_WIDTH = 26,
    parameter PID_WIDTH  = 8
)(
    input wire                  clk,
    input wire                  reset,

    input wire                  page_fault,
    input wire [14:0]           fault_page,
    input wire [PID_WIDTH-1:0]  fault_pid,

    output wire                 page_table_invalidate,
    output wire [PID_WIDTH-1:0] invalidate_pid,
    output wire [14:0]          invalidate_vpn,

    output wire                 page_table_update,
    output wire [PID_WIDTH-1:0] update_pid,
    output wire [14:0]           update_vpn,
    output wire [15:0]           update_frame,

    output wire                 fault_done,
    output wire                 fault_stall,
    output wire                 fault_busy,

    input wire                  l2_read_start,
    input wire [ADDR_WIDTH-1:0] l2_read_addr,
    input wire                  l2_read_ready,

    output wire [31:0]          l2_read_data,
    output wire [2:0]           l2_read_index,
    output wire                 l2_read_valid,
    output wire                 l2_read_done,

    input wire                  l2_write_start,
    input wire [ADDR_WIDTH-1:0] l2_write_addr,
    input wire [31:0]           l2_write_data,
    input wire                  l2_write_valid,

    output wire                 l2_write_ready,
    output wire                 l2_write_done
);

    wire page_load_start;
    wire [15:0] page_load_frame;
    wire [14:0] page_load_number;
    wire page_load_done;

    wire page_writeback_start;
    wire [15:0] page_writeback_frame;
    wire [PID_WIDTH-1:0] page_writeback_pid;
    wire [14:0] page_writeback_number;
    wire page_writeback_done;

    wire page_load_start_to_controller;
    wire page_writeback_start_to_controller;

    wire victim_request;

    wire victim_valid;
    wire [15:0] victim_frame;
    wire [PID_WIDTH-1:0] victim_pid;
    wire [14:0] victim_vpn;
    wire victim_dirty;
    wire victim_is_free;
    wire no_victim;

    wire frame_release;
    wire [15:0] release_frame;

    wire frame_allocate;
    wire [15:0] allocate_frame;
    wire [PID_WIDTH-1:0] allocate_pid;

    wire disk_page_read;
    wire [14:0] disk_page_number;
    wire [31:0] disk_page_data;
    wire disk_page_data_valid;
    wire disk_page_data_ready;

    wire disk_page_write;
    wire [14:0] disk_write_page_number;
    wire [31:0] disk_write_data;
    wire disk_write_valid;
    wire disk_write_ready;

    wire memory_valid;
    wire memory_write;
    wire [ADDR_WIDTH-1:0] memory_addr;
    wire [31:0] memory_write_data;
    wire [31:0] memory_read_data;
    wire memory_ready;

    wire access_valid;
    wire [15:0] access_frame;
    wire dirty_update_valid;
    wire [15:0] dirty_frame;

    assign page_load_start_to_controller =
        page_load_start & ~page_load_done;

    assign page_writeback_start_to_controller =
        page_writeback_start & ~page_writeback_done;

    memory_controller #(
        .ADDR_WIDTH(ADDR_WIDTH)
    ) u_memory_controller (
        .clk(clk),
        .reset(reset),

        .l2_write_start(l2_write_start),
        .l2_write_addr(l2_write_addr),
        .l2_write_data(l2_write_data),
        .l2_write_valid(l2_write_valid),
        .l2_write_ready(l2_write_ready),
        .l2_write_done(l2_write_done),

        .l2_read_start(l2_read_start),
        .l2_read_addr(l2_read_addr),
        .l2_read_data(l2_read_data),
        .l2_read_index(l2_read_index),
        .l2_read_valid(l2_read_valid),
        .l2_read_ready(l2_read_ready),
        .l2_read_done(l2_read_done),

        .page_load_start(page_load_start_to_controller),
        .page_load_frame(page_load_frame),
        .page_load_number(page_load_number),
        .page_load_done(page_load_done),

        .page_writeback_start(page_writeback_start_to_controller),
        .page_writeback_frame(page_writeback_frame),
        .page_writeback_number(page_writeback_number),
        .page_writeback_done(page_writeback_done),

        .disk_page_read(disk_page_read),
        .disk_page_number(disk_page_number),
        .disk_page_data(disk_page_data),
        .disk_page_data_valid(disk_page_data_valid),
        .disk_page_data_ready(disk_page_data_ready),

        .disk_page_write(disk_page_write),
        .disk_write_page_number(disk_write_page_number),
        .disk_write_data(disk_write_data),
        .disk_write_valid(disk_write_valid),
        .disk_write_ready(disk_write_ready),

        .memory_valid(memory_valid),
        .memory_write(memory_write),
        .memory_addr(memory_addr),
        .memory_write_data(memory_write_data),
        .memory_read_data(memory_read_data),
        .memory_ready(memory_ready),

        .access_valid(access_valid),
        .access_frame(access_frame),
        .dirty_update_valid(dirty_update_valid),
        .dirty_frame(dirty_frame)
    );

    main_memory u_main_memory (
        .clk(clk),
        .reset(reset),
        .memory_valid(memory_valid),
        .memory_write(memory_write),
        .memory_addr(memory_addr),
        .memory_write_data(memory_write_data),
        .memory_read_data(memory_read_data),
        .memory_ready(memory_ready)
    );

    disk_memory #(
        .PAGE_SIZE_WORDS(256)
    ) u_disk_memory (
        .clk(clk),
        .reset(reset),

        .page_read(disk_page_read),
        .page_number(disk_page_number),
        .page_data_ready(disk_page_data_ready),

        .page_data(disk_page_data),
        .page_data_valid(disk_page_data_valid),
        .page_done(),

        .page_write_start(disk_page_write),
        .page_write_number(disk_write_page_number),
        .page_write_data(disk_write_data),
        .page_write_valid(disk_write_valid),
        .page_write_ready(disk_write_ready),
        .page_write_done(),

        .busy()
    );

    page_fault_handler #(
        .PID_WIDTH(PID_WIDTH)
    ) u_page_fault_handler (
        .clk(clk),
        .reset(reset),

        .page_fault(page_fault),
        .fault_page(fault_page),
        .fault_pid(fault_pid),

        .victim_request(victim_request),

        .victim_valid(victim_valid),
        .victim_frame(victim_frame),
        .victim_pid(victim_pid),
        .victim_vpn(victim_vpn),
        .victim_dirty(victim_dirty),
        .victim_is_free(victim_is_free),
        .no_victim(no_victim),

        .page_writeback_start(page_writeback_start),
        .page_writeback_frame(page_writeback_frame),
        .page_writeback_pid(page_writeback_pid),
        .page_writeback_number(page_writeback_number),
        .page_writeback_done(page_writeback_done),

        .page_load_start(page_load_start),
        .page_load_frame(page_load_frame),
        .page_load_number(page_load_number),
        .page_load_done(page_load_done),

        .frame_release(frame_release),
        .release_frame(release_frame),

        .frame_allocate(frame_allocate),
        .allocate_frame(allocate_frame),
        .allocate_pid(allocate_pid),

        .page_table_invalidate(page_table_invalidate),
        .invalidate_pid(invalidate_pid),
        .invalidate_vpn(invalidate_vpn),

        .page_table_update(page_table_update),
        .update_pid(update_pid),
        .update_vpn(update_vpn),
        .update_frame(update_frame),

        .fault_done(fault_done),
        .fault_stall(fault_stall),
        .busy(fault_busy)
    );

    memory_lru #(
        .NUM_FRAMES(65536),
        .NUM_PROCESSES(256),
        .PID_WIDTH(PID_WIDTH),
        .MIN_PAGES(2),
        .BOOT_FRAME_0(16'h0010),
        .BOOT_FRAME_1(16'h0011)
    ) u_memory_lru (
        .clk(clk),
        .reset(reset),

        .access_valid(access_valid),
        .access_frame(access_frame),

        .frame_allocate(frame_allocate),
        .allocate_frame(allocate_frame),
        .allocate_pid(allocate_pid),
        .allocate_vpn(page_load_number),

        .dirty_update_valid(dirty_update_valid),
        .dirty_frame(dirty_frame),

        .frame_release(frame_release),
        .release_frame(release_frame),

        .victim_request(victim_request),

        .victim_valid(victim_valid),
        .victim_frame(victim_frame),
        .victim_pid(victim_pid),
        .victim_vpn(victim_vpn),
        .victim_dirty(victim_dirty),
        .victim_is_free(victim_is_free),
        .no_victim(no_victim),
        .busy()
    );

endmodule