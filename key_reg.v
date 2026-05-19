`timescale 1ns / 1ps
//------------------------------------------------------------
// key_reg.v  —  19-bit key register + KEYXOR operation
//
// KEYREG is a single 19-bit register loaded by the LDK
// instruction (load from data memory into key register).
// KEYXOR: rd = rs1 XOR KEYREG
//
// The key register is separate from the 16 general-purpose
// registers — it cannot be read or written by normal ALU
// instructions. Only LDK writes it, only KEYXOR reads it.
// This enforces key isolation as a microarchitectural property.
//------------------------------------------------------------
module key_reg (
    input  wire        clk,
    input  wire        rst,

    // Write port — from memory read result (LDK instruction)
    input  wire [18:0] key_wdata,   // data from DMEM
    input  wire        key_we,      // write enable (LDK)

    // Read port — for KEYXOR operation
    input  wire [18:0] data_in,     // rs1 data to XOR with key
    input  wire        keyxor_en,   // 1 = perform KEYXOR

    output wire [18:0] key_out,     // raw key (for debug only)
    output wire [18:0] xor_result   // data_in XOR KEYREG
);
    reg [18:0] keyreg;

    always @(posedge clk) begin
        if (rst)        keyreg <= 19'd0;
        else if (key_we) keyreg <= key_wdata;
    end

    assign key_out    = keyreg;
    assign xor_result = data_in ^ keyreg;   // combinational XOR — 1 LUT level

endmodule
