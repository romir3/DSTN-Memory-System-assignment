module top_cache #(
    parameter ADDR_WIDTH = 26,
    parameter DATA_WIDTH = 32
)(
    input clk,
    input reset,

    // ==================================================
    // Interface with Person 1: MMU / TLB
    // ==================================================

    input mmu_valid,
    input mmu_write,
    input [ADDR_WIDTH-1:0] mmu_addr,
    input [DATA_WIDTH-1:0] mmu_write_data,

    output [DATA_WIDTH-1:0] mmu_read_data,
    output mmu_ready,
    output mmu_hit,

    // ==================================================
    // Interface with Person 3: Main Memory
    // ==================================================

    output memory_valid,
    output memory_write,
    output [ADDR_WIDTH-1:0] memory_addr,
    output [DATA_WIDTH-1:0] memory_write_data,

    input [DATA_WIDTH-1:0] memory_read_data,
    input memory_ready
);

    // ==================================================
    // L1 Cache <-> L2 Cache signals
    // ==================================================

    wire l2_valid;
    wire l2_write;
    wire [ADDR_WIDTH-1:0] l2_addr;
    wire [DATA_WIDTH-1:0] l2_write_data;

    wire [DATA_WIDTH-1:0] l2_read_data;
    wire l2_ready;


    // ==================================================
    // L1 Cache
    // ==================================================

    l1_cache #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH)
    ) l1 (
        .clk(clk),
        .reset(reset),

        // Person 1 / MMU side
        .cpu_valid(mmu_valid),
        .cpu_write(mmu_write),
        .cpu_addr(mmu_addr),
        .cpu_write_data(mmu_write_data),

        .cpu_read_data(mmu_read_data),
        .cpu_ready(mmu_ready),
        .cpu_hit(mmu_hit),

        // L2 side
        .l2_valid(l2_valid),
        .l2_write(l2_write),
        .l2_addr(l2_addr),
        .l2_write_data(l2_write_data),

        .l2_read_data(l2_read_data),
        .l2_ready(l2_ready)
    );


    // ==================================================
    // L2 Cache
    // ==================================================

    l2_cache #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH)
    ) l2 (
        .clk(clk),
        .reset(reset),

        // L1 side
        .upper_valid(l2_valid),
        .upper_write(l2_write),
        .upper_addr(l2_addr),
        .upper_write_data(l2_write_data),

        .upper_read_data(l2_read_data),
        .upper_ready(l2_ready),

        // Main memory side
        .memory_valid(memory_valid),
        .memory_write(memory_write),
        .memory_addr(memory_addr),
        .memory_write_data(memory_write_data),

        .memory_read_data(memory_read_data),
        .memory_ready(memory_ready)
    );

endmodule