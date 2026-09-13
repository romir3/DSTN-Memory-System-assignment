`timescale 1ns / 1ps

module segment_table (
    input  wire        clk,
    input  wire        rst_n,

    // Translation / Lookup Interface
    input  wire        read_en,
    input  wire [6:0]  seg_num,
    output reg  [15:0] pt_base_addr,
    output reg         seg_valid,
    output reg         seg_fault,

    // OS Configuration / Write Interface
    input  wire        write_en,
    input  wire [6:0]  write_seg_num,
    input  wire [15:0] write_pt_base,
    input  wire        write_valid
);

    // 128 entries for 7-bit segment indexing
    reg [15:0] base_storage  [0:127];
    reg        valid_storage [0:127];

    integer i;

    // Combinational lookup for zero-latency translation walk
    always @(*) begin
        if (read_en) begin
            if (valid_storage[seg_num]) begin
                pt_base_addr = base_storage[seg_num];
                seg_valid    = 1'b1;
                seg_fault    = 1'b0;
            end else begin
                pt_base_addr = 16'd0;
                seg_valid    = 1'b0;
                seg_fault    = 1'b1;
            end
        end else begin
            pt_base_addr = 16'd0;
            seg_valid    = 1'b0;
            seg_fault    = 1'b0;
        end
    end

    // Sequential reset and OS dynamic configuration
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (i = 0; i < 128; i = i + 1) begin
                valid_storage[i] <= 1'b0;
                base_storage[i]  <= 16'd0;
            end
            // Default initialization: Segment 0 active at base 0x0000
            valid_storage[0] <= 1'b1;
            base_storage[0]  <= 16'h0000;
        end else if (write_en) begin
            valid_storage[write_seg_num] <= write_valid;
            base_storage[write_seg_num]  <= write_pt_base;
        end
    end

endmodule