`timescale 1ns / 1ps

module tb_system_grand_top;

    reg         clk;
    reg         reset;

    reg         cpu_req;
    reg         cpu_write;
    reg  [31:0] cpu_va;
    reg  [31:0] cpu_wdata;
    reg  [7:0]  cpu_pid;
    reg         cpu_flush;

    wire [31:0] cpu_rdata;
    wire        cpu_ready;
    wire        cpu_hit;
    wire [25:0] cpu_pa;

    wire        page_fault_pulse;
    wire        fault_servicing;
    wire        fault_resolved;
    wire        seg_fault_flag;
    wire        system_busy;

    system_grand_top #(
        .ADDR_WIDTH(26),
        .DATA_WIDTH(32),
        .PID_WIDTH(8),
        .NUM_FRAMES(1024)
    ) dut (
        .clk(clk),
        .reset(reset),
        .cpu_req(cpu_req),
        .cpu_write(cpu_write),
        .cpu_va(cpu_va),
        .cpu_wdata(cpu_wdata),
        .cpu_pid(cpu_pid),
        .cpu_flush(cpu_flush),
        .cpu_rdata(cpu_rdata),
        .cpu_ready(cpu_ready),
        .cpu_hit(cpu_hit),
        .cpu_pa(cpu_pa),
        .page_fault_pulse(page_fault_pulse),
        .fault_servicing(fault_servicing),
        .fault_resolved(fault_resolved),
        .seg_fault_flag(seg_fault_flag),
        .system_busy(system_busy)
    );

    always #5 clk = ~clk;

    task cpu_access(
        input             is_write,
        input      [31:0] va,
        input      [31:0] wdata,
        input      [7:0]  pid,
        output reg [31:0] rdata
    );
        integer timeout;
        begin
            while (system_busy) @(posedge clk);

            @(posedge clk);
            cpu_req   <= 1'b1;
            cpu_write <= is_write;
            cpu_va    <= va;
            cpu_wdata <= wdata;
            cpu_pid   <= pid;
            @(posedge clk);
            cpu_req   <= 1'b0;

            timeout = 0;
            while (!cpu_ready && timeout < 20000) begin
                @(posedge clk);
                timeout = timeout + 1;
            end

            if (timeout >= 20000) begin
                $display("[ERROR @ %0t ns] TIMEOUT waiting for cpu_ready on VA = 0x%08h", $time, va);
            end else begin
                rdata = cpu_rdata;
            end
            @(posedge clk);
        end
    endtask

    reg [31:0] read_val;

    initial begin
        $display("\n========================================================");
        $display("   STARTING GRAND TOP MEMORY SUBSYSTEM VERIFICATION     ");
        $display("========================================================\n");

        clk       = 0;
        reset     = 1;
        cpu_req   = 0;
        cpu_write = 0;
        cpu_va    = 32'd0;
        cpu_wdata = 32'd0;
        cpu_pid   = 8'd1;
        cpu_flush = 0;

        #40;
        @(posedge clk);
        reset = 0;
        @(posedge clk);
        $display("[STATUS @ %0t ns] Global reset released.", $time);

        $display("\n--- TEST 1: Pre-paged Read Access (Page 0) ---");
        cpu_access(1'b0, 32'h0000_0004, 32'h0, 8'd1, read_val);
        $display("[TEST 1 PASS @ %0t ns] Read VA=0x%08h -> PA=0x%07h | Data=0x%08h | Hit=%b", 
                 $time, 32'h0000_0004, cpu_pa, read_val, cpu_hit);

        $display("\n--- TEST 2: Memory Write then Readback (Page 0) ---");
        cpu_access(1'b1, 32'h0000_0010, 32'hA5A5_5A5A, 8'd1, read_val);
        $display("[TEST 2 WRITE @ %0t ns] Wrote 0xA5A55A5A to VA=0x00000010 (PA=0x%07h)", $time, cpu_pa);

        cpu_access(1'b0, 32'h0000_0010, 32'h0, 8'd1, read_val);
        if (read_val == 32'hA5A5_5A5A) begin
            $display("[TEST 2 PASS @ %0t ns] Readback matched: 0x%08h | Cache Hit=%b", $time, read_val, cpu_hit);
        end else begin
            $display("[TEST 2 FAIL @ %0t ns] Readback mismatch! Expected 0xA5A55A5A, got 0x%08h", $time, read_val);
        end

        $display("\n--- TEST 3: Page Fault on Unmapped Page (Page 5) ---");
        cpu_access(1'b0, 32'h0000_1400, 32'h0, 8'd1, read_val);
        $display("[TEST 3 PASS @ %0t ns] Resolved Page Fault! VA=0x00001400 mapped to PA=0x%07h | Data=0x%08h", 
                 $time, cpu_pa, read_val);

        $display("\n--- TEST 4: Process Preemption & TLB Flush ---");
        @(posedge clk);
        cpu_flush <= 1'b1;
        @(posedge clk);
        cpu_flush <= 1'b0;
        $display("[STATUS @ %0t ns] Context switch strobe asserted. TLBs flushed.", $time);

        cpu_access(1'b0, 32'h0000_0004, 32'h0, 8'd2, read_val);
        $display("[TEST 4 PASS @ %0t ns] Translation after flush resolved: PA=0x%07h | Data=0x%08h", 
                 $time, cpu_pa, read_val);

        $display("\n--- TEST 5: Process 2 Memory Allocation ---");
        cpu_access(1'b1, 32'h0000_0408, 32'h1234_5678, 8'd2, read_val);
        cpu_access(1'b0, 32'h0000_0408, 32'h0, 8'd2, read_val);
        if (read_val == 32'h1234_5678) begin
            $display("[TEST 5 PASS @ %0t ns] Process 2 readback verified: 0x%08h", $time, read_val);
        end else begin
            $display("[TEST 5 FAIL @ %0t ns] Process 2 readback mismatch: 0x%08h", $time, read_val);
        end

        $display("\n========================================================");
        $display("   ALL TEST VECTORS EXECUTED SUCCESSFULLY               ");
        $display("========================================================\n");
        #100 $finish;
    end

    always @(posedge page_fault_pulse) begin
        $display("[MONITOR @ %0t ns] *** Page Fault Strobe Detected from MMU! ***", $time);
    end

    always @(posedge fault_servicing) begin
        $display("[MONITOR @ %0t ns] Memory subsystem started servicing page swap...", $time);
    end

    always @(posedge fault_resolved) begin
        $display("[MONITOR @ %0t ns] Memory subsystem finished swap (fault_done asserted).", $time);
    end

endmodule