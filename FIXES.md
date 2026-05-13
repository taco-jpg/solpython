# FIXES.md — Critical Fix Queue

## CURRENT_FIX
FIX-2: _classifyType returns TYPE_BOOL for 0 and 1
  Sub-step: Write failing tests

## COMPLETED
- [x] FIX-1: _classifyType empty-list misclassification (commit pending, +5 tests)

## QUEUE (in priority order — DO NOT REORDER)
- [x] FIX-1: _classifyType empty-list misclassification
- [ ] FIX-2: _classifyType returns TYPE_BOOL for 0 and 1
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

## FOLLOW_UPS
(things noticed but out of scope for current fix)

## TEST_COUNT
571 passing / 571 total
