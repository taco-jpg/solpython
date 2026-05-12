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

## 2026-05-11 — Feature Extensions: For Loops, Negative Numbers, Bubble Sort, Print String

### Changes Made

#### P1: For Loop Implementation
- Fully implemented `_genForRange` supporting `range(n)`, `range(start, stop)`, `range(start, stop, step)`
- Implemented `_genForList` for list literal iteration
- Implemented `_genForIterable` for variable-based list iteration
- Added break/continue support with backpatching for both while and for loops
- For loops desugar into while loops with temp variables `__fi`, `__fs`, `__fz`

#### P2: Negative Number Arithmetic
- Changed VM's ADD, SUB, MUL, NEG operations to use `unchecked` blocks for two's complement arithmetic
- Comparison operations (LT, GT, LTE, GTE) use `int256` casting for correct signed comparison

#### P3: Bubble Sort Test
- Added `testBubbleSort` to Integration.t.sol — sorts `[5, 3, 8, 1, 2]` into `[1, 2, 3, 5, 8]`
- Uses nested for loops with list element swapping

#### P4: Print String Output
- Added `OP_PRINT_STR` (0x82) opcode to VM and ISA
- Added `PrintString(string)` event to VM
- Added `_execPrintStr` handler that reads from string table
- Code generator detects STRING_LITERAL arguments to print() and emits PRINT_STR
- Added `testPrintString` to Integration.t.sol

#### Critical Bug Fix: Parser Body Stack Management
- Root cause: `_bodyCur()` always returned the last pushed body level because `_bodyPopTo` didn't restore the parent nesting
- Symptom: Recursive functions (factorial, fibonacci) returned wrong values because statements after nested blocks were pushed to wrong body level
- Fix: Added `_bodyNesting` stack that is pushed in `_bodyPush` and popped in `_bodyPopTo`, separate from `bodyStackIdx` used for merge loop

### Files Modified
- `src/phases/Parser.sol` — Added `_bodyNesting` stack, updated `_bodyPush`, `_bodyPopTo`, `_bodyCur`
- `src/phases/CodeGenerator.sol` — Added for loop desugaring, break/continue backpatching, PRINT_STR emission
- `src/phases/VM.sol` — Added unchecked arithmetic, PRINT_STR opcode, PrintString event
- `ISA.md` — Added PRINT_STR opcode documentation

### Files Created
- `test/ForLoop.t.sol` — 13 tests for for loops (range, list, nested, break, continue)

### Test Results
177/177 passing across 8 suites. New tests: for loop range variants, list iteration, nested loops, break, continue, bubble sort, print string.

## 2026-05-11 — P1-B: String Methods

### Changes Made

#### String Opcodes (11 new opcodes: 0xA0-0xAA)
- `OP_STR_LEN` (0xA0) — Get string length
- `OP_STR_CONCAT` (0xA1) — Concatenate two strings
- `OP_STR_UPPER` (0xA2) — Convert string to uppercase
- `OP_STR_LOWER` (0xA3) — Convert string to lowercase
- `OP_STR_SLICE` (0xA4) — Extract substring (s[start:end])
- `OP_STR_EQ` (0xA5) — String equality comparison
- `OP_STR_TO_INT` (0xA6) — Convert string to integer
- `OP_INT_TO_STR` (0xA7) — Convert integer to string
- `OP_STR_CONTAINS` (0xA8) — Check if string contains substring
- `OP_STR_SPLIT` (0xA9) — Split string by delimiter
- `OP_STR_CHAR_AT` (0xAA) — Get character at index

#### Parser Changes
- Added `_methodCall()` function for dot notation method calls (s.upper(), s.lower(), etc.)
- Added slice syntax parsing (a[i:j]) with SLICE_ACCESS node type
- Strip quotes from string literals in AST (lexer keeps quotes for test compatibility)

#### CodeGenerator Changes
- Added method call detection in `_genFuncCall()` for upper, lower, contains, split, charAt
- Added type conversion detection for str() and int()
- Updated len() dispatch to emit OP_STR_LEN, OP_DICT_LEN, or OP_SET_LEN based on argument type
- Added SLICE_ACCESS node handling in `_genExpr()`

