`timescale 1ns / 1ps
//------------------------------------------------------------
// data_mem.v
// 19-bit data memory — BRAM inferred (36-bit mode)
// Depth: 1024 × 19-bit words
//
// Word-addressed: addr[9:0] selects the word.
// No byte/half-word accesses — custom ISA, all ops are 19-bit.
// This simplifies the write path enormously vs. RV32I.
//
// Write: synchronous, single-cycle (ST instruction)
// Read:  synchronous, 1-cycle latency (LD instruction)
//        → programmer must insert NOP after LD (ISA contract)
//
// BRAM inference: identical rules to instr_mem.v
//   (* ram_style = "block" *) attribute mandatory
//   Synchronous read in always @(posedge clk)
//   No conditional on read — BRAM always reads, gate downstream
//------------------------------------------------------------
module data_mem #(
    parameter DEPTH = 1024
)(
    input  wire        clk,
    input  wire [18:0] addr,      // word address from ALU result
    input  wire [18:0] wdata,     // data to write (rs2)
    input  wire        we,        // write enable (ST instruction)
    output reg  [18:0] rdata      // registered read data — 1 cycle latency
);
    (* ram_style = "block" *)
    reg [18:0] mem [0:DEPTH-1];

    integer i;
    initial begin
        for (i = 0; i < DEPTH; i = i + 1)
            mem[i] = 19'd0;
        // Optional: preload test data
        // $readmemh("programs/data_init.mem", mem);
    end

    // Synchronous write
    always @(posedge clk) begin
        if (we)
            mem[addr[9:0]] <= wdata;
    end

    // Synchronous read — unconditional (BRAM always reads)
    // Gate the result in WB via wb_sel, not here
    always @(posedge clk) begin
        rdata <= mem[addr[9:0]];
    end

endmodule
