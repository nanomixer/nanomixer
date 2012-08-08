module saturate_test();

    logic [35:0] in;
    wire clip;
    wire [23:0] out;
    saturate sat(.in, .overflow(clip), .out);

    task test_vec(input [35:0] _in, input _clip, input[23:0] _out); begin
        in <= _in;
        #10ps;
        if (clip != _clip || out != _out)
            $display("Failed vector %x, ref (%d, %x), actual (%d, %x)",
                _in, _clip, _out, clip, out);
        #10ps;
    end
    endtask
    initial begin
        // non-overflowing
        test_vec(12<<6, 0, 12);
        test_vec({36{1'b1}}, 0, {24{1'b1}});
        test_vec({{7{1'b0}}, {29{1'b1}}}, 0, {1'b0, {23{1'b1}}}); // should be largest before clipping
        test_vec({{7{1'b1}}, {29{1'b0}}}, 0, {1'b1, {23{1'b0}}}); // should be smallest before clipping

        test_vec({1'b0, {35{1'b1}}}, 1, {1'b0, {23{1'b1}}}); // clips, but positive.
        test_vec({{5{1'b1}}, {31{1'b0}}}, 1, {1'b1, {23{1'b0}}}); // clips, negative.
    end

endmodule
