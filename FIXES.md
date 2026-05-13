# FIXES.md — Critical Fix Queue

## CURRENT_FIX
FIX-12: Solidity & Yul backends produce unverified output

## COMPLETED
- [x] FIX-1: _classifyType empty-list misclassification (commit 6a47a93, +5 tests)
- [x] FIX-2: _classifyType returns TYPE_BOOL for 0 and 1 (commit b104a09, +16 tests)
- [x] FIX-3: None vs -1 collision (commit 147ca96, +8 tests)
- [x] FIX-4: Integer range / string ID collision (commit 3b70c02, +6 tests)
- [x] FIX-5: Float tag false positives (commit pending, +6 tests)
- [x] FIX-6: Exception handling — multiple except & finally JUMP backpatch (+6 tests)
- [x] FIX-7: Augmented assignment to non-simple targets (+5 tests)
- [x] FIX-8: Temp variable slot exhaustion in lst[i] = value (+3 tests)
- [x] FIX-9: GC actually decrements refs (+4 tests)
- [x] FIX-10: Float precision documented as 6-digit fixed-point (ISA.md, ARCHITECTURE.md)

## QUEUE (in priority order — DO NOT REORDER)
- [x] FIX-1: _classifyType empty-list misclassification
- [x] FIX-2: _classifyType returns TYPE_BOOL for 0 and 1
- [x] FIX-3: None vs -1 collision
- [x] FIX-4: Integer range / string ID collision
- [x] FIX-5: Float tag false positives on extreme values
- [x] FIX-6: Exception handling — multiple except & finally JUMP backpatch
- [x] FIX-7: Augmented assignment to non-simple targets
- [x] FIX-8: Temp variable slot exhaustion in lst[i] = value
- [x] FIX-9: GC actually decrements refs
- [x] FIX-10: Float precision is 6-digit fixed point, not IEEE 754
- [x] FIX-11: Self-hosting bootstrap is not real
- [ ] FIX-12: Solidity & Yul backends produce unverified output
- [ ] FIX-13: Test assertions strengthen
- [ ] FIX-14: Documentation drift
- [ ] FIX-15: Parser _funcPs/_funcPc storage-as-return-value
- [ ] FIX-16: _callArgs reset between Parser uses

## BLOCKERS
- FIX-1: `len([])` returns 0 which is also a valid list ID. This is a value-space collision that requires type tagging (FIX-2) to fully resolve. Decision: accept this limitation for FIX-1, document it. FIX-2 will introduce BOOL_TAG and address 0/1 ambiguity.
- FIX-3: `is` keyword was not parsed as comparison operator. Fixed by adding KW_IS to _isCmp/_cmpOp, mapping `is` → EQ and `is not` → NEQ.
- FIX-3: -1 (2^256-1) collides with string ID range (>= 2^62). isinstance(-1, int) returns TYPE_STR. This is FIX-4's domain. Decision: test -1 == None instead of isinstance(-1, int) for FIX-3.
- FIX-6: Three bugs in _genTryStmt: (1) handlerPC backpatch used relative offset but _execRaise treats it as absolute — fixed with `code.length` backpatch. (2) code.length included 7-byte header but VM code starts at index 0 — fixed with `code.length - HEADER_SIZE`. (3) Finally block body not generated because _genBlock received FINALLY_BRANCH wrapper node — fixed by dereferencing through `_c1(finallyBranch)`.
- FIX-7: _genAugAssign only handled IDENTIFIER_REF targets. lst[i] += value was silently ignored. Fixed by adding INDEX_ACCESS handling: load current value via LIST_GET, apply op, store via LIST_SET with temp variable for intermediate result.
- FIX-8: List/augmented assignment codegen used unique temp variable names per statement (`__asgn0`, `__asgn1`, ...) via `_forTempCounter`, exhausting uint8 variable slots in loops. Fixed by using a single reusable temp name `__tmp` per scope — safe because temps are always stored then loaded within the same statement.
- FIX-9: Three issues: (1) Code generator never emitted OP_GC_UNREF — added LOAD_VAR + GC_UNREF before every STORE_VAR. (2) `_gcDecRef`/`_gcIncRef` treated ID 0 as sentinel (`id == 0` early return), but list IDs start at 0 — removed the sentinel check, relying solely on `gcLive[id]`. (3) GC_UNREF on first-assignment variables incorrectly unrefed the default value 0 — added `varInitialized` tracking to only emit GC_UNREF on reassignment.
- FIX-10: Documentation-only fix. ISA.md said "Float: NOT SUPPORTED in v1" but floats are implemented using 6-digit fixed-point (FLOAT_SCALE=1,000,000). Updated ISA.md and ARCHITECTURE.md to accurately describe the tagged fixed-point representation.
- FIX-11: Documentation-only fix. "Self-hosting Bootstrap" was misleading — the mini_lexer.py is compiled by the Solidity compiler, not by itself. True self-hosting would require the compiler to compile its own source code. Updated GOAL.md to clarify this is a "Bootstrap Demo", not self-hosting.

## FOLLOW_UPS
(things noticed but out of scope for current fix)

## TEST_COUNT
625 passing / 625 total
