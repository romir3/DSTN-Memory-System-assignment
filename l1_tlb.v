module l1_tlb(input clk,input rst_n,input flush,input lookup_en,input [14:0] vpn_in,input write_en,input [14:0] write_vpn,input [15:0] write_pfn,output reg hit,output reg [15:0] pfn_out);


localparam ENTRIES=12;

reg valid [0:ENTRIES-1];
reg [14:0] vpn_tag [0:ENTRIES-1];
reg [15:0]  pfn_data [0:ENTRIES-1];
reg [3:0] replace_ptr;

integer i;

always@(*)begin
    hit=1'b0;
    pfn_out=16'b0;
    if(lookup_en)begin
    for(i=0;i<ENTRIES;i=i+1)begin
        if(valid[i]&&vpn_in==vpn_tag[i])begin
            hit=1'b1;
            pfn_out=pfn_data[i];
        end
    end
end

end

always@(posedge clk or negedge rst_n)begin
    if(!rst_n)begin
        //reset is active low meant to reset the tlb
        replace_ptr<=4'd0;
        for(i=0;i<ENTRIES;i=i+1)begin
            valid[i]<=1'b0;
            vpn_tag[i]<=15'b0;
            pfn_data[i]<=15'b0;
        end
    end
    else if(flush)begin
        //flush is meant to invalidate all the tlb addresses so that new process cannot lookup old tlb conversions
        for(i=0;i<ENTRIES;i++)begin
            valid[i]<=1'b0;
        end
        replace_ptr<=4'd0;
    end
    else if(write_en)begin
        valid[replace_ptr]=1'b1;
        pfn_data[replace_ptr]=write_pfn;
        vpn_tag[replace_ptr]=write_vpn;
if(replace_ptr==ENTRIES-1)begin 
    replace_ptr<=4'd0;
end
else begin
    replace_ptr<=replace_ptr+1'b1;
end
    end
end




endmodule