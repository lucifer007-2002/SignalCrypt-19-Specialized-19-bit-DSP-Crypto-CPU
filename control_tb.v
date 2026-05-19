module tb_control;
    reg  [4:0] opcode;
    wire [3:0] alu_op;
    wire       reg_write, is_mac, is_crypto, is_branch, is_halt, illegal;
    wire [1:0] wb_sel;

    control_unit dut (
        .opcode(opcode), .alu_op(alu_op),
        .reg_write(reg_write), .wb_sel(wb_sel),
        .is_mac(is_mac), .is_crypto(is_crypto),
        .is_branch(is_branch), .is_halt(is_halt),
        .illegal(illegal),
        // tie off unused
        .fmt(), .mem_read(), .mem_write(), .key_write(),
        .mac_clear(), .crypto_sel(), .is_jump(), .is_jmpr()
    );

    task check;
        input [4:0] op;
        input       exp_rw, exp_mac, exp_cry, exp_br, exp_halt;
        begin
            opcode = op; #5;
            if (reg_write !== exp_rw || is_mac !== exp_mac ||
                is_crypto !== exp_cry || is_branch !== exp_br ||
                is_halt !== exp_halt)
                $display("FAIL op=%05b rw=%b mac=%b cry=%b br=%b halt=%b",
                         op, reg_write, is_mac, is_crypto, is_branch, is_halt);
            else
                $display("PASS op=%05b", op);
        end
    endtask

    initial begin
        check(`OP_ADD,    1,0,0,0,0);   // ADD  → reg_write=1
        check(`OP_MAC,    0,1,0,0,0);   // MAC  → is_mac=1, no reg_write
        check(`OP_MACZ,   0,1,0,0,0);   // MACZ → is_mac=1
        check(`OP_LFSR,   1,0,1,0,0);   // LFSR → is_crypto=1, reg_write=1
        check(`OP_SBOX,   1,0,1,0,0);   // SBOX → is_crypto=1
        check(`OP_BEQ,    0,0,0,1,0);   // BEQ  → is_branch=1
        check(`OP_HALT,   0,0,0,0,1);   // HALT → is_halt=1
        check(`OP_NOP,    0,0,0,0,0);   // NOP  → all zero
        check(5'b10011,   0,0,0,0,0);   // RSVD → illegal only
        $finish;
    end
endmodule
