import struct
import re
import argparse
import os

def main():
    # Set up argument parser
    parser = argparse.ArgumentParser(description="Convert COE file to raw binary (BIN) file.")
    parser.add_argument("input_file", help="Path to the input .coe file (e.g., ./test/irom.coe)")
    parser.add_argument("output_dir", help="Directory to save the output .bin file (e.g., ./bin)")
    
    args = parser.parse_args()
    input_file = args.input_file
    output_dir = args.output_dir

    # Check if input file exists
    if not os.path.isfile(input_file):
        print(f"Error: Input file '{input_file}' does not exist.")
        return

    # Create output directory if it doesn't exist
    os.makedirs(output_dir, exist_ok=True)

    # Extract base filename and change extension to .bin (e.g., 'irom.coe' -> 'irom.bin')
    base_name = os.path.splitext(os.path.basename(input_file))[0]
    output_file = os.path.join(output_dir, f"{base_name}.bin")

    # Read the COE file
    with open(input_file, 'r') as f:
        lines = f.readlines()

    # Filter out comments and header info, extract pure hexadecimal numbers
    hex_data = []
    for line in lines:
        line = line.strip()
        # Ignore header info like memory_initialization_radix, etc.
        if line.startswith('memory') or line == '':
            continue
        
        # Remove commas or semicolons at the end of the line
        line = re.sub(r'[,;]', '', line)
        if line:
             hex_data.append(line)

    # Pack the hex strings into a binary file and write
    with open(output_file, 'wb') as f:
        for hex_str in hex_data:
            # Convert the 8-character hex string to an integer
            val = int(hex_str, 16)
            # '<I' represents a Little-Endian 32-bit unsigned integer
            binary_data = struct.pack('<I', val)
            f.write(binary_data)

    print(f"Conversion successful! Converted a total of {len(hex_data)} instructions.")
    print(f"Saved as: {output_file}")

if __name__ == "__main__":
    main()
