#!/usr/bin/env python

# This script converts registers.yaml to memory initialization files for the
# control function and profile registers

import yaml
import sys

def parse_control_fns(tree):
    control_fns = []
    for control_fn in tree:
        address = control_fn["address"]
        numeric = 0
        for _, option in control_fn["options"].iteritems():
            if "value" in option:
                val = option["value"]
            else:
                val = option["default"]
            if type(val) is bool:
                if val:
                    val = 1
                else:
                    val = 0
            bits = option["bits"]
            if type(bits) is int:
                shift = bits
            else:
                shift = bits[0]
            numeric = numeric | val << shift
        control_fns.append(address << 32 | numeric)
    return control_fns

def parse_profiles(tree):
    return [
        profile["address"] << 64 |
        profile["step"]    << 40 |
        profile["end"]     << 30 |
        profile["start"]   << 14 |
        profile["mode"]
        for profile in tree
    ]

MIF_HEADER = "width={};\n" \
        "depth={};\n" \
        "\n" \
        "address_radix=hex;\n" \
        "data_radix=hex;\n" \
        "\n" \
        "content begin\n"

MIF_FOOTER = "end;\n"

DEFAULT_FILE = "../data/ram_data.mif"

def write_mif(data, width, depth, path):
    data_len = len(data)
    if data_len == 0:
        return
    format_str = "\t{:x}: {:0" + str(width / 4) + "x};\n"

    with open(path, "w") as f:
        f.write(MIF_HEADER.format(width, depth))
        for i in range(0, depth):
            f.write(format_str.format(i, data[i]))
        f.write(MIF_FOOTER)

def main(args):
    with open("../data/registers.yaml", "r") as f:
        tree = yaml.load(f)
        control_fns = parse_control_fns(tree["control_functions"])
        write_mif(control_fns, 40, 3, "../data/control_function_data.mif")
        profiles = parse_profiles(tree["profiles"])
        write_mif(profiles, 72, 8, "../data/profile_data.mif")

if __name__ == "__main__":
    main(sys.argv)

