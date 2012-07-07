module CPU_toplevel(
	input wire clk,
	input wire[31:0] config_data,
	input wire [7:0] config_addr,
	input wire config_wren,
	output wire[7:0] LED
);

wire [31:0] PC;
assign LED = PC[9:2];

wire [31:0] Iin, Daddr, Din;
wire [1:0] DMC;
wire Dread;

instruction_rom instruction_rom_inst(
	.clock(clk),
	.address(PC[10:2]),
	.q(Iin));

config_mem	config_mem_inst (
	.clock(clk),
	// write port
	.data(config_data),
	.wraddress (config_addr),
	.wren(config_wren),
	.rdaddress(Daddr),
	.rden(DMC == 2'b00),
	.q(Din)
	);

CPU cpu_inst(
	.clk(clk),
	.reset(0),
	.Iaddr(PC),
	.Iin(Iin),
	.Daddr(Daddr),
	.Din(Din),
	.Dout(),
	.DMC(DMC));
	
endmodule
