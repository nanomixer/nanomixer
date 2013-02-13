import bitstring
import re

opcodes = {0:'Nop',
           1:'Mul',
           2:'Mac',
           3:'RotMac',
           4:'Store',
           5:'In',
           6:'Out',
           7:'Spin'}

class Instruction(object):
    def __init__(self, opcode='Nop', sample_addr=0, param_or_io_addr=0):
        self.opcode = opcode
        self.sample_addr = sample_addr
        self.param_or_io_addr = param_or_io_addr
    def __repr__(self):
        return '{}({}, {})'.format(self.opcode, self.sample_addr, self.param_or_io_addr)

def simulate():
    decoded_instr   = Instruction()
    read_instr      = Instruction()
    ex1_instr       = Instruction()
    ex2_instr       = Instruction()
    writeback_instr = Instruction()

    with open('instr.mif', 'r') as f:
        machine_code = re.findall('[0-9a-fA-F]+\s*:\s*([0,1]+)', f.read())

    for machine_word in machine_code:
        # Decode binary machine words:
        opcode           = opcodes[bitstring.BitArray(bin=machine_word[0:6]).int]
        sample_addr      = bitstring.BitArray(bin=machine_word[6:16] ).int
        param_or_io_addr = bitstring.BitArray(bin=machine_word[16:26]).int
        
        # Update instruction pipeline:
        writeback_instr = ex2_instr
        ex2_instr = ex1_instr
        ex1_instr = read_instr
        read_instr = decoded_instr
        decoded_instr = Instruction(opcode, sample_addr, param_or_io_addr)
        
        print 'Pipeline: {}\t{}\t{}\t{}\t{}'.format(decoded_instr,
                                                    read_instr, 
                                                    ex1_instr, 
                                                    ex2_instr, 
                                                    writeback_instr)
    print "Program length:", len(machine_code)

if __name__ == '__main__':
    simulate()
        
