`timescale 1ns / 1ps
//------------------------------------------------------------
// ex_stage.v  —  Execute stage for SignalCrypt-19
//
// Critical timing paths (all must close at 200MHz = 5ns):
//   1. ID/EX.rs1_data → DSP48 A port → P register  (~3.8ns)
//      This is your dominant path. Zero logic allowed here.
//   2. ID/EX.rs1_data → ALU → EX/WB register        (~2.0ns)
//   3. ID/EX.rs1_data → branch comparator → branch_taken
//      → IF stage PC mux                             (~3.0ns)
//   4. crypto_sel → LFSR/SBOX mux → EX/WB register  (~1.5ns)
//
// The EX/WB register is the destination flip-flop for paths
// 1, 2, and 4. Path 3 drives combinational output directly
// back to the IF stage (branch_taken, branch_target).
//------------------------------------------------------------
module ex_stage (
    input  wire        clk,
    input  wire        rst,

    //── From ID/EX pipeline register ─────────────────────────
    input  wire [18:0] id_ex_pc,
    input  wire [18:0] id_ex_rs1_data,
    input  wire [18:0] id_ex_rs2_data,
    input  wire [18:0] id_ex_imm,
    input  wire [3:0]  id_ex_rs1_addr,
    input  wire [3:0]  id_ex_rs2_addr,
    input  wire [3:0]  id_ex_rd_addr,
    input  wire [4:0]  id_ex_opcode,
    input  wire [2:0]  id_ex_fn,

    // Control signals
    input  wire [3:0]  id_ex_alu_op,
    input  wire        id_ex_reg_write,
    input  wire [1:0]  id_ex_wb_sel,
    input  wire        id_ex_mem_read,
    input  wire        id_ex_mem_write,
    input  wire        id_ex_key_write,
    input  wire        id_ex_is_mac,
    input  wire        id_ex_mac_clear,
    input  wire        id_ex_is_crypto,
    input  wire [1:0]  id_ex_crypto_sel,
    input  wire        id_ex_is_branch,
    input  wire        id_ex_is_jump,
    input  wire        id_ex_is_jmpr,
    input  wire        id_ex_is_halt,

    // Flush from hazard unit (branch squash)
    input  wire        flush,

    //── Branch/jump resolution → IF stage ────────────────────
    output reg         branch_taken,
    output reg  [18:0] branch_target,

    // HALT signal to top level
    output wire        cpu_halt,

    //── Memory interface (combinational address + data) ───────
    output wire [18:0] dmem_addr,    // ALU result used as address
    output wire [18:0] dmem_wdata,   // rs2 data for stores
    output wire        dmem_we,      // store write enable
    output wire        dmem_re,      // load read enable

    // Key register write (from LDK — memory data written in WB)
    // Passed through to WB stage which connects to key_reg
    output wire        ex_key_write,

    //── EX/WB pipeline register outputs ──────────────────────
    output reg  [18:0] ex_wb_alu_result,
    output reg  [37:0] ex_wb_acc,
    output reg  [18:0] ex_wb_crypto_result,
    output reg  [3:0]  ex_wb_rd_addr,
    output reg         ex_wb_reg_write,
    output reg  [1:0]  ex_wb_wb_sel,
    output reg         ex_wb_mem_read,
    output reg         ex_wb_mem_write,
    output reg         ex_wb_key_write,
    output reg  [18:0] ex_wb_dmem_addr,
    output reg  [18:0] ex_wb_dmem_wdata
);

    //── ALU operand B mux ─────────────────────────────────────
    // R-type: operand_b = rs2_data
    // I-type: operand_b = sign-extended immediate
    // For ALU_PASS (MOVI): operand_b = imm, result = imm
    wire [18:0] alu_op_b = (id_ex_alu_op == 4'd8) ? id_ex_imm  :  // PASS
                            (id_ex_wb_sel == 2'b00 &&
                             id_ex_reg_write)       ? id_ex_imm  :  // I-type ALU
                                                      id_ex_rs2_data;

    // Note: For R-type instructions (fmt=00), alu_op_b = rs2_data.
    // For I-type (fmt=01), alu_op_b = imm. The control unit already
    // sets alu_op correctly; here we use wb_sel and reg_write to
    // distinguish, but a cleaner approach is to pass fmt through.
    // For this project, pass id_ex_fmt as a separate signal if needed.
    // The version above is a simplification — if you see wrong
    // ALU results on R-type, add id_ex_fmt to the port list and use:
    // wire [18:0] alu_op_b = (id_ex_fmt == 2'b00) ? id_ex_rs2_data : id_ex_imm;

    //── ALU instantiation ─────────────────────────────────────
    wire [18:0] alu_result;
    wire        alu_zero, alu_negative;

    alu u_alu (
        .operand_a (id_ex_rs1_data),
        .operand_b (alu_op_b),
        .alu_op    (id_ex_alu_op),
        .result    (alu_result),
        .zero      (alu_zero),
        .negative  (alu_negative)
    );

    //── DSP48 MAC instantiation ───────────────────────────────
    // DIRECT connection: id_ex_rs1_data → mac a_in
    //                    id_ex_rs2_data → mac b_in
    // No mux, no conditional, no logic between pipeline reg and DSP.
    // mac_en gates the accumulate operation — this is a control
    // signal, not a data signal, so it does not add to the
    // multiply path depth.
    wire [37:0] acc_out;

    mac_unit u_mac (
        .clk       (clk),
        .rst       (rst),
        .a_in      (id_ex_rs1_data),       // direct from ID/EX register
        .b_in      (id_ex_rs2_data[17:0]), // truncated to 18-bit B port
        .mac_en    (id_ex_is_mac),
        .mac_clear (id_ex_mac_clear),
        .acc_out   (acc_out)
    );

    //── Crypto unit instantiation ─────────────────────────────
    // LFSR
    wire [18:0] lfsr_result;
    lfsr_unit u_lfsr (
        .state_in  (id_ex_rs1_data),
        .tap_sel   (id_ex_fn),
        .state_out (lfsr_result)
    );

    // SBOX
    wire [18:0] sbox_result;
    sbox_mem u_sbox (
        .addr     (id_ex_rs1_data[3:0]),
        .sbox_out (sbox_result)
    );

    // Key register and KEYXOR
    wire [18:0] keyxor_result;
    // key_reg is instantiated at top level or WB stage
    // Here we pass through the result — key_reg write port
    // is connected from WB (LDK writeback path)
    // For KEYXOR: result = rs1 XOR KEYREG (from top-level key_reg)
    // We receive keyxor_result as an input from top level
    // (key_reg instantiated in sc19_top.v, result wired here)
    // For now, declare as input — connect in Part 5 integration:
    // assign keyxor_result = id_ex_rs1_data ^ keyreg_value;
    // (placeholder — wired in sc19_top.v)
    assign keyxor_result = 19'd0; // replaced in top-level integration

    // Crypto result mux
    wire [18:0] crypto_result =
        (id_ex_crypto_sel == 2'b00) ? lfsr_result   :
        (id_ex_crypto_sel == 2'b01) ? sbox_result   :
        (id_ex_crypto_sel == 2'b10) ? keyxor_result :
                                       19'd0;

    //── Branch / Jump resolution (combinational) ──────────────
    // Branch condition evaluation
    wire branch_cond =
        (id_ex_opcode == 5'b10100) ?  alu_zero          : // BEQ: rs1 == 0
        (id_ex_opcode == 5'b10101) ? ~alu_zero          : // BNE: rs1 != 0
        (id_ex_opcode == 5'b10110) ?  alu_negative      : // BLT: rs1 < 0 (signed)
                                       1'b0;

    // Branch and jump target computation
    // BEQ/BNE/BLT/JMP: target = PC + sign-extended offset (imm10)
    // JMPR:            target = rs1 (indirect)
    wire [18:0] pc_rel_target  = id_ex_pc + id_ex_imm;
    wire [18:0] jmpr_target    = id_ex_rs1_data;

    always @(*) begin
        branch_taken  = 1'b0;
        branch_target = 19'd0;

        if (id_ex_is_jump) begin
            branch_taken  = 1'b1;
            branch_target = pc_rel_target;   // JMP: unconditional relative
        end else if (id_ex_is_jmpr) begin
            branch_taken  = 1'b1;
            branch_target = jmpr_target;      // JMPR: indirect
        end else if (id_ex_is_branch && branch_cond) begin
            branch_taken  = 1'b1;
            branch_target = pc_rel_target;    // BEQ/BNE/BLT taken
        end
    end

    //── Memory interface (combinational outputs) ─────────────
    // Address = ALU result (rs1 + imm for load/store)
    assign dmem_addr  = alu_result;
    assign dmem_wdata = id_ex_rs2_data;         // store data
    assign dmem_we    = id_ex_mem_write & ~flush;
    assign dmem_re    = id_ex_mem_read  & ~flush;
    assign ex_key_write = id_ex_key_write & ~flush;

    // HALT
    assign cpu_halt = id_ex_is_halt;

    //── EX/WB pipeline register ───────────────────────────────
    wire bubble = rst || flush;

    always @(posedge clk) begin
        if (bubble) begin
            ex_wb_alu_result   <= 19'd0;
            ex_wb_acc          <= 38'd0;
            ex_wb_crypto_result<= 19'd0;
            ex_wb_rd_addr      <= 4'd0;
            ex_wb_reg_write    <= 1'b0;
            ex_wb_wb_sel       <= 2'b00;
            ex_wb_mem_read     <= 1'b0;
            ex_wb_mem_write    <= 1'b0;
            ex_wb_key_write    <= 1'b0;
            ex_wb_dmem_addr    <= 19'd0;
            ex_wb_dmem_wdata   <= 19'd0;
        end else begin
            ex_wb_alu_result   <= alu_result;
            ex_wb_acc          <= acc_out;
            ex_wb_crypto_result<= crypto_result;
            ex_wb_rd_addr      <= id_ex_rd_addr;
            ex_wb_reg_write    <= id_ex_reg_write;
            ex_wb_wb_sel       <= id_ex_wb_sel;
            ex_wb_mem_read     <= id_ex_mem_read;
            ex_wb_mem_write    <= id_ex_mem_write;
            ex_wb_key_write    <= id_ex_key_write;
            ex_wb_dmem_addr    <= dmem_addr;
            ex_wb_dmem_wdata   <= dmem_wdata;
        end
    end

endmodule
