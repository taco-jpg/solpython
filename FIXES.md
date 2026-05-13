# FIXES.md — Critical Fix Queue

## CURRENT_FIX
FIX-5: Float tag false positives on extreme values
  Sub-step: Review tag space partitioning

## COMPLETED
- [x] FIX-1: _classifyType empty-list misclassification (commit 6a47a93, +5 tests)
- [x] FIX-2: _classifyType returns TYPE_BOOL for 0 and 1 (commit b104a09, +16 tests)
- [x] FIX-3: None vs -1 collision (commit 147ca96, +8 tests)
- [x] FIX-4: Integer range / string ID collision (commit pending, +6 tests)

## QUEUE (in priority order — DO NOT REORDER)
- [x] FIX-1: _classifyType empty-list misclassification
- [x] FIX-2: _classifyType returns TYPE_BOOL for 0 and 1
- [x] FIX-3: None vs -1 collision
- [x] FIX-4: Integer range / string ID collision
- [ ] FIX-5: Float tag false positives on extreme values
- [ ] FIX-3: None vs -1 collision
- [ ] FIX-4: Integer range / string ID collision
- [ ] FIX-5: Float tag false positives on extreme values
- [ ] FIX-6: Exception handling — multiple except & finally JUMP backpatch
- [ ] FIX-7: Augmented assignment to non-simple targets
- [ ] FIX-8: Temp variable slot exhaustion in lst[i] = value
- [ ] FIX-9: GC actually decrements refs
- [ ] FIX-10: Float precision is 6-digit fixed point, not IEEE 754
- [ ] FIX-11: Self-hosting bootstrap is not real
- [ ] FIX-12: Solidity & Yul backends produce unverified output
- [ ] FIX-13: Test assertions strengthen
- [ ] FIX-14: Documentation drift
- [ ] FIX-15: Parser _funcPs/_funcPc storage-as-return-value
- [ ] FIX-16: _callArgs reset between Parser uses

## BLOCKERS
- FIX-1: `len([])` returns 0 which is also a valid list ID. This is a value-space collision that requires type tagging (FIX-2) to fully resolve. Decision: accept this limitation for FIX-1, document it. FIX-2 will introduce BOOL_TAG and address 0/1 ambiguity.
- FIX-3: `is` keyword was not parsed as comparison operator. Fixed by adding KW_IS to _isCmp/_cmpOp, mapping `is` → EQ and `is not` → NEQ.
- FIX-3: -1 (2^256-1) collides with string ID range (>= 2^62). isinstance(-1, int) returns TYPE_STR. This is FIX-4's domain. Decision: test -1 == None instead of isinstance(-1, int) for FIX-3.

## FOLLOW_UPS
(things noticed but out of scope for current fix)

## TEST_COUNT
601 passing / 601 total
