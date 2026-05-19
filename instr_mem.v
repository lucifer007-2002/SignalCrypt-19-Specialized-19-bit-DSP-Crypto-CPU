`timescale 1ns / 1ps
//------------------------------------------------------------
// instr_mem.v
// 19-bit instruction memory — BRAM inferred (36-bit mode)
// Depth: 1024 words = 1K instructions
//
// 19-bit data in 36-bit BRAM: upper [35:19] unused per word.
// Vivado infers RAMB36E1 in TRUE_DP or SDP mode.
// (* rom_style = "block" *) forces BRAM — without it Vivado
// may choose distributed RAM for small depths.
//
// PC is word-addressed — no byte offset needed (custom ISA,
// no sub-word fetch). PC[9:0] is the word address.
//------------------------------------------------------------
module instr_mem #(
    parameter DEPTH = 1024
)(
    input  wire        clk,
    input  wire [18:0] addr,       // PC — word address, [9:0] used
    output reg  [18:0] instr       // registered output — 1-cycle latency
);
    (* rom_style = "block" *)
    reg [18:0] mem [0:DEPTH-1];

    // Load program at simulation time
    // Hex file contains 19-bit words, one per line, zero-padded to 5 hex digits
    initial begin
        $readmemh("programs/test_alu.mem", mem);
    end

    // Synchronous read — mandatory for BRAM inference
    always @(posedge clk) begin
        instr <= mem[addr[9:0]];   // word-addressed, lower 10 bits of PC
    end

endmodule
