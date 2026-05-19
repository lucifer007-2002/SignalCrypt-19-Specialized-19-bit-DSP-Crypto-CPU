module tb_mac_unit;
    reg clk = 0, rst = 1;
    reg [18:0] a_in;
    reg [17:0] b_in;
    reg        mac_en, mac_clear;
    wire [37:0] acc_out;

    always #2.5 clk = ~clk;   // 200MHz = 5ns period

    mac_unit dut (.clk(clk), .rst(rst), .a_in(a_in),
                  .b_in(b_in), .mac_en(mac_en),
                  .mac_clear(mac_clear), .acc_out(acc_out));

    initial begin
        @(posedge clk); rst = 0;

        // Test 1: MACZ 3 × 4 = 12
        a_in=19'd3; b_in=18'd4; mac_clear=1; mac_en=1;
        @(posedge clk);
        mac_clear=0;
        #1; $display("After MACZ 3x4: acc=%0d (expect 12)", acc_out);

        // Test 2: MAC 5 × 6 = 30, acc should be 12+30=42
        a_in=19'd5; b_in=18'd6; mac_en=1;
        @(posedge clk);
        #1; $display("After MAC 5x6:  acc=%0d (expect 42)", acc_out);

        // Test 3: MAC hold (mac_en=0) — acc stays 42
        mac_en=0;
        @(posedge clk);
        #1; $display("After hold:     acc=%0d (expect 42)", acc_out);

        // Test 4: Signed — (-2) × 3 = -6, then acc = 42-6 = 36
        a_in=19'h7FFFE; // -2 in 19-bit two's complement
        b_in=18'd3; mac_en=1;
        @(posedge clk);
        #1; $display("After MAC -2x3: acc=%0d (expect 36)", $signed(acc_out));

        $finish;
    end
endmodule
