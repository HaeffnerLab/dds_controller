#!/usr/bin/env python

# This script writes a memory initialization file containing amplitude data
# that will populate the DDS onboard RAM.

import io
import numpy
import sys
from math import cos, pi

# Generate 14-bit amplitude data
def gen_data():
    points      = numpy.arange(0., 2. * pi, 2. * pi / 1024.)
    vals        = map(lambda x: 0.5 + 0.5 * -cos(x), points)
    scaled_vals = map(lambda y: y * (2**14 - 1), vals)
    int_vals    = map(int, scaled_vals)
    shift_vals  = map(lambda x: x << 18, int_vals)

    return shift_vals

MIF_HEADER = "width=32;\n" \
        "depth=1024;\n" \
        "\n" \
        "address_radix=hex;\n" \
        "data_radix=hex;\n" \
        "\n" \
        "content begin\n"

MIF_FOOTER = "end;\n"

DEFAULT_FILE = "../data/ram_data.mif"

USAGE = "Usage: ram_waveform.py [FILE]"

def write_mif(data, path):
    if len(data) == 0:
        return

    with open(path, 'w') as f:
        f.write(MIF_HEADER)
        for i in range(0, 1024):
            f.write("\t{:03x}: {:08x};\n".format(i, data[i]))
        f.write(MIF_FOOTER)

def main(args):
    if len(args) < 2:
        write_mif(gen_data(), DEFAULT_FILE)
    elif args[1] == "-h" or args[1] == "--help":
        print(USAGE.format(args[0]))
    else:
        write_mif(gen_data(), args[1])

if __name__ == "__main__":
    main(sys.argv)

