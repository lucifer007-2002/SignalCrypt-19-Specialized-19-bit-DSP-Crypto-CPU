
# SignalCrypt-19

A custom 19-bit ISA soft-core CPU implemented in Verilog, targeting the Xilinx AC701 evaluation board (XC7A200T-2FBG676, Artix-7 speed grade -2). Built from scratch — no standard ISA borrowed. Every instruction encoding, pipeline stage, and timing decision is original and documented below.

---

## What This Is

SignalCrypt-19 is a 4-stage pipelined processor (IF / ID / EX / WB) designed specifically for DSP-intensive and lightweight cryptographic workloads. The two core goals were:

1. Map a multiply-accumulate instruction to Xilinx DSP48E1 silicon tiles through RTL inference — not IP instantiation
2. Achieve 200MHz timing closure on Artix-7 speed grade -2

Both were met. Final WNS = +0.142ns, TNS = 0.

---

## Why 19-Bit

The instruction width is deliberately non-power-of-two. With 19 bits: a 5-bit opcode gives 32 instruction slots, two 4-bit register specifiers cover 16 GPRs (saving 2 bits per specifier vs. 32-register designs), and the remaining bits form either a 6-bit immediate (R-type) or a 10-bit immediate (I/B-type, where the rs2 field folds into the immediate). Every field width has a hardware cost justification — this is not an arbitrary choice.

---

## ISA

32 opcodes across 3 instruction formats. Fully locked before any RTL was written and never changed.

**Instruction classes:**
- ALU register-register: ADD, SUB, AND, OR, XOR, SHL, SHR, NOT
- ALU immediate: ADDI, ANDI, ORI, XORI, SHLI, SHRI, MOVI
- Memory: LD, ST, LDK (load to key register)
- Branch / Jump: BEQ, BNE, BLT, JMP, JMPR (indirect)
- MAC / DSP: MAC (accumulate), MACZ (clear then accumulate), RDACC (read accumulator)
- Crypto: LFSR, SBOX, KEYXOR
- Special: NOP, HALT

All instructions are 19 bits. PC is word-addressed and increments by 1 — no byte addressing. LD and LDK have a visible 1-cycle latency by ISA contract; the programmer inserts a NOP after them.

---

## Pipeline

4 stages: IF fetches from a 19-bit instruction BRAM. ID decodes the instruction, reads the register file, and generates the sign-extended immediate. EX runs the ALU, MAC unit, and crypto units in parallel, then selects the correct result. WB writes back to the register file from one of four sources: ALU result, memory read data, accumulator, or crypto output.

4 stages instead of 5 because the load-use hazard is handled by ISA contract (NOP after LD), eliminating the need for a dedicated MEM stage. Fewer pipeline stages means fewer forwarding cases and more timing budget for the EX stage where the DSP48 path lives.

Branch resolution was initially combinational (EX output directly to IF stage PC mux). This caused the worst timing violation — ~1.8ns of routing delay across pipeline boundaries. Fix: registered branch_taken and branch_target into the EX/WB pipeline register, making it a pure FF-to-FF path. Branch penalty increased from 2 to 3 cycles, which is acceptable for a custom ISA.

---

## DSP48E1 MAC Unit

The MAC instruction computes `ACC = ACC + (rs1 × rs2)`. The critical requirement is that Vivado infers the Xilinx DSP48E1 tile for this operation rather than synthesizing a LUT-based multiplier (which would consume ~57 LUT6s and add 6–8 logic levels — immediate 200MHz failure).

Inference requires: registered inputs (the ID/EX pipeline register serves as the input register — no additional register between it and the MAC module), the `(* use_dsp = "yes" *)` attribute on the accumulator register, and an accumulate pattern Vivado recognises.

The accumulator uses a 2-stage internal pipeline (multiply stage → accumulate stage, mapping to DSP48 MREG and PREG). This keeps the DSP48 P-to-C feedback path inside the silicon tile (~0.1ns) rather than routing externally (~4.6ns). Cost is 2-cycle MAC latency, handled by the same NOP contract as LD.

The DSP48E1 B port is 18 bits. By ISA convention, the rs2 operand in MAC/MACZ is treated as 18-bit signed. The MSB of rs2 is dropped at the connection point in ex_stage.v. This is an explicit trade-off — rs2 MAC operand range is ±131071.

Post-synthesis result: DSP48E1 = 1, LUTs in MAC hierarchy < 10.

---

## Crypto Units

Three units, all combinational, registered by the EX/WB pipeline register.

**Galois LFSR:** 19-bit linear feedback shift register. Galois topology chosen over Fibonacci because Fibonacci XOR chain depth grows with tap count (3 XOR levels for 4 taps). Galois XORs all tap positions in parallel — always 1 XOR gate deep regardless of taps. Four selectable tap polynomials via the instruction's `fn` field.

