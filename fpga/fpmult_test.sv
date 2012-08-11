module fpmult_test();

// Test a saturating Q5.30 * Q1.34 multiply

    logic signed [35:0] a, b;
    wire [71:0] mulOut;
    wire [35:0] out;
    wire overflow;

    assign mulOut = a * b;
    saturate #(.IN_WIDTH(72), .HEADROOM(2), .OUT_WIDTH(36)) sat(.in(mulOut), .overflow, .out);

    task test_vec(input [35:0] _a, input [35:0] _b, input _overflow, input[35:0] _out); begin
        a <= _a; b <= _b;
        #100ps;
        if (overflow != _overflow || out != _out)
            $display("Failed: %x * %x = (%d, %x) but got (%d, %x)",
                _a, _b, _overflow, _out, overflow, _out);
        #100ps;
    end
    endtask
    
    const bit [35:0] one = {2'b01, 34'b0};
    const bit [35:0] half = {2'b00, 1'b1, 33'b0};
    const bit [35:0] minus_one = {2'b11, 34'b0};
    
    initial begin
        // x * 1
        test_vec(0, one, 0, 0);
        test_vec({1'b0, 5'b11111, 30'b0}, one, 0, {1'b0, 5'b11111, 30'b0});
        test_vec({1'b0, 5'b11111, {30{1'b1}}}, one, 0, {1'b0, 5'b11111, {30{1'b1}}});
        test_vec({1'b1, 35'b0}, one, 0, {1'b1, 35'b0});

        // x * .5
        test_vec(0, half, 0, 0);
        test_vec({1'b0, 5'b11111, 30'b0}, half, 0, {1'b0, 5'b01111, 1'b1, 29'b0});
        test_vec({1'b0, 5'b11111, {30{1'b1}}}, half, 0, {1'b0, 5'b01111, {30{1'b1}}});
        test_vec({1'b1, 35'b0}, half, 0, {1'b1, 1'b1, 34'b0});
        
        // x * -1
        test_vec(0, minus_one, 0, 0);
        test_vec({1'b0, 5'b00001, 30'b0}, minus_one, 0, {1'b1, 5'b11111, {30{1'b0}}});
    end

endmodule