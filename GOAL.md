# GOAL.md — Python-to-EVM Compiler in Solidity

## CURRENT_TASK
FEAT-13: Dict Methods (items/values/get/update)

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
- [x] P1-C: Solidity Backend (39 tests, AST-to-Solidity transpiler)
- [x] P2-A: Import (11 tests, static linking, compileWithImports)
- [x] P2-B: VFS (16 tests, virtual file system, compileWithVFS)
- [x] P2-C: GC (13 tests, reference counting, OP_GC_REF/UNREF/CLEANUP/STATS)
- [x] P3-A: Yul Backend (33 tests, AST-to-Yul IR transpiler)
- [x] P3-B: Self-hosting Bootstrap (6 tests, mini Python lexer compiled by Solidity compiler)
- [x] P4: Exception Handling (15 tests, try/except/finally/raise)
- [x] P5: Venv (17 tests, compilation environment with VFS, settings, module paths)
- [x] Class System (15 tests, instantiation, self, methods, inheritance)
- [x] None Type Safety (10 tests, arithmetic/comparison with None produces VMError)
- [x] Unbound Local Error (5 tests, semantic analyzer detects read-before-assign)
- [x] Dict String Keys (8 tests, string key dict ops + `in` operator via OP_IN)
- [x] For Loop Variable Range (5 tests, range with variable/expr args all working)
- [x] Negative Indexing (8 tests, lst[-1]/s[-1], fixed list element ordering bug)
- [x] Tuple Type (8 tests, tuple literals, indexing, unpacking, swap pattern)
- [x] Multiple Assignment (covered by tuple unpacking: a, b = 1, 2)
- [x] Default Parameters (7 tests, def f(x, y=10), expression defaults, partial/override)
- [x] Keyword Arguments (7 tests, positional + keyword mix, reorder, defaults + kwargs)
- [x] Ternary Expression (7 tests, a if cond else b, nested, in expressions)
- [x] Chained Comparison (8 tests, a < b < c, 4 operands, mixed ops)
- [x] For...Else and While...Else (7 tests, else executes on normal exit, skipped by break)
- [x] Enumerate and Zip builtins (7 tests, tuple for-loop targets, enumerate/zip desugaring)
- [x] Isinstance and Type builtins (9 tests, isinstance/typeof opcodes, type classification)
- [x] Map and Filter builtins (8 tests, OP_LIST_APPEND, desugared for-loop, list building)
- [x] String Formatting (8 tests, f-strings with {var}, %s/%d formatting, OP_STR_CONCAT)

## IN_PROGRESS
FEAT-13: Dict Methods (items/values/get/update)

## NEXT_UP
FEAT-14: Sorted and Reversed

## BLOCKERS
(None yet)

## TEST_COUNT
540 passing / 540 total

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
