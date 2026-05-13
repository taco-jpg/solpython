# ISA.md — Python-to-EVM Bytecode Instruction Set

## Overview

Custom stack-based bytecode for the Python compiler VM. Each instruction is a single opcode byte, optionally followed by operand bytes. The VM operates on a value stack and uses mapping-based frames for local variables.

## Data Types

Values on the stack are 256-bit words, interpreted as:
- **Integer**: signed 256-bit integer, range -2^62 to 2^62-1 (overflow-checked)
- **Float**: fixed-point with 6 decimal digits (FLOAT_SCALE = 1,000,000). Tagged with tag 5 at bits 252-255. E.g., 3.14 is stored as `(5 << 252) | 3140000`. NOT IEEE 754 — precision is limited to ~6 significant digits.
- **Boolean**: tagged with BOOL_OFFSET (2^66). `True` = 2^66 + 1, `False` = 2^66.
- **None**: special value `(6 << 252)` (tag 6 at bits 252-255)
- **String**: string table index + offset (>= 2^62)
- **List**: ID 0 to 2^60-1, tracked by `isList` mapping
- **Dict**: ID 2^60 to 2^61-1
- **Set**: ID 2^61 to 2^62-1
- **Tuple**: ID 2^62 to 2^63-1

## Instruction Set

### Stack Operations

| Opcode | Name    | Operands | Description |
|--------|---------|----------|-------------|
| 0x01   | PUSH    | 32 bytes | Push immediate 256-bit value onto stack |
| 0x02   | POP     | —        | Remove top of stack |
| 0x03   | DUP     | —        | Duplicate top of stack |
| 0x04   | SWAP    | —        | Swap top two stack values |

### Arithmetic

| Opcode | Name | Operands | Description |
|--------|------|----------|-------------|
| 0x10   | ADD  | —        | `b + a` → stack (pops a, b, pushes result) |
| 0x11   | SUB  | —        | `b - a` → stack |
| 0x12   | MUL  | —        | `b * a` → stack |
| 0x13   | DIV  | —        | `b / a` → stack (integer division) |
| 0x14   | MOD  | —        | `b % a` → stack |
| 0x15   | POW  | —        | `b ** a` → stack |
| 0x16   | NEG  | —        | `-a` → stack (unary) |

### Comparison

| Opcode | Name | Operands | Description |
|--------|------|----------|-------------|
| 0x20   | EQ   | —        | `b == a` → 1 or 0 |
| 0x21   | NEQ  | —        | `b != a` → 1 or 0 |
| 0x22   | LT   | —        | `b < a` → 1 or 0 |
| 0x23   | GT   | —        | `b > a` → 1 or 0 |
| 0x24   | LTE  | —        | `b <= a` → 1 or 0 |
| 0x25   | GTE  | —        | `b >= a` → 1 or 0 |

### Boolean / Logic

| Opcode | Name | Operands | Description |
|--------|------|----------|-------------|
| 0x30   | AND  | —        | `b && a` → 1 or 0 |
| 0x31   | OR   | —        | `b \|\| a` → 1 or 0 |
| 0x32   | NOT  | —        | `!a` → 1 or 0 |

### Variables

| Opcode | Name     | Operands | Description |
|--------|----------|----------|-------------|
| 0x40   | LOAD_VAR | 2 bytes (frame index, var index) | Push variable value onto stack |
| 0x41   | STORE_VAR| 2 bytes (frame index, var index) | Pop stack, store in variable |

Frame index 0 = global, 1 = current local. Variable index is the slot number.

### Control Flow

| Opcode | Name         | Operands | Description |
|--------|--------------|----------|-------------|
| 0x50   | JUMP         | 4 bytes (absolute bytecode offset) | Unconditional jump |
| 0x51   | JUMP_IF_FALSE| 4 bytes (absolute bytecode offset) | Pop stack; if 0, jump |
| 0x52   | JUMP_IF_TRUE | 4 bytes (absolute bytecode offset) | Pop stack; if nonzero, jump |
| 0x53   | JUMP_BACK    | 4 bytes (absolute bytecode offset) | Unconditional jump (for loops) |

### Functions

| Opcode | Name      | Operands | Description |
|--------|-----------|----------|-------------|
| 0x60   | CALL      | 2 bytes (num_args), 4 bytes (func offset) | Call function at offset with N args pushed on stack |
| 0x61   | RETURN    | —        | Pop return value, restore caller frame, push return value |
| 0x62   | SETUP_FRAME| 2 bytes (num_locals) | Allocate new stack frame with N local slots |
| 0x63   | TEAR_FRAME | —      | Deallocate current frame |

### Lists

| Opcode | Name      | Operands | Description |
|--------|-----------|----------|-------------|
| 0x70   | MAKE_LIST | 2 bytes (num_elements) | Pop N elements, create list, push list pointer |
| 0x71   | LIST_GET  | —        | Pop index and list pointer, push `list[index]` |
| 0x72   | LIST_SET  | —        | Pop value, index, and list pointer; set `list[index] = value` |
| 0x73   | LIST_LEN  | —        | Pop list pointer, push length |
| 0x74   | MAKE_TUPLE | 2 bytes (num_elements) | Pop N elements, create tuple, push tuple pointer |
| 0x75   | TUPLE_GET | —        | Pop index and tuple pointer, push `tuple[index]` |

### I/O

| Opcode | Name       | Operands | Description |
|--------|------------|----------|-------------|
| 0x80   | PRINT      | 1 byte (num_args) | Pop N values, emit as Print event |
| 0x81   | EMIT       | —        | Pop value, emit as Result event |
| 0x82   | PRINT_STR  | —        | Pop string table index, emit as PrintString event |

### Control

| Opcode | Name  | Operands | Description |
|--------|-------|----------|-------------|
| 0xFF   | HALT  | —        | Stop execution |

## Bytecode Format

```
[magic bytes: 0x5059 (PY)] [version: 0x01] [code length: 4 bytes] [code...] [string table length: 4 bytes] [string table...]
```

String table: length-prefixed strings (2 bytes length + UTF-8 bytes).

## Execution Model

1. PC starts at 0
2. Fetch instruction at PC
3. Execute (may modify stack, variables, or PC)
4. If no jump, PC advances past instruction + operands
5. Repeat until HALT or error

## Stack Frame Layout

Each function call creates a new frame:
- Frame index 0: global variables (always exists)
- Frame N: local variables for function call depth N-1

Variables are accessed by `(frame_index, var_index)` pairs. Arguments are stored in the first N slots of the new frame.
