module address_decompose(input [31:0] va,output reg [6:0] seg_no, output reg [14:0] vpn,output reg [9:0] offset);

always @(va) begin
    seg_no = va[31:25];
    vpn = va[24:10];
    offset = va[9:0];
end

endmodule
