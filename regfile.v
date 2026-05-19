`timescale 1ns / 1ps
//------------------------------------------------------------
// regfile.v
// 16 × 19-bit register file
// Two synchronous read ports, one synchronous write port
//
// x0 (r0) is NOT hardwired to zero in this ISA — all 16
// registers are general purpose. This differs from RISC-V.
// If you want a zero register, reserve r15 by convention
// and never write to it in your programs.
//
// Sync reads: 1-cycle read latency (same as BRAM).
// This means rs1_data and rs2_data arrive one cycle after
// the address is presented — same timing as RISC-V BRAM regfile.
//------------------------------------------------------------
module regfile (
    input  wire        clk,

    // Read port A (rs1)
    input  wire [3:0]  ra1,
    output reg  [18:0] rd1,

    // Read port B (rs2)
    input  wire [3:0]  ra2,
    output reg  [18:0] rd2,

    // Write port (from WB stage)
    input  wire [3:0]  wa,
    input  wire [18:0] wd,
    input  wire        we
);
    reg [18:0] regs [0:15];

    integer i;
    initial begin
        for (i = 0; i < 16; i = i + 1)
            regs[i] = 19'd0;
    end

    // Synchronous write
    always @(posedge clk) begin
        if (we) regs[wa] <= wd;
    end

    // Synchronous read — port A
    always @(posedge clk) begin
        rd1 <= regs[ra1];
    end

    // Synchronous read — port B
    always @(posedge clk) begin
        rd2 <= regs[ra2];
    end
endmodule
