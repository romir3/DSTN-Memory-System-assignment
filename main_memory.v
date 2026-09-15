`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 15.09.2026 09:43:23
// Design Name: 
// Module Name: main_memory
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


module main_memory(
    input clk,
    input reset,
    input          memory_valid,
    input          memory_write,
    input  [25:0]  memory_addr,
    input  [31:0]  memory_write_data,

    output reg [31:0] memory_read_data,
    output reg        memory_ready
    );
    
    reg [7:0] memory [0:67108863];
    always @(posedge clk) begin
        if (reset) begin
            memory_read_data <= 32'b0;
            memory_ready     <= 1'b0;
        end
        else begin
            memory_ready <= 1'b0;
    
            if (memory_valid) begin
                if (memory_write) begin
                    memory[memory_addr]     <= memory_write_data[7:0];
                    memory[memory_addr + 1] <= memory_write_data[15:8];
                    memory[memory_addr + 2] <= memory_write_data[23:16];
                    memory[memory_addr + 3] <= memory_write_data[31:24];
                end
                else begin
                    memory_read_data <= {
                        memory[memory_addr + 3],
                        memory[memory_addr + 2],
                        memory[memory_addr + 1],
                        memory[memory_addr]
                    };
                end
    
                memory_ready <= 1'b1;
            end
        end
    end
endmodule
