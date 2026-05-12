# GOAL.md — Python-to-EVM Compiler in Solidity

## CURRENT_TASK
P1-C: Solidity Backend

## COMPLETED
- [x] Project scaffolding (Foundry, directory structure)
- [x] CLAUDE.md, GOAL.md, PROGRESS.md, ARCHITECTURE.md, ISA.md created
- [x] Phase 1: Lexer contract — 54 tests passing
- [x] Phase 2: Parser (AST Builder) — 33 tests passing
- [x] Phase 3: Semantic Analysis — 24 tests passing
- [x] Phase 4: Code Generation — 13 tests passing
- [x] Phase 5: Bytecode Interpreter (VM) — 12 tests passing
- [x] Phase 6: Integration & Test Suite — 177 tests passing
- [x] For loop implementation (range, list iteration, break, continue)
- [x] Negative number arithmetic (unchecked two's complement)
- [x] Bubble sort test
- [x] Print string output (PRINT_STR opcode)
- [x] P0-A: Constant Folding and Dead Code Elimination (17 tests)
- [x] P0-B: Better Error Messages (12 tests, VMError events, getErrors())
- [x] P1-A: Dict and Set Types (12 dict + 8 set tests)
- [x] P1-B: String Methods (19 tests, 11 opcodes, method calls, slice syntax)

## IN_PROGRESS
- [ ] P1-C: Solidity Backend (transpiler)

## NEXT_UP
- [ ] P2-A: Import (static linking)
- [ ] P2-B: VFS (virtual file system)
- [ ] P2-C: GC (reference counting)
- [ ] P2-A: Import (static linking)
- [ ] P2-B: VFS (virtual file system)
- [ ] P2-C: GC (reference counting)
- [ ] P3-A: Yul Backend
- [ ] P3-B: Self-hosting Bootstrap
- [ ] P4: Exception Handling
- [ ] P5: Venv

## BLOCKERS
(None yet)

## TEST_COUNT
245 passing / 245 total

## PHASE DETAILS

### Phase 1 — Lexer (Tokenizer)
Solidity contract that takes Python source as `string`/`bytes` input and returns a token stream.
Tokens: keywords (def, return, if, else, elif, while, for, in, pass, break, continue, import, class, True, False, None, and, or, not, is, lambda), identifiers, integer literals, float literals, string literals, operators (+, -, *, /, //, %, **, ==, !=, <, >, <=, >=, =, +=, -=, *=, /=), delimiters (( ) [ ] { } , : . ;), INDENT, DEDENT, NEWLINE, EOF.
Handle Python's indentation-based block structure.

### Phase 2 — Parser (AST Builder)
Recursive descent parser. Consumes token stream, produces AST as struct array in storage.
Support: function definitions, if/elif/else, while loops, for loops, assignments, augmented assignments, expressions (arithmetic, comparison, boolean), function calls, return statements, integer/float/string/bool/None literals, list literals, basic class definitions.

### Phase 3 — Semantic Analysis
Symbol table using Solidity mappings. Scope resolution (global vs local), basic type inference (int, float, str, bool, None, list), undefined variable detection, arity checking for function calls.

### Phase 4 — Code Generation
Walk AST, emit custom stack-based bytecode. ISA defined in ISA.md. Must support: PUSH, POP, ADD, SUB, MUL, DIV, MOD, POW, EQ, NEQ, LT, GT, LTE, GTE, AND, OR, NOT, LOAD_VAR, STORE_VAR, CALL, RETURN, JUMP, JUMP_IF_FALSE, MAKE_LIST, LIST_GET, LIST_SET, PRINT, HALT.

### Phase 5 — Bytecode Interpreter (VM)
Solidity contract executing Phase 4 bytecode. Stack machine with local variable storage (mapping-based frame). Must run: fibonacci, factorial, fizzbuzz, basic list operations.

### Phase 6 — Integration & Test Suite
`PythonCompiler.sol` wiring Lexer → Parser → SemanticAnalyzer → CodeGenerator.
Test suite (Foundry) with end-to-end compilation and execution of:
1. Hello World (print)
2. Fibonacci (recursive)
3. Fibonacci (iterative)
4. Factorial
5. FizzBuzz
6. Bubble sort on a list
7. A class with a method

## TECHNICAL DECISIONS
- Framework: Foundry
- AST representation: Solidity structs with node type enum and child index arrays
- Libraries for reusable logic to avoid 24KB limit
- `string memory` / `bytes memory` conversions used freely for parsing
