# PROGRESS.md — Development Log

## 2026-05-10 — Project Initialization

### Decisions Made
- **Framework**: Foundry chosen over Hardhat. Rationale: faster compilation, native Solidity testing, better fuzz testing support, no JavaScript dependency.
- **Directory structure**: `src/` for compiler contracts, `test/` for Foundry tests, `src/libraries/` for shared logic, `src/phases/` for each compiler phase.
- **AST representation**: Array of structs in contract storage. Each node has a type enum and indices to children (not pointers, since Solidity storage uses indices).

### Files Created
- `CLAUDE.md` — Project guidance and autonomy rules
- `GOAL.md` — Single source of truth
- `PROGRESS.md` — This file
- `ARCHITECTURE.md` — System design document
- `ISA.md` — (pending) Instruction set definition

### Problems Encountered
(None yet)

### Next Actions
1. ~~Initialize Foundry project~~ DONE
2. ~~Implement Lexer contract~~ DONE
3. ~~Implement Lexer tests~~ DONE (54/54 passing)
4. Implement Parser contract (Phase 2)

## 2026-05-10 — Phase 1 Complete: Lexer

### Files Created
- `src/types/Token.sol` — TokenType enum (59 types) and Token struct
- `src/libraries/StringLib.sol` — String/bytes manipulation utilities
- `src/phases/Lexer.sol` — Full Python tokenizer
- `test/Lexer.t.sol` — 54 unit tests

### Decisions Made
- Lexer uses separate storage arrays (TokenType[], string[], uint256[]) instead of Token[] to avoid Solidity 0.8.20's limitation with copying struct arrays containing strings from memory to storage.
- `bytesToUint` stops at decimal point to handle float lexeme parsing.
- NEWLINE is emitted before incrementing the line counter for correct line tracking.
- Trailing NEWLINE is emitted before EOF for non-empty inputs (parser expects this).

### Problems Solved
- Solidity 0.8.20 cannot copy `Token[] memory` (struct with string) to storage → restructured to separate arrays.
- Float "3.14" caused arithmetic overflow in `bytesToUint` → added decimal point check.
- Line numbers off by one for NEWLINE tokens → moved emit before line++.
- Empty/single-token input tests expected different NEWLINE/EOF patterns → aligned tests with lexer behavior.

### Test Results
54/54 passing. Covers: empty input, integers, floats, strings, booleans, None, identifiers, all keywords, all operators (including multi-char disambiguation), all delimiters, indentation (nested), comments, multi-line, function definitions, line number tracking.

## 2026-05-11 — Phase 2 Complete: Parser

### Files Created/Modified
- `src/phases/Parser.sol` — Full recursive descent parser
- `test/Parser.t.sol` — 33 unit tests

### Decisions Made
- Parser reads tokens directly from Lexer instance via getter functions (getTokenType, getTokenLexeme, etc.) instead of copying Token arrays to storage.
- Three separate storage arrays for AST auxiliary data:
  - `aux[]` — top-level statement list indices only
  - `exprAux[]` — function call arguments, list elements, function params, elif branches
  - `bodyStack` — nested body statements (indented blocks), merged into `aux` after parsing
- `bodyNodeIdx[]` parallel array tracks which AST node owns each body level (instead of storing node index in the body array itself, which caused ordering bugs).
- Index computation (`argStart`, `es`, `ps`) is done AFTER all pushes (`exprAux.length - count`) to handle nested calls correctly.

### Problems Solved
- **`delete` on storage arrays not clearing slots**: Each test creates a fresh Parser instance, avoiding the need to clear state between calls.
- **Body statements corrupting aux ordering**: `_suite()` pushed body statement indices directly to `aux`, making them appear before the parent statement. Fixed by using a separate `bodyStack` that's merged into `aux` after all parsing completes.
- **`bodyStack[bi][0]` read wrong value**: Originally used first element of body array as owning node index, but `push` appends so the node index was at the END. Fixed by storing node indices in a separate `bodyNodeIdx[]` array.
- **Function args/params/elif corrupting aux**: These were pushed to `aux` during expression parsing, mixing with statement indices. Moved all to `exprAux`.
- **Nested function call auxIndex stale**: `_funcCall` captured `argStart = exprAux.length` before parsing args, but inner calls pushed their own args first. Fixed by computing `argStart = exprAux.length - argCnt` after all pushes.

