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

def get_mif_header():
    return  "width=32;\n" \
            "depth=1024;\n" \
            "\n" \
            "address_radix=hex;\n" \
            "data_radix=hex;\n" \
            "\n" \
            "content begin\n"

def get_mif_footer():
    return "end;\n"

def write_mif(data, path):
    data_len = len(data)
    if data_len == 0:
        return

    with open(path, 'w') as f:
        f.write(get_mif_header())
        for i in range(0, 1024):
            f.write("\t%03x: %08x;\n" % (i, data[i]))
        f.write(get_mif_footer())

def usage():
    return 'Usage: python ram_waveform.py OUTPUT_MIF'

def main(args):
    if len(args) < 2:
        print(usage())
    else:
        write_mif(gen_data(), args[1])

if __name__ == "__main__":
    main(sys.argv)

