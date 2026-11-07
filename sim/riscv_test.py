"""
Cocotb verification environment for the single-cycle RV32I core (RISCV_Top).

What it does
------------
A self-contained software reference model ("Rv32iReference") executes the same
machine-code image that is loaded into the DUT's instruction memory. After every
instruction the DUT is advanced by one clock; the testbench prints a side-by-side
comparison table - one row per architectural element (PC and the 32 registers),
with the DUT value next to the reference ("model") value - and then asserts they
match. Rows are coloured GREEN when the DUT and the model agree and RED when they
differ, so a divergence is obvious at a glance.

    #007  PC=0x001C  0030F3B3  and   x7, x1, x3
      reg  | DUT        | model
      -----+------------+------------
      PC   | 0x00000020 | 0x00000020      <- green
      x0   | 0x00000000 | 0x00000000      <- green
      ...
      x7   | 0x00000060 | 0x00000060      <- green

Conventions
-----------
* Program image: one 32-bit hex word per line in "Instructions.hex".
* The image ends with a self-branch "jal x0, 0" (0x0000006F); the model treats
  that word (or an all-zero word) as the halt marker.
* `en` is held high so the core retires one instruction per rising clock edge.
"""

import os
import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer

HEX_IMAGE   = "Instructions.hex"
CLK_PERIOD  = 10            # ns
HALT_WORDS  = (0x0000006F, 0x00000000)
CYCLE_LIMIT = 5000          # safety net against a runaway PC
TRACE       = True          # set False to silence the per-instruction table
USE_COLOR   = True          # set False if your console prints raw escape codes

XLEN = 32
MASK = (1 << XLEN) - 1

GREEN = "\033[32m"
RED   = "\033[31m"
RESET = "\033[0m"


def enable_windows_ansi():
    """Best-effort: turn on ANSI/VT colour processing in a Windows console."""
    if os.name == "nt":
        try:
            import ctypes
            kernel32 = ctypes.windll.kernel32
            kernel32.SetConsoleMode(kernel32.GetStdHandle(-11), 7)
        except Exception:
            pass


def sext(value, width):
    """Sign-extend the low `width` bits of `value` to a Python int."""
    sign = 1 << (width - 1)
    return (value & (sign - 1)) - (value & sign)


def field(instr, hi, lo):
    return (instr >> lo) & ((1 << (hi - lo + 1)) - 1)


# ---------------------------------------------------------------------------
#  Disassembler (for the trace header line only)
# ---------------------------------------------------------------------------
def disasm(instr):
    if instr in HALT_WORDS:
        return "halt"
    op  = field(instr, 6, 0)
    rd  = field(instr, 11, 7)
    f3  = field(instr, 14, 12)
    rs1 = field(instr, 19, 15)
    rs2 = field(instr, 24, 20)
    f7  = field(instr, 31, 25)
    i_imm = sext(field(instr, 31, 20), 12)

    if op == 0b0110111:
        return f"lui   x{rd}, 0x{field(instr, 31, 12):05X}"
    if op == 0b0010111:
        return f"auipc x{rd}, 0x{field(instr, 31, 12):05X}"
    if op == 0b1101111:
        imm = (field(instr, 31, 31) << 20) | (field(instr, 19, 12) << 12) | \
              (field(instr, 20, 20) << 11) | (field(instr, 30, 21) << 1)
        return f"jal   x{rd}, {sext(imm, 21)}"
    if op == 0b1100111:
        return f"jalr  x{rd}, x{rs1}, {i_imm}"
    if op == 0b1100011:
        m = {0: "beq", 1: "bne", 4: "blt", 5: "bge", 6: "bltu", 7: "bgeu"}.get(f3, "b???")
        imm = (field(instr, 31, 31) << 12) | (field(instr, 7, 7) << 11) | \
              (field(instr, 30, 25) << 5) | (field(instr, 11, 8) << 1)
        return f"{m:5s} x{rs1}, x{rs2}, {sext(imm, 13)}"
    if op == 0b0000011:
        m = {0: "lb", 1: "lh", 2: "lw", 4: "lbu", 5: "lhu"}.get(f3, "l??")
        return f"{m:5s} x{rd}, {i_imm}(x{rs1})"
    if op == 0b0100011:
        m = {0: "sb", 1: "sh", 2: "sw"}.get(f3, "s??")
        imm = (field(instr, 31, 25) << 5) | field(instr, 11, 7)
        return f"{m:5s} x{rs2}, {sext(imm, 12)}(x{rs1})"
    if op == 0b0010011:
        if f3 == 1:
            return f"slli  x{rd}, x{rs1}, {field(instr, 24, 20)}"
        if f3 == 5:
            return f"{'srai' if f7 == 0x20 else 'srli'}  x{rd}, x{rs1}, {field(instr, 24, 20)}"
        m = {0: "addi", 2: "slti", 3: "sltiu", 4: "xori", 6: "ori", 7: "andi"}.get(f3, "???i")
        return f"{m:5s} x{rd}, x{rs1}, {i_imm}"
    if op == 0b0110011:
        if f3 == 0 and f7 == 0x20:
            name = "sub"
        elif f3 == 5 and f7 == 0x20:
            name = "sra"
        else:
            name = {0: "add", 1: "sll", 2: "slt", 3: "sltu",
                    4: "xor", 5: "srl", 6: "or", 7: "and"}.get(f3, "op?")
        return f"{name:5s} x{rd}, x{rs1}, x{rs2}"
    return "(unknown)"


