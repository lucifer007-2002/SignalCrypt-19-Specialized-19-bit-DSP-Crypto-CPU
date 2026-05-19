`timescale 1ns / 1ps
//------------------------------------------------------------
// tb_sc19_top.v  —  SignalCrypt-19 full system testbench
// Runs test_full.mem and monitors every instruction class
//------------------------------------------------------------
module tb_sc19_top;
    // 200MHz clock = 5ns period
    reg clk_p = 0, clk_n = 1;
    always #2.5 begin clk_p = ~clk_p; clk_n = ~clk_n; end

    reg         cpu_reset = 1;
    wire [3:0]  led;
    wire        uart_tx;

    sc19_top dut (
        .sysclk_p  (clk_p),
        .sysclk_n  (clk_n),
        .cpu_reset (cpu_reset),
        .led       (led),
        .uart_tx   (uart_tx),
        .uart_rx   (1'b1),
        .dip_sw    (4'b0000)
    );

    // Release reset after 3 cycles
    initial begin
        repeat (3) @(posedge clk_p);
        cpu_reset = 0;
    end

    // Monitor register file writes
    always @(posedge clk_p) begin
        if (!cpu_reset && dut.wb_reg_write)
            $display("t=%0t  WB: r%0d <= 0x%05X (%0d)",
                     $time,
                     dut.wb_rd,
                     dut.wb_data,
                     $signed(dut.wb_data));
    end

    // Monitor MAC accumulator
    always @(posedge clk_p) begin
        if (!cpu_reset && dut.u_ex.id_ex_is_mac)
            $display("t=%0t  MAC: acc=0x%010X (%0d)",
                     $time,
                     dut.u_ex.ex_wb_acc,
                     $signed(dut.u_ex.ex_wb_acc));
    end

    // Monitor HALT
    always @(posedge clk_p) begin
        if (!cpu_reset && dut.cpu_halt) begin
            $display("t=%0t  HALT reached — simulation complete", $time);
            #20 $finish;
        end
    end

    // Timeout safety net
    initial begin
        #5000;
        $display("TIMEOUT — HALT not reached, check program or pipeline");
        $finish;
    end

    // VCD dump for waveform viewing
    initial begin
        $dumpfile("sc19_sim.vcd");
        $dumpvars(0, tb_sc19_top);
    end
endmodule
