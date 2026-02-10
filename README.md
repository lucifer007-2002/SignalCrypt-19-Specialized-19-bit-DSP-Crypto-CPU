# SignalCrypt-19 — Custom 19-bit Pipelined DSP/Crypto Processor

## Overview
SignalCrypt-19 is a custom-designed 19-bit processor implementing a
5-stage in-order pipeline with dedicated DSP and cryptographic instructions.
The design is written in pure Verilog and validated on Xilinx FPGA targets.

## Key Features
- Custom 19-bit ISA
- 5-stage pipeline (IF, ID, EX, MEM, WB)
- Hazard detection and data forwarding
- DSP instruction: FFT (butterfly-style)
- Cryptographic instructions: ENC / DEC
- FPGA-friendly synchronous memories
- Industry-grade self-checking testbench

## Instruction Format
[18:15] OPCODE
[14:11] RS1
[10:7] RS2
[6:3] RD / IMM
[2:0] FUNC

## Pipeline Stages
1. Instruction Fetch (IF)
2. Instruction Decode (ID)
3. Execute (EX)
4. Memory Access (MEM)
5. Write Back (WB)

## Hazard Handling
- Load-use hazard detection with pipeline stall
- EX/MEM and MEM/WB forwarding paths
- Store data forwarding supported