#### SemanticAnalyzer Changes
- Added string method recognition in `_analyzeFuncCall()` for type inference
- upper/lower → STRING, contains → BOOL, split → LIST[STRING], charAt → INT

#### VM Changes
- Implemented all 11 string opcode execution functions
- Added runtime string storage (runtimeStrings mapping, RUNTIME_STR_OFFSET = 2^240)
- Added STATIC_STR_OFFSET = 2^62 for string table IDs
- Separated ID ranges: Lists (0..2^60), Dicts (2^60..2^61), Sets (2^61..2^62), Static strings (2^62..2^240), Runtime strings (2^240+)
- Updated OP_ADD to handle string concatenation when operands are string IDs
- Updated OP_PRINT to detect string IDs and emit PrintString events
- Updated OP_LIST_LEN to handle all types (list, dict, set, static string, runtime string)
- Added `_isStringId()` helper for precise string ID detection (avoids false positives with negative numbers)
- Added StringLib functions: upper, lower, sliceStr, contains, split, intToBytes, bytesToInt

#### StringLib Changes
- Added upper(), lower(), sliceStr(), contains(), split(), intToBytes(), bytesToInt() functions
- Fixed `match` reserved keyword issue (renamed to `isMatch`)

#### Critical Bug Fixes
1. **String table cache bug**: stringIndex mapping used 0 as both "not cached" and "cached at index 0", causing duplicate string entries. Fixed by adding stringCached mapping.
2. **Negative number string collision**: STATIC_STR_OFFSET (2^62) overlapped with two's complement negative numbers, causing ADD to treat negative numbers as strings. Fixed by using `_isStringId()` with precise range checking.
3. **String concat operand order**: Stack pop order was reversed, producing wrong concatenation order. Fixed to b (left) + a (right).
4. **Slice end default**: end==0 should mean "use string length" but wasn't handled. Fixed in `_execStrSlice`.

### Files Modified
- `src/types/ASTNode.sol` — Added SLICE_ACCESS node type
- `src/phases/Lexer.sol` — No changes (kept quotes in lexeme)
- `src/phases/Parser.sol` — Added _methodCall(), updated _idxAccess() for slices, strip quotes from STRING_LITERAL
- `src/phases/SemanticAnalyzer.sol` — Added string method type inference
- `src/phases/CodeGenerator.sol` — Added string method dispatch, slice handling, STATIC_STR_OFFSET
- `src/phases/VM.sol` — Added all string opcodes, runtime string storage, ID range separation
- `src/libraries/StringLib.sol` — Added string utility functions

### Files Created
- `test/StringMethods.t.sol` — 19 tests for string operations

### Test Results
245/245 passing across 13 suites. New tests: str len, upper, lower, contains, split, int/str conversion, slice, concat, equality, combined operations.

## 2026-05-11 — P1-C: Solidity Backend

### Changes Made

