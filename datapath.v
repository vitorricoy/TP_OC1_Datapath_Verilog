module fetch (input takebranch, rst, clk, branch, input [31:0] sigext, output [31:0] inst);
  
  wire [31:0] pc, pc_4, new_pc;

  assign pc_4 = 4 + pc; // pc+4  Adder
  assign new_pc = (branch & takebranch) ? pc_4 + sigext : pc_4; // new PC Mux

  PC program_counter(new_pc, clk, rst, pc);

  reg [31:0] inst_mem [0:31];

  assign inst = inst_mem[pc[31:2]];

  initial begin
    // Instruções usadas para testar as instruções na implementação
    inst_mem[0] <= 32'h00000000; // nop
    inst_mem[1] <= 32'b00000000000100110110010000010011; // ori x8, x6, 1 ok
    inst_mem[2] <= 32'b00000000010000011001000110010011; // slli x3, x3, 4 ok
    inst_mem[3] <= 32'b00000000000000000100001100110111; // lui x6, 16384 ok
    inst_mem[4] <= 32'b00000000101001100000000110000111; // lwi x3, x6, x10 ok
    inst_mem[5] <= 32'b00000000110001001000000001010100; // swap x9, x12 ok
    inst_mem[6] <= 32'b00000000010000101000011000100111; // ss x12, x5, 4 ok
    //inst_mem[7] <= 32'b11111110000100000100110011100011; // blt x0, x1, -8
    //inst_mem[7] <= 32'b11111110000000001101110011100011; // bge x1, x0, -8 ok
    inst_mem[7] <= 32'b11111111100111111111000001101111; //jump -8 ok
  end
  
endmodule

module PC (input [31:0] pc_in, input clk, rst, output reg [31:0] pc_out);

  always @(posedge clk) begin
    pc_out <= pc_in;
    if (~rst)
      pc_out <= 0;
  end

endmodule

module decode (input [31:0] inst, writedata, writedata2, input clk, output [31:0] data1, data2, ImmGen, output alusrc, memread, memwrite, memtoreg, branch, jump, regaddress, output [1:0] aluop, output [9:0] funct);
  
  wire branch, jump, regaddress, memread, memtoreg, MemWrite, alusrc, regwrite, regwrite2;
  wire [1:0] aluop; 
  wire [4:0] writereg, rs1, rs2, rd;
  wire [6:0] opcode;
  wire [9:0] funct;
  wire [31:0] ImmGen;

  assign opcode = inst[6:0];
  assign rs1    = inst[19:15];
  assign rs2    = (regaddress) ? inst[11:7] : inst[24:20];
  assign rd     = inst[11:7];
  assign funct = {inst[31:25],inst[14:12]};

  ControlUnit control (opcode, inst, alusrc, memtoreg, regwrite, regwrite2, memread, memwrite, branch, jump, regaddress, aluop, ImmGen);
  
  Register_Bank Registers (clk, regwrite, regwrite2, rs1, rs2, rd, writedata, writedata2, data1, data2); 

endmodule