**SBOX:** 16-entry 4-bit substitution box using the PRESENT cipher S-box. Operates on the lower 4 bits of rs1, result zero-extended to 19 bits. Synthesises as LUTRAM (4 LUT6s) — too small to justify a BRAM tile.

**Key Register + KEYXOR:** A dedicated 19-bit register separate from the 16 GPRs. Only the LDK instruction writes it (loads from data memory). Only KEYXOR reads it (`rd = rs1 XOR KEYREG`). No ALU instruction can access it — isolation is microarchitectural, not a software convention.

---

## Clock and Timing

The AC701's 200MHz oscillator is a differential LVDS pair. An IBUFDS primitive converts it to single-ended before the clock network — skipping this causes Vivado DRC error REQP-56.

Clock then goes through MMCME2_BASE rather than directly to a BUFG. Reason: the raw oscillator has ±150ps jitter. At a 5ns clock period, that jitter directly reduces timing margin. The MMCM's PLL filters it to ±50ps. The MMCM is configured with VCO at 1000MHz (200MHz input × 5), output divided by 5 back to 200MHz.

CPU reset is gated on mmcm_locked. The CPU stays in reset until the PLL acquires lock (~5000–10000 cycles after power-on). Without this, random pipeline state during lock acquisition looks like functional bugs.

**Three timing violations fixed during closure:**

1. Combinational branch feedback (WNS = −0.847ns) → registered into EX/WB register, eliminating all logic from the path
2. DSP48 C-port feedback (−0.412ns) → 2-stage MREG+PREG pipeline keeps feedback inside the DSP tile
3. WB mux priority chain (−0.291ns) → replaced with `(* parallel_case *)` case statement, 1 LUT level instead of 2

---

## Instruction Memory and Data Memory

Both are 19-bit wide, 1024 words deep, synchronous BRAM. The `(* rom_style = "block" *)` and `(* ram_style = "block" *)` attributes force BRAM inference — without them Vivado may choose distributed RAM for small depths. Reads are unconditional (BRAM always reads; the result is gated downstream in WB via wb_sel). Conditional reads can prevent BRAM inference on some Vivado versions.

Post-synthesis: RAMB36E1 = 2 confirmed.

---

## Simulation

Functional correctness was verified through directed simulation before synthesis. `test_full.mem` is a hand-assembled 19-bit hex program that exercises all 7 instruction classes sequentially. Three values are ground truth:

- `r2 = 13` — verifies ADD (10 + 3)
- `r6 = 42` — verifies MACZ (7 × 6) and RDACC
- `r11 = SBOX[LFSR_next(341)[3:0]] XOR 0x5A` — verifies the full crypto chain

---

## File Structure

```
signalcrypt19/
├── src/
│   ├── core/
│   │   ├── sc19_top.v        top-level: MMCM, all stage instantiations, stall logic
│   │   ├── if_stage.v        PC, BRAM fetch, stall and flush handling
│   │   ├── id_stage.v        decode, register file, immediate generator, ID/EX register
│   │   ├── ex_stage.v        ALU, MAC, crypto mux, branch resolution, EX/WB register
│   │   ├── wb_stage.v        4-to-1 writeback mux, key register write port
│   │   ├── control_unit.v    opcode to control signals, all 32 opcodes explicit
│   │   ├── alu.v             19-bit combinational ALU, 9 operations
│   │   └── mac_unit.v        DSP48E1-inferred signed MAC, 2-stage pipeline
│   ├── crypto/
│   │   ├── lfsr_unit.v       19-bit Galois LFSR, 4 tap polynomials
│   │   ├── sbox_mem.v        PRESENT cipher 4-bit S-box, LUTRAM
│   │   └── key_reg.v         isolated key register and KEYXOR
│   └── mem/
│       ├── instr_mem.v       19-bit x 1024 instruction BRAM
│       └── data_mem.v        19-bit x 1024 data BRAM, word-addressed
├── tb/
│   ├── tb_sc19_top.v         full CPU testbench
│   ├── tb_mac_unit.v         MAC unit test including signed operands
│   ├── tb_lfsr.v             LFSR correctness per polynomial
│   └── programs/
│       ├── test_alu.mem      ALU verification program
│       ├── test_mac.mem      MAC accumulation test
│       ├── test_crypto.mem   LFSR, SBOX, KEYXOR chain test
│       └── test_full.mem     all instruction classes, sequential
└── constraints/
    └── ac701_sc19.xdc        200MHz LVDS clock, reset, LEDs, UART, false paths, multicycle paths
```

---

## Tools

- HDL: Verilog (IEEE 1364-2001)
- Tool: Xilinx Vivado 2023.x
- Target: XC7A200T-2FBG676, Artix-7 speed grade -2
- Board: Xilinx AC701 Evaluation Board
- Simulation: Vivado XSim