#### SolidityBackend.sol — AST to Solidity source transpiler
- Walks the AST and generates valid Solidity source code as a string
- Python functions become `internal pure` Solidity functions with `uint256` params/returns
- Variables become `uint256` local variables in an `execute()` function
- Control flow (if/elif/else, while, for) maps directly to Solidity
- `for x in range(n)` desugars to `for (uint256 __fi = 0; __fi < n; __fi++)` style loops
- `for x in list` desugars to index-based iteration with `uint256[] memory`
- List literals become `new uint256[]` array expressions
- Index access, arithmetic, comparisons, boolean logic all map directly
- `print()` becomes a comment (Solidity doesn't have console output)
- `len()` becomes `.length`
- Dict/set/float/string operations emit comments (not Solidity-compatible)
- Break/continue map directly to Solidity break/continue

#### PythonCompiler.sol
- Added `compileToSolidity(source)` function that runs Lexer → Parser → SemanticAnalyzer → SolidityBackend

### Files Created
- `src/phases/SolidityBackend.sol` — AST to Solidity transpiler
- `test/SolidityBackend.t.sol` — 39 tests

### Test Results
284/284 passing across 14 suites. New tests: contract structure, variable assignment, reassignment, arithmetic (add/sub/mul/div/mod), unary neg, augmented assignment, comparisons (eq/lt/gte), boolean logic (and/or/not), literals (bool/none/string), control flow (if/elif/else/while/for), break, function definitions, function calls, list literals, index access, list length, nested expressions, empty program, pass statement, compiler integration.

## 2026-05-11 — P2-A: Import (Static Linking)

### Changes Made

#### AST Changes
- Added `IMPORT_STMT` to `NodeType` enum
- `import module` — strValue = module name
- `from module import name` — strValue = module name, exprAux = imported names

#### Token Changes
- Added `KW_FROM` to `TokenType` enum
- Added `"from"` keyword recognition in Lexer

#### Parser Changes
- Added `_importStmt()` for `import module` syntax
- Added `_fromImportStmt()` for `from module import name [, name2, ...]` syntax

#### CodeGenerator / SemanticAnalyzer / SolidityBackend
- Added IMPORT_STMT handling as no-op (imports resolved at compiler level)

#### PythonCompiler Changes
- Added `compileWithImports(source, moduleNames[], moduleSources[])` function
- Each imported module is parsed separately, function definitions are extracted
- Function source text is prepended to the main source
- Combined source is compiled as a single program (static linking)
- Added `_extractFuncSource()` helper that uses line tracking to extract function text

### Files Created
- `test/Import.t.sol` — 11 tests

### Files Modified
- `src/types/ASTNode.sol` — Added IMPORT_STMT node type
- `src/types/Token.sol` — Added KW_FROM
- `src/phases/Lexer.sol` — Added "from" keyword
- `src/phases/Parser.sol` — Added import parsing
- `src/phases/CodeGenerator.sol` — Added IMPORT_STMT no-op
- `src/phases/SemanticAnalyzer.sol` — Added IMPORT_STMT no-op
- `src/phases/SolidityBackend.sol` — Added IMPORT_STMT comment emission
- `src/PythonCompiler.sol` — Added compileWithImports, _extractFuncSource

### Test Results
295/295 passing across 15 suites. New tests: parser recognizes import/from-import, import no-op in codegen, simple function import, multiple function import, cross-module function calls, import with for loop, import with main code, multiple modules, empty module list.

## 2026-05-11 — P2-B: VFS (Virtual File System)

### Changes Made

#### VFS Contract (`src/vfs/VFS.sol`)
- On-chain file storage using `mapping(string => string)` for content and `mapping(string => bool)` for existence tracking
- `writeFile(path, content)` — write/overwrite a file
- `readFile(path)` — read file content (reverts if not found)
- `fileExists(path)` — check existence
- `deleteFile(path)` — delete a file (reverts if not found)
- `fileCount()` — number of files
- `getFilePath(index)` — get path by index
- `listFiles()` — get all file paths
- Events: `FileWritten`, `FileDeleted`

#### PythonCompiler Integration
- Added `compileWithVFS(source, vfs)` function
- Parses source for import statements
- Reads module source from VFS (tries `module.py` then `module`)
- Delegates to `compileWithImports` for static linking

### Files Created
- `src/vfs/VFS.sol` — Virtual File System contract
- `test/VFS.t.sol` — 16 tests

### Files Modified
- `src/PythonCompiler.sol` — Added VFS import and compileWithVFS function

### Test Results
311/311 passing across 16 suites. New tests: write/read, file exists, overwrite, delete, delete revert, read revert, file count, get path, list files, delete doesn't remove from list, write/delete events, compile with VFS, VFS multiple modules, VFS no imports, VFS missing module.

## 2026-05-11 — P2-C: GC (Reference Counting)

### Changes Made

#### GC Library (`src/gc/RefCounter.sol`)
- `RefCounter` library with `GCState` struct
- `alloc()` — allocate new object with refcount 1
- `incRef()` / `decRef()` — adjust reference counts
- `decRef()` returns `true` if object freed (refcount hit 0)
- `getRefcount()`, `isAlive()`, `getObjectType()`, `stats()` getters
- Object types: OBJ_LIST, OBJ_DICT, OBJ_SET, OBJ_STRING

#### VM GC Integration
- Added GC state: `gcRefcounts`, `gcLive`, `gcTotalAllocated`, `gcTotalFreed`, `frameObjects`
- Added opcodes: `OP_GC_REF` (0xB0), `OP_GC_UNREF` (0xB1), `OP_GC_CLEANUP` (0xB2), `OP_GC_STATS` (0xB3)
- `_gcRegister(id)` — register object with refcount 1 in current frame
- `_gcIncRef(id)` / `_gcDecRef(id)` — refcount management
- `_execGcRef` — increment refcount (non-destructive, pushes value back)
- `_execGcUnref` — decrement refcount, free if 0
- `_execGcCleanup` — cleanup all objects in current frame
- `_execGcStats` — emit GCStats event
- MAKE_LIST, MAKE_DICT, MAKE_SET now register with GC
- Public getters: `getGCAllocated()`, `getGCFreed()`, `getGCLive()`, `getGCRefcount()`, `getGCLiveStatus()`

### Files Created
- `src/gc/RefCounter.sol` — GC library
- `test/GC.t.sol` — 13 tests

### Files Modified
- `src/phases/VM.sol` — Added GC state, opcodes, and execution functions

### Test Results
324/324 passing across 17 suites. New tests: list registered, multiple lists, dict registered, set registered, refcount starts at 1, GC stats, no objects for primitives, list in loop, nested list, list reassignment, GC in function, GC multiple types, existing tests unaffected.

## 2026-05-11 — P3-A: Yul Backend

### Changes Made

#### YulBackend.sol — AST to Yul IR transpiler
- Walks the AST and emits Yul intermediate representation
- Yul is Solidity's intermediate language that compiles to EVM bytecode
- Output format: `object "Transpiled" { code { ... } }`
- Variables: `let x := expr` for first declaration, `x := expr` for reassignment
- Arithmetic: `add()`, `sub()`, `mul()`, `div()`, `mod()`, `exp()`
- Comparisons: `eq()`, `lt()`, `gt()`, `iszero()` for NEQ/LTE/GTE
- Boolean: `and()`, `or()`, `iszero()` for NOT
- Control flow: `if cond { }`, `for { } cond { } { }` (while→for)
- For loops: `for { let i := start } lt(i, stop) { i := add(i, step) } { }`
- Functions: `function name(params) -> result { }` as sub-objects
- Lists: memory allocation with `mstore`/`mload`
- Index access: `mload(add(list, mul(add(i, 1), 32)))`
- `print()` → `log1(0, 0, value)`
- `len()` → `mload(ptr)`

#### PythonCompiler.sol
- Added `compileToYul(source)` function

### Files Created
- `src/phases/YulBackend.sol` — Yul IR transpiler
- `test/YulBackend.t.sol` — 33 tests

### Files Modified
- `src/PythonCompiler.sol` — Added YulBackend import and compileToYul

### Test Results
357/357 passing across 18 suites. New tests: object header, assignment, reassignment, arithmetic (add/sub/mul/div/mod/exp), unary neg, augmented assignment, comparisons (eq/lt/gt/neq/lte/gte), boolean logic (and/or/not), control flow (if/else/while/for), functions, list literal, index access, bool/none literals, compiler integration, empty program, pass statement.

## 2026-05-11 — P3-B: Self-hosting Bootstrap

### Changes Made

#### Python Lexer (`src/bootstrap/lexer.py`)
- Full Python lexer written in the subset of Python the compiler supports
- Handles: integers, identifiers, keywords (all 20+), string literals, all operators (single and multi-char), all delimiters, indentation (INDENT/DEDENT), comments, newlines
- Token type constants match `Token.sol` enum order
- Helper functions: `is_alpha()`, `is_digit()`, `is_alnum()`, `keyword_type()`, `token_type_name()`
- Too large for EVM execution (~300 lines) — used for documentation and future off-chain use

#### Mini Python Lexer (`src/bootstrap/mini_lexer.py`)
- Minimal lexer written in compiler-compatible Python subset
- Handles: integers, identifiers, +, -, *, /, =, (, ), [, ], ,, :, newline
- Small enough to compile and execute within EVM gas limits
- Successfully compiled by the Solidity compiler and executed on test inputs

#### Self-hosting Verification
- Mini lexer compiled by Solidity compiler → produces valid bytecode
- Mini lexer executed on "x = 42" → produces correct token types (6, 34, 0, 58)
- Mini lexer executed on "x + y" → produces correct token types (6, 27, 6, 58)
- Token count matches expected values
- Full pipeline: source → Lexer → Parser → SemanticAnalyzer → CodeGenerator → VM → execute Python lexer

#### foundry.toml
- Added `fs_permissions` for reading from `./src` directory

### Files Created
- `src/bootstrap/lexer.py` — Full Python lexer (documentation/off-chain)
- `src/bootstrap/mini_lexer.py` — Minimal lexer for EVM execution
- `test/Bootstrap.t.sol` — 6 tests

### Test Results
363/363 passing across 19 suites. New tests: mini lexer compiles, mini lexer tokenizes simple input, mini lexer tokenizes arithmetic, mini lexer token count, self-hosting token count match, bootstrap via VFS.

## 2026-05-11 — P4: Exception Handling

### Changes Made

#### Token/AST Changes
- Added `KW_TRY`, `KW_EXCEPT`, `KW_FINALLY`, `KW_RAISE` to `TokenType` enum
- Added `TRY_STMT`, `EXCEPT_BRANCH`, `FINALLY_BRANCH`, `RAISE_STMT` to `NodeType` enum

#### Lexer Changes
- Added keyword recognition for `try`, `except`, `finally`, `raise`

#### Parser Changes
- Added `_tryStmt()` for `try: ... except: ... finally: ...` syntax
- Added `_raiseStmt()` for `raise [expr]` syntax
- TRY_STMT: child1=try body, child2=finally branch, auxIndex/auxCount=except branches
- EXCEPT_BRANCH: child1=exception type (0 if bare except), child2=body
- RAISE_STMT: child1=exception expression (0 if bare raise)

#### CodeGenerator Changes
- Added `OP_TRY_BEGIN` (0xC0), `OP_TRY_END` (0xC1), `OP_RAISE` (0xC2), `OP_CATCH` (0xC3)
- `_genTryStmt()` — emits TRY_BEGIN with handler PC, try body, TRY_END, JUMP over handlers, except handlers with CATCH, finally body
- `_genRaiseStmt()` — emits expression then RAISE opcode

#### VM Changes
- Added exception stack (`tryStack`), `exceptionActive`, `exceptionValue`
- `_execTryBegin()` — reads 4-byte handler PC, pushes onto try stack
- `_execTryEnd()` — pops try stack
- `_execRaise()` — pops value, sets exception state, jumps to handler or halts
- `_execCatch()` — pushes exception value onto stack, clears exception state
- Public getters: `isExceptionActive()`, `getExceptionValue()`, `getTryStackDepth()`

#### SemanticAnalyzer / SolidityBackend / YulBackend
- Added TRY_STMT, RAISE_STMT handling (analyze body/handlers, emit comments/revert)

### Files Created
- `test/Exception.t.sol` — 15 tests

### Files Modified
- `src/types/Token.sol` — Added KW_TRY, KW_EXCEPT, KW_FINALLY, KW_RAISE
- `src/types/ASTNode.sol` — Added TRY_STMT, EXCEPT_BRANCH, FINALLY_BRANCH, RAISE_STMT
- `src/phases/Lexer.sol` — Added try/except/finally/raise keywords
- `src/phases/Parser.sol` — Added _tryStmt(), _raiseStmt()
- `src/phases/CodeGenerator.sol` — Added exception opcodes and code generation
- `src/phases/VM.sol` — Added exception stack and execution functions
- `src/phases/SemanticAnalyzer.sol` — Added TRY_STMT/RAISE_STMT analysis
- `src/phases/SolidityBackend.sol` — Added TRY_STMT/RAISE_STMT handling
- `src/phases/YulBackend.sol` — Added TRY_STMT/RAISE_STMT handling

### Test Results
378/378 passing across 20 suites. New tests: try/except parsed, try/except/finally parsed, raise parsed, raise with value parsed, try/except basic, raise in try, finally executes, raise with finally, exception value, try without except, compile and execute, try/except/finally/raise keywords.