module ControlUnit (input [6:0] opcode, input [31:0] inst, output reg alusrc, memtoreg, regwrite, regwrite2, memread, memwrite, branch, jump, regaddress, output reg [1:0] aluop, output reg [31:0] ImmGen);

  always @(opcode) begin
    alusrc   <= 0;
    memtoreg <= 0;
    regwrite <= 0;
    regwrite2 <=0;
    memread  <= 0;
    memwrite <= 0;
    branch   <= 0;
    aluop    <= 0;
    ImmGen   <= 0; 
    jump <= 0;
    regaddress <= 0;
    case(opcode) 
      7'b0110011: begin // R type == 51
        regwrite <= 1;
        aluop    <= 2;
	  end
	  7'b1100011: begin // beq, blt, bge == 99
        branch   <= 1;
        aluop    <= 1;
        ImmGen   <= {{19{inst[31]}},inst[31],inst[7],inst[30:25],inst[11:8],1'b0};
	  end
	  7'b0010011: begin // addi, slli, ori == 19
        alusrc   <= 1;
        regwrite <= 1;
        aluop    <= 2;
        ImmGen   <= {{20{inst[31]}},inst[31:20]};
      end
	  7'b0000011: begin // lw == 3
        alusrc   <= 1;
        memtoreg <= 1;
        regwrite <= 1;
        memread  <= 1;
        ImmGen   <= {{20{inst[31]}},inst[31:20]};
      end
	  7'b0100011: begin // sw == 35
        alusrc   <= 1;
        memwrite <= 1;
        ImmGen   <= {{20{inst[31]}},inst[31:25],inst[11:7]};
      end
      7'b0000111: begin //lwi == 7
        memtoreg <= 1;
        regwrite <= 1;
        memread  <= 1;
      end
      7'b1010100: begin //swap == 84
        regwrite <= 1;
        regwrite2 <= 1;
        aluop <= 3;
      end
      7'b0110111: begin //lui == 55
        aluop <= 3; 
        alusrc <= 1;
        regwrite <= 1;
        ImmGen <= {inst[31:12], {12{inst[3]}}};        
      end
      7'b1101111: begin //jump == 111
        ImmGen <= {{12{inst[31]}}, inst[19:12], inst[20], inst[30:21], 1'b0} - 32'd4; //Corrige o offset para ficar equivalente ao offset de um branch
        branch <= 1;
        jump <= 1;
      end
      7'b0100111: begin //ss == 39
        memwrite <= 1;
        ImmGen <= {{20{inst[31]}},inst[31:20]};
        alusrc <= 1;
        aluop <= 2;
        regaddress <= 1;
      end
    endcase
  end

endmodule 

module Register_Bank (input clk, regwrite, regwrite2, input [4:0] read_reg1, read_reg2, writereg, input [31:0] writedata, writedata2, output [31:0] read_data1, read_data2);

  integer i;
  reg [31:0] memory [0:31]; // 32 registers de 32 bits cada

  // fill the memory
  initial begin
    for (i = 0; i <= 31; i++) 
      memory[i] <= i;
  end

  assign read_data1 = memory[read_reg1];
  assign read_data2 = memory[read_reg2];
	
  always @(posedge clk) begin 
    if (regwrite & !regwrite2)
      memory[writereg] <= writedata;
    if (regwrite & regwrite2) begin
      memory[read_reg1] <= writedata;
      memory[read_reg2] <= writedata2;
    end
  end
  
endmodule

module execute (input [31:0] in1, in2, ImmGen, input alusrc, input [1:0] aluop, input [9:0] funct, output takebranch, output [31:0] aluout, input jump);

  wire [31:0] alu_B;
  wire [3:0] aluctrl;
  wire [2:0] brchop;
  
  assign alu_B = (alusrc) ? ImmGen : in2 ;

  //Unidade Lógico Aritimética
  ALU alu (aluctrl, brchop, in1, alu_B, aluout, takebranch);

  alucontrol alucontrol (aluop, funct, aluctrl, brchop, alusrc, jump);

endmodule

module alucontrol (input [1:0] aluop, input [9:0] funct, output reg [3:0] alucontrol, output reg [2:0] branchop, input alusrc, jump);
  
  wire [7:0] funct7;
  wire [2:0] funct3;

  assign funct3 = funct[2:0];
  assign funct7 = funct[9:3];

  always @(funct) begin
    case (jump)
      1: branchop <= 3'd3; // JUMP
      default: begin
        case (funct3)
          0: branchop <= 3'd0; // BEQ
          4: branchop <= 3'd1; // BLT
          5: branchop <= 3'd2; // BGE
          default: branchop <= 3'd7; // Nop
        endcase
      end
    endcase  
  end

  always @(aluop) begin
    case (aluop)
      0: alucontrol <= 4'd2; // ADD to SW and LW
      1: alucontrol <= 4'd6; // SUB to branch
      3: alucontrol <= 4'd3; // B goes through ALU
      default: begin
        case (funct3)
          0: alucontrol <= (funct7 == 0 || alusrc == 1) ? /*ADD*/ 4'd2 : /*SUB*/ 4'd6; 
          1: alucontrol <= 4'd4; //SLL
          2: alucontrol <= 4'd7; // SLT
          6: alucontrol <= 4'd1; // OR
          7: alucontrol <= 4'd0; // AND
          default: alucontrol <= 4'd15; // Nop
        endcase
      end
    endcase
  end
endmodule

module ALU (input [3:0] alucontrol, input [2:0] branchop, input [31:0] A, B, output reg [31:0] aluout, output takebranch);
  
  always @(branchop, A, B) begin
    case(branchop)
      0: takebranch <= (A == B); // BEQ
      1: takebranch <= (A < B); // BLT
      2: takebranch <= (A >= B); // BGE
      3: takebranch <= 1; // JUMP
      default: takebranch <= 0; // Nop
    endcase
  end

  always @(alucontrol, A, B) begin
      case (alucontrol)
        0: aluout <= A & B; // AND
        1: aluout <= A | B; // OR
        2: aluout <= A + B; // ADD
        3: aluout <= B;   // B passa direto
        4: aluout <= A << B; // SLL
        6: aluout <= A - B; // SUB
      default: aluout <= 0; //default 0, Nada acontece;
    endcase
  end
endmodule

module memory (input [31:0] aluout, data2, input memread, memwrite, clk, regaddress, output [31:0] readdata);

  integer i;
  reg [31:0] memory [0:127]; 
  
  // fill the memory
  initial begin
    for (i = 0; i <= 127; i++) 
      memory[i] <= i;
  end

  assign readdata = (memread) ? memory[aluout[31:2]] : 0;

  always @(posedge clk) begin
    if (memwrite & !regaddress)
      memory[aluout[31:2]] <= data2;
    if (memwrite & regaddress)
      memory[data2[31:2]] <= aluout;
	end
endmodule

module writeback (input [31:0] aluout, readdata, data1, input memtoreg, output reg [31:0] write_data, write_data2);
  always @(memtoreg) begin
    write_data <= (memtoreg) ? readdata : aluout;
    write_data2 <= data1;
  end
endmodule

// TOP -------------------------------------------
module mips (input clk, rst, output [31:0] writedata, writedata2);
  
  wire [31:0] inst, sigext, data1, data2, aluout, readdata;
  wire takebranch, memread, memwrite, memtoreg, branch, alusrc, jump, regaddress;
  wire [9:0] funct;
  wire [1:0] aluop;
  
  // FETCH STAGE
  fetch fetch (takebranch, rst, clk, branch, sigext, inst);
  
  // DECODE STAGE
  decode decode (inst, writedata, writedata2, clk, data1, data2, sigext, alusrc, memread, memwrite, memtoreg, branch, jump, regaddress, aluop, funct);   
  
  // EXECUTE STAGE
  execute execute (data1, data2, sigext, alusrc, aluop, funct, takebranch, aluout, jump);

  // MEMORY STAGE
  memory memory (aluout, data2, memread, memwrite, clk, regaddress, readdata);

  // WRITEBACK STAGE
  writeback writeback (aluout, readdata, data1, memtoreg, writedata, writedata2);

endmodule