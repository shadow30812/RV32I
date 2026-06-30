import sys

# RV32I Instruction Encodings
OPCODES = {
    "add": ("0110011", "000", "0000000", "R"),
    "sub": ("0110011", "000", "0100000", "R"),
    "and": ("0110011", "111", "0000000", "R"),
    "or": ("0110011", "110", "0000000", "R"),
    "xor": ("0110011", "100", "0000000", "R"),
    "slt": ("0110011", "010", "0000000", "R"),
    "addi": ("0010011", "000", None, "I"),
    "andi": ("0010011", "111", None, "I"),
    "ori": ("0010011", "110", None, "I"),
    "xori": ("0010011", "100", None, "I"),
    "slti": ("0010011", "010", None, "I"),
    "lw": ("0000011", "010", None, "I_mem"),
    "sw": ("0100011", "010", None, "S"),
    "beq": ("1100011", "000", None, "B"),
    "bne": ("1100011", "001", None, "B"),
    "blt": ("1100011", "100", None, "B"),
    "bge": ("1100011", "101", None, "B"),
    "jal": ("1101111", None, None, "J"),
    "lui": ("0110111", None, None, "U"),
}


def to_bin(val, bits):
    """Convert integer to two's complement binary string of given length."""
    if val < 0:
        val = (1 << bits) + val
    return format(val, f"0{bits}b")


def parse_reg(reg_str):
    """Extract integer from register string (e.g., 'x13' -> 13)."""
    return to_bin(int(reg_str.replace("x", "").replace(",", "")), 5)


def assemble(input_file, output_file):
    with open(input_file, "r") as f:
        lines = f.readlines()

    # Pass 1: Strip comments, whitespace, and record labels
    instructions = []
    labels = {}
    pc = 0

    for line in lines:
        line = line.split("//")[0].strip()
        if not line:
            continue
        if line.endswith(":"):
            labels[line[:-1]] = pc
        else:
            # Clean up commas and brackets for easier splitting
            line = line.replace(",", " ").replace("(", " ").replace(")", " ")
            parts = [p for p in line.split() if p]
            instructions.append((pc, parts))
            pc += 4

    # Pass 2: Encode instructions
    machine_code = []
    for pc, parts in instructions:
        inst = parts[0].lower()
        if inst not in OPCODES:
            raise ValueError(f"Unknown instruction: {inst}")

        binary = 0
        opcode, funct3, funct7, fmt = OPCODES[inst]

        try:
            if fmt == "R":
                rd = parse_reg(parts[1])
                rs1 = parse_reg(parts[2])
                rs2 = parse_reg(parts[3])
                binary = funct7 + rs2 + rs1 + funct3 + rd + opcode

            elif fmt == "I":
                rd = parse_reg(parts[1])
                rs1 = parse_reg(parts[2])
                # Handle hex or decimal immediates
                imm_val = (
                    int(parts[3], 16) if parts[3].startswith("0x") else int(parts[3])
                )
                imm = to_bin(imm_val, 12)
                binary = imm + rs1 + funct3 + rd + opcode

            elif fmt == "I_mem":  # lw x14, 0(x13)
                rd = parse_reg(parts[1])
                imm_val = (
                    int(parts[2], 16) if parts[2].startswith("0x") else int(parts[2])
                )
                rs1 = parse_reg(parts[3])
                imm = to_bin(imm_val, 12)
                binary = imm + rs1 + funct3 + rd + opcode

            elif fmt == "S":  # sw x10, 0(x13)
                rs2 = parse_reg(parts[1])
                imm_val = (
                    int(parts[2], 16) if parts[2].startswith("0x") else int(parts[2])
                )
                rs1 = parse_reg(parts[3])
                imm = to_bin(imm_val, 12)
                binary = imm[0:7] + rs2 + rs1 + funct3 + imm[7:12] + opcode

            elif fmt == "B":
                rs1 = parse_reg(parts[1])
                rs2 = parse_reg(parts[2])
                target = labels[parts[3]] if parts[3] in labels else int(parts[3])
                offset = target - pc
                imm = to_bin(offset, 13)
                # B-type immediate scrambling: imm[12|10:5|4:1|11]
                binary = (
                    imm[0] + imm[2:8] + rs2 + rs1 + funct3 + imm[8:12] + imm[1] + opcode
                )

            elif fmt == "J":
                rd = parse_reg(parts[1])
                target = labels[parts[2]] if parts[2] in labels else int(parts[2])
                offset = target - pc
                imm = to_bin(offset, 21)
                # J-type immediate scrambling: imm[20|10:1|11|19:12]
                binary = imm[0] + imm[10:20] + imm[9] + imm[1:9] + rd + opcode

            elif fmt == "U":
                rd = parse_reg(parts[1])
                imm_val = (
                    int(parts[2], 16) if parts[2].startswith("0x") else int(parts[2])
                )
                imm = to_bin(imm_val, 20)
                binary = imm + rd + opcode

            # Convert 32-bit binary string to 8-character hex
            hex_str = f"{int(binary, 2):08X}"
            machine_code.append(hex_str)

        except Exception as e:
            print(f"Error parsing instruction at PC {pc}: {' '.join(parts)}")
            raise e

    # Write to output
    with open(output_file, "w") as f:
        for hex_code in machine_code:
            f.write(hex_code + "\n")
    print(f"Successfully assembled {len(machine_code)} instructions to {output_file}")


if __name__ == "__main__":
    if len(sys.argv) != 3:
        print(
            "Usage: python assembler.py <input.s> <output.hex>\n\nContinue with default?: [Y/n]"
        )
        choice = input().strip().lower()
        if choice != "n":
            assemble("imem.s", "imem.hex")

    else:
        assemble(sys.argv[1], sys.argv[2])