# ---------------------------------------------------------------------------
#  Reference model
# ---------------------------------------------------------------------------
class Rv32iReference:
    """A minimal, instruction-accurate RV32I executor used as the oracle."""

    def __init__(self, image):
        self.image = image
        self.pc = 0
        self.x = [0] * 32
        self.byte = {}                  # address -> 0..255

    def put(self, rd, value):
        if rd != 0:
            self.x[rd] = value & MASK

    def signed(self, r):
        return sext(self.x[r], XLEN)

    def read(self, addr, nbytes):
        v = 0
        for k in range(nbytes):
            v |= self.byte.get((addr + k) & MASK, 0) << (8 * k)
        return v

    def write(self, addr, nbytes, value):
        for k in range(nbytes):
            self.byte[(addr + k) & MASK] = (value >> (8 * k)) & 0xFF

    def fetched(self):
        idx = self.pc >> 2
        if idx >= len(self.image):
            return None
        return self.image[idx]

    def retire(self):
        """Execute the instruction at PC. Returns False at the halt marker."""
        instr = self.fetched()
        if instr is None or instr in HALT_WORDS:
            return False

        opcode = field(instr, 6, 0)
        rd     = field(instr, 11, 7)
        f3     = field(instr, 14, 12)
        rs1    = field(instr, 19, 15)
        rs2    = field(instr, 24, 20)
        f7     = field(instr, 31, 25)
        a, b   = self.x[rs1], self.x[rs2]
        nxt    = self.pc + 4

        if opcode == 0b0110011:                       # OP (register/register)
            shamt = b & 0x1F
            table = {
                (0x0, 0x00): (a + b) & MASK,
                (0x0, 0x20): (a - b) & MASK,
                (0x1, 0x00): (a << shamt) & MASK,
                (0x2, 0x00): 1 if self.signed(rs1) < self.signed(rs2) else 0,
                (0x3, 0x00): 1 if a < b else 0,
                (0x4, 0x00): a ^ b,
                (0x5, 0x00): a >> shamt,
                (0x5, 0x20): (sext(a, XLEN) >> shamt) & MASK,
                (0x6, 0x00): a | b,
                (0x7, 0x00): a & b,
            }
            self.put(rd, table[(f3, f7)])

        elif opcode == 0b0010011:                     # OP-IMM
            imm = sext(field(instr, 31, 20), 12)
            shamt = field(instr, 24, 20)
            if f3 == 0x0:
                self.put(rd, (a + imm) & MASK)
            elif f3 == 0x2:
                self.put(rd, 1 if self.signed(rs1) < imm else 0)
            elif f3 == 0x3:
                self.put(rd, 1 if a < (imm & MASK) else 0)
            elif f3 == 0x4:
                self.put(rd, a ^ (imm & MASK))
            elif f3 == 0x6:
                self.put(rd, a | (imm & MASK))
            elif f3 == 0x7:
                self.put(rd, a & (imm & MASK))
            elif f3 == 0x1:
                self.put(rd, (a << shamt) & MASK)
            elif f3 == 0x5:
                self.put(rd, ((sext(a, XLEN) >> shamt) if f7 == 0x20 else a >> shamt) & MASK)

        elif opcode == 0b0000011:                     # LOAD
            addr = (a + sext(field(instr, 31, 20), 12)) & MASK
            if f3 == 0x0:
                self.put(rd, sext(self.read(addr, 1), 8) & MASK)
            elif f3 == 0x1:
                self.put(rd, sext(self.read(addr, 2), 16) & MASK)
            elif f3 == 0x2:
                self.put(rd, self.read(addr, 4))
            elif f3 == 0x4:
                self.put(rd, self.read(addr, 1))
            elif f3 == 0x5:
                self.put(rd, self.read(addr, 2))

        elif opcode == 0b0100011:                     # STORE
            imm = (field(instr, 31, 25) << 5) | field(instr, 11, 7)
            addr = (a + sext(imm, 12)) & MASK
            self.write(addr, {0x0: 1, 0x1: 2, 0x2: 4}[f3], b)

        elif opcode == 0b1100011:                     # BRANCH
            imm = (field(instr, 31, 31) << 12) | (field(instr, 7, 7) << 11) | \
                  (field(instr, 30, 25) << 5) | (field(instr, 11, 8) << 1)
            imm = sext(imm, 13)
            take = {
                0x0: a == b,
                0x1: a != b,
                0x4: self.signed(rs1) < self.signed(rs2),
                0x5: self.signed(rs1) >= self.signed(rs2),
                0x6: a < b,
                0x7: a >= b,
            }[f3]
            if take:
                nxt = self.pc + imm

        elif opcode == 0b1101111:                     # JAL
            imm = (field(instr, 31, 31) << 20) | (field(instr, 19, 12) << 12) | \
                  (field(instr, 20, 20) << 11) | (field(instr, 30, 21) << 1)
            self.put(rd, self.pc + 4)
            nxt = self.pc + sext(imm, 21)

        elif opcode == 0b1100111:                     # JALR
            imm = sext(field(instr, 31, 20), 12)
            self.put(rd, self.pc + 4)
            nxt = (a + imm) & ~1

        elif opcode == 0b0110111:                     # LUI
            self.put(rd, instr & 0xFFFFF000)

        elif opcode == 0b0010111:                     # AUIPC
            self.put(rd, (self.pc + (instr & 0xFFFFF000)) & MASK)

        else:
            raise AssertionError(f"reference model: unsupported opcode {opcode:#09b}")

        self.pc = nxt & MASK
        return True


