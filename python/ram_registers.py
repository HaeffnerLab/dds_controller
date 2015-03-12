class Bitmask:
    """A bitmask class for setting single bits in registers
    """
    def __init__(self, label, width, shift, value=0):
        """
        generates the bitmask object
        """
        self.label = label
        self.width = width
        self.shift = shift
        self.set_value(value)

    def set_value(self, val):
        """
        Sets the value bit
        """
        assert type(val) == int
        self.value = int(val)

    def get_value(self):
        """
        Retruns the shifted value
        """
        return self.value << self.shift


auto_clr = Bitmask(label="auto_clr", width=1, shift=13, value=0)
ram_en =  Bitmask(label="ram_en", width=1, shift=31, value=1) #CHECK ??
ram_dest =  Bitmask(label="ram_dest", width=2, shift=29, value=1) #CHECK ???
"""Ram destination:
0 : Frequency
1 : Phase
2 : Amplitude
3 : Polar
"""
pdclk_en = Bitmask(label="pdclk_en", width=1, shift=11, value=0)
para_en = Bitmask(label="parallel_enable", width=1, shift=4, value=0)
para_gain = Bitmask(label="parallel_gain", width=4, shift=0, value=0)
para_hold_last = Bitmask(label="data assembler hold last", width=1, shift=6, value=0)
divider_bypass = Bitmask(label="divider_bypass", width=1, shift=15, value=0)
divider_reset = Bitmask(label="divider_reset", width=1, shift=14, value=0)

ram_mode = Bitmask(label="ram_mode", width=4, shift=0, value=3)
ram_start = Bitmask(label="ram_start", width=10, shift=14, value=0) #CHECK ??
ram_stop = Bitmask(label="ram_stop", width=10, shift=30, value=1023) # CHECK ??
ram_step = Bitmask(label="ram_step", width=16, shift=40, value=50) # CHECK ??

CFR1 = 0
CFR2 = 1
CFR3 = 2
RAM0 = 8

register_list = [CFR1,CFR2,CFR3,RAM0]

"""Format: filename, [[registers],width]"""
fn_dict = {'cfr_data.mif' : [[CFR1,CFR2,CFR3],32],
           'prof_data.mif' : [[RAM0],64]}

reg_bitmask_dict = {}

reg_bitmask_dict[CFR1] = [auto_clr, ram_en, ram_dest]
reg_bitmask_dict[CFR2] = [pdclk_en, para_en,
                          para_gain, para_hold_last]
reg_bitmask_dict[CFR3] = [divider_bypass, divider_reset]
reg_bitmask_dict[RAM0] = [ram_mode, ram_start, ram_stop, ram_step]

value_dict = {}
for register in register_list:
    value = 0
    for bitmask in reg_bitmask_dict[register]:
        value = value | bitmask.get_value()
    value_dict[register] = value

for fn in fn_dict.keys():
    print fn
    fh = open(fn,'w')
    reg_list = fn_dict[fn][0]
    width = fn_dict[fn][1]
    header = "width="+str(width+8)+"; \n"
    header += "depth=" + str(len(reg_list))
    header +=""";
address_radix=hex;
data_radix=hex;
content begin 
"""
    fh.write(header)
    rom_addr = 0
    for reg_addr in reg_list:
        val = reg_addr << width | value_dict[reg_addr]
        if width == 32:
            val_str = '%0.10X' % val
        else:
            val_str = '%0.18X' % val
        fh.write(str(rom_addr) + ' : ' + val_str + ' \n')
        print rom_addr, val_str
        rom_addr += 1
    fh.write('end;')
    fh.close()
            