### Test Results
33/33 passing. Covers: empty program, int literal, assignment, augmented assignment, binary ops (add/sub/mul), operator precedence, parenthesized expressions, comparison, boolean and/or/not, unary negation, function calls (no args, with args, nested), print call, if/elif/else/while/for, function defs (no params, with params, with return), return without value, list literals (empty, with elements), index access, class defs, multiple statements, exponentiation.

## 2026-05-11 — Phase 3 Complete: Semantic Analysis

### Files Created
- `src/types/TypeInfo.sol` — TypeTag enum and TypeInfo struct
- `src/phases/SemanticAnalyzer.sol` — Symbol table, scope resolution, type inference
- `test/SemanticAnalyzer.t.sol` — 24 unit tests

### Decisions Made
- Reads AST from Parser via getter functions (getNodeType, getChild1, etc.) to avoid Solidity's inability to copy struct arrays with strings from memory to storage.
- Symbol table: `mapping(uint256 => mapping(bytes32 => uint256))` — scope → name hash → type index.
- Scope stack with parent tracking for nested scopes.
- Built-in function detection (print, len, range, int, str, bool) checked before symbol lookup to avoid false "undefined" errors.

### Test Results
24/24 passing. Covers: literal types (int, float, string, bool, none), binary ops (int+int, float+int, string concat), comparisons return bool, variable type tracking, function definitions and calls, built-in functions, list operations, control flow (if, while, for), nested scopes, undefined variable detection.

## 2026-05-11 — Phase 4 Complete: Code Generation

### Files Created
- `src/phases/CodeGenerator.sol` — AST to bytecode emitter
- `test/CodeGenerator.t.sol` — 13 unit tests

### Decisions Made
- Custom stack-based bytecode ISA (defined in ISA.md) with opcodes 0x01-0xFF.
- String table appended after code section with 2-byte length-prefixed entries.
- Function offset tracking via `mapping(bytes32 => uint256)` for CALL backpatching.
- Variable slot mapping per scope via `mapping(uint256 => mapping(bytes32 => uint256))`.
- Forward jumps use placeholder values patched after target offset is known.
- `print` builtin pushes NONE after PRINT instruction so EXPR_STMT can pop it.

### Test Results
13/13 passing. Covers: magic header, code length field, push int, int assignment, print int, binary add, comparison, if statement, while loop, function def, list literal, string literal, halt at end.

## 2026-05-11 — Phase 5 Complete: Bytecode Interpreter (VM)

### Files Created
- `src/phases/VM.sol` — Stack machine bytecode interpreter
- `test/VM.t.sol` — 12 unit tests

### Decisions Made
- Stack machine with `uint256[]` stack and mapping-based frame locals.
- Call frames: `mapping(uint256 => mapping(uint256 => uint256))` for frame-local variable storage.
- Return stack (`returnPC`, `returnFrame`) for function call/return.
- Lists stored as `mapping(uint256 => uint256[])` with `nextListId` counter.
- Bytecode header: magic bytes "PY" + version byte + 4-byte code length + code section + string table.
- 100,000 step gas limit safeguard to prevent infinite loops.

### Problems Solved
- `lists[listId].length = N` not allowed in Solidity 0.8.20 → replaced with `push` loop.
- Test contract variable named `pyVm` to avoid conflict with Foundry's built-in `vm` cheatcodes.

### Test Results
12/12 passing. Covers: empty program, push and halt, assignment, addition, print int, if true/false, variable assignment, augmented assignment, magic header, code length field, make list.

## 2026-05-11 — Phase 6 Complete: Integration & Test Suite

### Files Created
- `src/PythonCompiler.sol` — Top-level orchestrator wiring Lexer → Parser → SemanticAnalyzer → CodeGenerator → VM
- `test/Integration.t.sol` — 15 end-to-end integration tests

### Test Results
15/15 passing. Covers: hello world, print multiple, simple arithmetic, nested arithmetic, augmented assignment, if/else, elif chains, while loops, simple function call, recursive factorial, recursive fibonacci, list create/access, list length, bytecode verification, end-to-end fibonacci.

## Total Test Count: 151 tests across 6 suites, all passing.