# ---------------------------------------------------------------------------
#  Helpers
# ---------------------------------------------------------------------------
def load_image(path):
    words = []
    with open(path) as fh:
        for line in fh:
            tok = line.strip()
            if tok:
                words.append(int(tok, 16) & MASK)
    return words


def read_dut_registers(dut):
    # The register file stores x1..x31 in `registers[31:1]`; x0 is hardwired 0.
    regs = [0] * 32
    for i in range(1, 32):
        regs[i] = int(dut.datapath.reg_file.registers[i].value)
    return regs


def render_row(name, dut_val, model_val, touched, is_pc=False, pc_can_green=False):
    """Colour rule:
      * data register: green on match / red on mismatch only if it changed this
        cycle; otherwise white.
      * PC: normally white (red on mismatch). When `pc_can_green` is set - i.e.
        a branch whose only architectural effect is the PC - it goes green on
        match (red on mismatch)."""
    text = f"  {name:<4} | 0x{dut_val:08X} | 0x{model_val:08X}"
    ok = (dut_val == model_val)
    if is_pc:
        colour = (GREEN if ok else RED) if pc_can_green else (None if ok else RED)
    else:
        colour = (GREEN if ok else RED) if touched else None
    if colour and USE_COLOR:
        return colour + text + RESET
    return text


