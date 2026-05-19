`timescale 1ns / 1ps
//------------------------------------------------------------
// if_stage.v
// Instruction fetch — manages PC, drives IMEM, handles
// stall (freeze PC), flush (inject NOP), branch redirect
//
// PC is word-addressed — increments by 1 per cycle, not by 4.
// Branch target is an absolute word address (from EX stage),
// not a byte offset. Custom ISA — no alignment constraints.
//------------------------------------------------------------
module if_stage (
    input  wire        clk,
    input  wire        rst,

    // Hazard controls
    input  wire        stall,          // hold PC, freeze IF/ID register
    input  wire        flush,          // squash fetched instr — insert NOP

    // Branch/jump redirect from EX stage
    input  wire        branch_taken,
    input  wire [18:0] branch_target,  // absolute word address

    // To ID stage (IF/ID pipeline register outputs)
    output reg  [18:0] if_id_pc,
    output wire [18:0] if_id_instr,    // from IMEM registered output
    output reg         if_id_valid
);
    // ── PC register ──────────────────────────────────────────
    reg  [18:0] pc;
    wire [18:0] pc_next;

    // PC mux: branch overrides sequential increment
    // Custom ISA: PC+1 (word-addressed), not PC+4
    assign pc_next = branch_taken ? branch_target : (pc + 19'd1);

    always @(posedge clk) begin
        if (rst)        pc <= 19'd0;
        else if (!stall) pc <= pc_next;
        // stall: PC holds
    end

    // ── Instruction memory (instantiated at top level) ────────
    // if_id_instr is the registered IMEM output — wired from top
    // We expose the PC to drive IMEM address input
    // (IMEM instantiated in sc19_top.v, output connected here)
    assign if_id_instr = if_id_instr; // driven from top-level wire

    // ── IF/ID pipeline register ───────────────────────────────
    always @(posedge clk) begin
        if (rst || flush) begin
            if_id_pc    <= 19'd0;
            if_id_valid <= 1'b0;     // bubble / NOP
        end else if (!stall) begin
            if_id_pc    <= pc;
            if_id_valid <= 1'b1;
        end
        // stall: register holds
    end

endmodule
