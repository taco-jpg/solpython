# REPORT.md — Python-to-EVM Compiler in Solidity

## Summary

A complete Python-to-EVM compiler implemented entirely in Solidity smart contracts. The compiler accepts Python source code as a string, processes it through a six-phase pipeline (Lexer → Parser → Semantic Analyzer → Code Generator → VM), and executes the resulting bytecode on a custom stack-based virtual machine.

## Test Results

| Suite | Tests | Status |
|-------|-------|--------|
| Lexer | 54 | All passing |
| Parser | 33 | All passing |
| SemanticAnalyzer | 24 | All passing |
| CodeGenerator | 13 | All passing |
| VM | 12 | All passing |
| Integration | 17 | All passing |
| ForLoop | 13 | All passing |
| Demo | 11 | All passing |
| **Total** | **177** | **All passing** |

## Files Created

### Source Contracts
- `src/PythonCompiler.sol` — Top-level orchestrator
- `src/phases/Lexer.sol` — Tokenizer
- `src/phases/Parser.sol` — Recursive descent parser / AST builder
- `src/phases/SemanticAnalyzer.sol` — Symbol table, scope resolution, type inference
- `src/phases/CodeGenerator.sol` — AST to bytecode emitter
- `src/phases/VM.sol` — Stack machine bytecode interpreter
- `src/types/Token.sol` — Token types and structs
- `src/types/ASTNode.sol` — AST node types and structs
- `src/types/TypeInfo.sol` — Semantic analysis type system
- `src/libraries/StringLib.sol` — String/bytes utilities

### Test Files
- `test/Lexer.t.sol` — 54 tests
- `test/Parser.t.sol` — 33 tests
- `test/SemanticAnalyzer.t.sol` — 24 tests
- `test/CodeGenerator.t.sol` — 13 tests
- `test/VM.t.sol` — 12 tests
- `test/Integration.t.sol` — 17 tests (including bubble sort and print string)
- `test/ForLoop.t.sol` — 13 tests (range, list iteration, nested loops, break, continue)
- `test/Demo.t.sol` — 11 tests

### Documentation
- `CLAUDE.md` — Project guidance
- `GOAL.md` — Project state tracker
- `PROGRESS.md` — Development log
- `ARCHITECTURE.md` — System design
- `ISA.md` — Instruction set definition

## Python Language Support

### Supported
- Integer, float, string, boolean, and None literals
- Arithmetic operators: `+`, `-`, `*`, `/`, `//`, `%`, `**`
- Comparison operators: `==`, `!=`, `<`, `>`, `<=`, `>=`
- Boolean operators: `and`, `or`, `not`
- Variable assignment and augmented assignment (`+=`, `-=`, `*=`, `/=`)
- `if` / `elif` / `else` control flow
- `while` loops
- `for` loops with `range()` (1-3 args) and list iteration
- `break` and `continue` statements
- Function definitions with parameters and `return`
- Recursive function calls
- List literals and index access
- Built-in functions: `print`, `len`
- Class definitions (basic — body executes inline)
- String output via `print("...")` using PRINT_STR opcode

### Not Supported
- `import` statements
- Exception handling (`try`/`except`)
- Dict / set types
- String methods
- Generator / iterator protocol
- Nested classes
- Multiple assignment (`a, b = 1, 2`)

## Key Technical Decisions

1. **Separate storage arrays** for tokens and AST nodes — Solidity 0.8.20 cannot copy `struct[] memory` containing strings to storage.
2. **Three-tier aux architecture** in Parser — `aux[]` for statements, `exprAux[]` for function args/list elements/params, `bodyStack` for nested blocks merged after parsing.
3. **Getter-based AST access** — SemanticAnalyzer and CodeGenerator read AST nodes from Parser via public getters to avoid struct copy limitations.
4. **Backpatching** for forward jumps — placeholder values emitted during code generation, patched after target offsets are known.
5. **Mapping-based VM frames** — `mapping(uint256 => mapping(uint256 => uint256))` for frame-local variable storage, avoiding dynamic memory allocation.
6. **Custom bytecode format** — header with magic bytes "PY", version, code length, followed by code section and string table.
7. **Body nesting stack** — Parser uses a separate `_bodyNesting` stack to track current nesting level, preventing statements from being pushed to wrong body level after nested blocks return.
8. **For loop desugaring** — `for x in range(n)` is desugared into index-based while loop with temp variables `__fi`, `__fs`, `__fz`.
9. **Unchecked arithmetic** — VM uses unchecked blocks for ADD, SUB, MUL, NEG to support two's complement negative numbers.
10. **Continue backpatching** — Continue targets are backpatched after loop body generation, since the increment code offset is unknown during body generation.
