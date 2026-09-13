`timescale 1ns / 1ps

module page_table (
    input  wire        clk,
    input  wire        rst_n,

    // Translation / Lookup Interface
    input  wire        read_en,
    input  wire [15:0] pt_base_addr,
    input  wire [14:0] vpn,
    output reg  [15:0] pfn,
    output reg         page_valid,
    output reg         page_fault,

    // OS Page Fault Handler Refill Interface
    input  wire        write_en,
    input  wire [15:0] write_pt_base,
    input  wire [14:0] write_vpn,
    input  wire [15:0] write_pfn,
    input  wire        write_valid
);

    // Simulation depth for mapped address space
    localparam TABLE_SIZE = 1024;

    reg [15:0] pfn_storage   [0:TABLE_SIZE-1];
    reg        valid_storage [0:TABLE_SIZE-1];

    wire [15:0] lookup_index = pt_base_addr + vpn;
    wire [15:0] write_index  = write_pt_base + write_vpn;

    integer i;

    // Combinational indexing: PTE index = pt_base_addr + vpn
    always @(*) begin
        if (read_en) begin
            if ((lookup_index < TABLE_SIZE) && valid_storage[lookup_index]) begin
                pfn        = pfn_storage[lookup_index];
                page_valid = 1'b1;
                page_fault = 1'b0;
            end else begin
                pfn        = 16'd0;
                page_valid = 1'b0;
                page_fault = 1'b1;
            end
        end else begin
            pfn        = 16'd0;
            page_valid = 1'b0;
            page_fault = 1'b0;
        end
    end

    // Sequential reset and dynamic page-swap update
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (i = 0; i < TABLE_SIZE; i = i + 1) begin
                valid_storage[i] <= 1'b0;
                pfn_storage[i]   <= 16'd0;
            end

            // Pre-paged mappings: First 2 blocks (pages 0 & 1) pre-loaded
            valid_storage[0] <= 1'b1;
            pfn_storage[0]   <= 16'h0010; // Page 0 -> PFN 0x0010

            valid_storage[1] <= 1'b1;
            pfn_storage[1]   <= 16'h0011; // Page 1 -> PFN 0x0011
        end else if (write_en) begin
            if (write_index < TABLE_SIZE) begin
                valid_storage[write_index] <= write_valid;
                pfn_storage[write_index]   <= write_pfn;
            end
        end
    end

endmodule