def is_branch(instr):
    return field(instr, 6, 0) == 0b1100011


def format_table(step, cur_pc, instr, dut_pc, dut_regs, ref, prev_dut, prev_model):
    """Per-instruction table. Only the register(s) that changed this cycle are
    coloured (green=match, red=mismatch); everything else stays white. PC is
    white unless it diverges - except for a branch whose only change is the PC,
    where a matching PC is shown green."""
    touched = [(dut_regs[i] != prev_dut[i]) or (ref.x[i] != prev_model[i])
               for i in range(32)]
    pc_can_green = is_branch(instr) and not any(touched)

    out = [f"#{step:03d}  PC=0x{cur_pc:04X}  {instr:08X}  {disasm(instr)}"]
    out.append(f"  {'reg':<4} | {'DUT':<10} | {'model':<10}")
    out.append(f"  {'-'*4}-+-{'-'*10}-+-{'-'*10}")
    out.append(render_row("PC", dut_pc, ref.pc, touched=False,
                          is_pc=True, pc_can_green=pc_can_green))
    for i in range(32):
        out.append(render_row(f"x{i}", dut_regs[i], ref.x[i], touched[i]))
    return "\n".join(out)


def collect_mismatches(regs, dut_pc, ref):
    diffs = []
    if dut_pc != ref.pc:
        diffs.append(("PC", ref.pc, dut_pc))
    for i in range(1, 32):
        if regs[i] != ref.x[i]:
            diffs.append((f"x{i}", ref.x[i], regs[i]))
    return diffs


# ---------------------------------------------------------------------------
#  Test
# ---------------------------------------------------------------------------
@cocotb.test()
async def riscv_single_cycle_test(dut):
    enable_windows_ansi()

    image = load_image(HEX_IMAGE)
    ref = Rv32iReference(image)

    cocotb.start_soon(Clock(dut.clk, CLK_PERIOD, unit="ns").start())

    # Synchronous reset: one edge with reset asserted clears PC and the regfile.
    dut.en.value = 1
    dut.reset.value = 1
    dut.debug_reg_select.value = 0
    dut.ACL_MISO.value = 0
    await RisingEdge(dut.clk)
    dut.reset.value = 0
    await Timer(1, "ns")

    dut._log.info("Per-instruction comparison: column 'DUT' vs column 'model' "
                  "(green = match, red = mismatch)")

    prev_dut = [0] * 32                  # DUT register state from the previous cycle
    prev_model = [0] * 32                # model register state from the previous cycle

    retired = 0
    while True:
        cur_pc = ref.pc
        instr = ref.fetched()
        if not ref.retire():            # halt marker reached
            break

        await RisingEdge(dut.clk)        # DUT commits the same instruction
        await Timer(1, "ns")             # let non-blocking updates settle

        regs = read_dut_registers(dut)
        dut_pc = int(dut.PC.value)

        if TRACE:
            print(format_table(retired, cur_pc, instr, dut_pc, regs, ref,
                               prev_dut, prev_model), flush=True)

        diffs = collect_mismatches(regs, dut_pc, ref)
        if diffs:
            report = "\n".join(
                f"  {name:>4}: expected {exp:#010x}, DUT {got:#010x}"
                for name, exp, got in diffs)
            raise AssertionError(
                f"State mismatch after instruction #{retired} "
                f"(executed at PC {cur_pc:#06x}):\n{report}")

        prev_dut = regs
        prev_model = list(ref.x)
        retired += 1
        assert retired < CYCLE_LIMIT, "instruction limit hit - missing halt marker?"

    dut._log.info("Reference and DUT agreed for all %d retired instructions; "
                  "final PC = %#06x", retired, ref.pc)
