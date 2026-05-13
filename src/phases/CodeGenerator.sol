// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {NodeType, BinaryOpType, UnaryOpType, CompOpType, AugAssignOp} from "../types/ASTNode.sol";
import {FLOAT_TAG, FLOAT_TAG_SHIFT} from "../types/TypeInfo.sol";
import {Parser} from "./Parser.sol";

contract CodeGenerator {
    // Bytecode output
    bytes private code;

    // String table
    bytes private stringTable;
    mapping(bytes32 => uint256) private stringIndex; // hash → index in string table
    mapping(bytes32 => bool) private stringCached; // hash → whether string is cached
    uint256 constant STATIC_STR_OFFSET = 2**62;

    // Function offsets: name hash → bytecode offset
    mapping(bytes32 => uint256) private funcOffsets;

    // Variable tracking: scope → name → var slot
    mapping(uint256 => mapping(bytes32 => uint256)) private varSlots;
    mapping(uint256 => uint256) private varCount; // next slot per scope
    uint256 private currentScope;

    // Backpatching stacks
    uint256[] private jumpPatchOffsets; // bytecode offsets where jump targets need to be filled

    // Loop context for break/continue
    uint256[] private _breakPatches;      // bytecode offsets of break JUMP operands to backpatch
    uint256[] private _breakContextStart;  // for each loop nesting, index in _breakPatches where breaks start
    uint256[] private _continuePatches;    // bytecode offsets of continue JUMP_BACK operands to backpatch
    uint256[] private _continueContextStart; // for each loop nesting, index in _continuePatches
    uint256[] private _continueTargets;    // for each loop nesting, the JUMP_BACK target offset (for while loops)

    // For loop temp variable counter (to generate unique names)
    uint256 private _forTempCounter;

    // Class name tracking (to detect instantiation)
    mapping(bytes32 => bool) private _classNames;
    mapping(bytes32 => bool) private _classHasInit;

    // Temporary storage for keyword argument reordering
    uint256[] private _kwargOrder;

    // Parser reference
    Parser private parser;

    event Print(bytes data);
    event Result(uint256 value);

    // Header size: 2 magic + 1 version + 4 codeLen = 7 bytes
    uint256 constant HEADER_SIZE = 7;

    // ==================== Opcodes ====================
    uint8 constant OP_PUSH = 0x01;
    uint8 constant OP_POP = 0x02;
    uint8 constant OP_DUP = 0x03;
    uint8 constant OP_SWAP = 0x04;

    uint8 constant OP_ADD = 0x10;
    uint8 constant OP_SUB = 0x11;
    uint8 constant OP_MUL = 0x12;
    uint8 constant OP_DIV = 0x13;
    uint8 constant OP_MOD = 0x14;
    uint8 constant OP_POW = 0x15;
    uint8 constant OP_NEG = 0x16;

    uint8 constant OP_EQ = 0x20;
    uint8 constant OP_NEQ = 0x21;
    uint8 constant OP_LT = 0x22;
    uint8 constant OP_GT = 0x23;
    uint8 constant OP_LTE = 0x24;
    uint8 constant OP_GTE = 0x25;

    uint8 constant OP_AND = 0x30;
    uint8 constant OP_OR = 0x31;
    uint8 constant OP_NOT = 0x32;

    uint8 constant OP_LOAD_VAR = 0x40;
    uint8 constant OP_STORE_VAR = 0x41;

    uint8 constant OP_JUMP = 0x50;
    uint8 constant OP_JUMP_IF_FALSE = 0x51;
    uint8 constant OP_JUMP_IF_TRUE = 0x52;
    uint8 constant OP_JUMP_BACK = 0x53;

    uint8 constant OP_CALL = 0x60;
    uint8 constant OP_RETURN = 0x61;
    uint8 constant OP_SETUP_FRAME = 0x62;
    uint8 constant OP_TEAR_FRAME = 0x63;

    uint8 constant OP_MAKE_LIST = 0x70;
    uint8 constant OP_LIST_GET = 0x71;
    uint8 constant OP_LIST_SET = 0x72;
    uint8 constant OP_LIST_LEN = 0x73;

    uint8 constant OP_MAKE_TUPLE = 0x74;
    uint8 constant OP_TUPLE_GET = 0x75;

    uint8 constant OP_PRINT = 0x80;
    uint8 constant OP_EMIT = 0x81;
    uint8 constant OP_PRINT_STR = 0x82;

    uint8 constant OP_MAKE_DICT = 0x90;
    uint8 constant OP_DICT_GET = 0x91;
    uint8 constant OP_DICT_SET = 0x92;
    uint8 constant OP_DICT_HAS = 0x93;
    uint8 constant OP_DICT_KEYS = 0x94;
    uint8 constant OP_DICT_LEN = 0x95;
    uint8 constant OP_MAKE_SET = 0x96;
    uint8 constant OP_SET_ADD = 0x97;
    uint8 constant OP_SET_HAS = 0x98;
    uint8 constant OP_SET_LEN = 0x99;
    uint8 constant OP_DICT_VALUES = 0x9A;
    uint8 constant OP_DICT_ITEMS = 0x9B;
    uint8 constant OP_DICT_GET_DEFAULT = 0x9C;
    uint8 constant OP_DICT_UPDATE = 0x9D;

    uint8 constant OP_STR_LEN = 0xA0;
    uint8 constant OP_STR_CONCAT = 0xA1;
    uint8 constant OP_STR_UPPER = 0xA2;
    uint8 constant OP_STR_LOWER = 0xA3;
    uint8 constant OP_STR_SLICE = 0xA4;
    uint8 constant OP_STR_EQ = 0xA5;
    uint8 constant OP_STR_TO_INT = 0xA6;
    uint8 constant OP_INT_TO_STR = 0xA7;
    uint8 constant OP_STR_CONTAINS = 0xA8;
    uint8 constant OP_STR_SPLIT = 0xA9;
    uint8 constant OP_STR_CHAR_AT = 0xAA;
    uint8 constant OP_IN = 0xAB;         // x in container

    uint8 constant OP_TRY_BEGIN = 0xC0;
    uint8 constant OP_TRY_END = 0xC1;
    uint8 constant OP_RAISE = 0xC2;
    uint8 constant OP_CATCH = 0xC3;

    uint8 constant OP_MAKE_CLASS = 0xD0;
    uint8 constant OP_MAKE_INSTANCE = 0xD1;
    uint8 constant OP_LOAD_ATTR = 0xD2;
    uint8 constant OP_STORE_ATTR = 0xD3;
    uint8 constant OP_CALL_METHOD = 0xD4;

    uint8 constant OP_ISINSTANCE = 0xE0;
    uint8 constant OP_TYPEOF = 0xE1;
    uint8 constant OP_LIST_APPEND = 0x76;

    uint8 constant OP_HALT = 0xFF;

    // ==================== Entry Point ====================

    function generate(Parser _parser) public returns (bytes memory) {
        parser = _parser;

        // Emit header: magic bytes PY + version
        _emitByte(0x50); // P
        _emitByte(0x59); // Y
        _emitByte(0x01); // version 1

        // Placeholder for code length (4 bytes) — backpatch later
        uint256 codeLenOffset = code.length;
        _emitByte(0); _emitByte(0); _emitByte(0); _emitByte(0);

        // Generate code for program (node 0)
        _genBlock(0);
        _emitOp(OP_HALT);

        // Backpatch code length
        uint256 codeLen = code.length - codeLenOffset - 4;
        _patchUint32(codeLenOffset, codeLen);

        // Append string table length + data
        uint256 stLen = stringTable.length;
        _emitByte(uint8(stLen >> 24));
        _emitByte(uint8((stLen >> 16) & 0xFF));
        _emitByte(uint8((stLen >> 8) & 0xFF));
        _emitByte(uint8(stLen & 0xFF));
        for (uint256 i = 0; i < stLen; i++) {
            code.push(stringTable[i]);
        }

        return code;
    }

    // ==================== Block / Statement Generation ====================

    function _genBlock(uint256 nodeIdx) internal {
        uint256 start = _ai(nodeIdx);
        uint256 count = _ac(nodeIdx);
        for (uint256 i = 0; i < count; i++) {
            _genStmt(_aux(start + i));
        }
    }

    function _genStmt(uint256 nodeIdx) internal {
        NodeType nt = _nt(nodeIdx);

        if (nt == NodeType.ASSIGN) {
            _genAssign(nodeIdx);
        } else if (nt == NodeType.AUG_ASSIGN) {
            _genAugAssign(nodeIdx);
        } else if (nt == NodeType.FUNCTION_DEF) {
            _genFuncDef(nodeIdx);
        } else if (nt == NodeType.IF_STATEMENT) {
            _genIfStmt(nodeIdx);
        } else if (nt == NodeType.WHILE_LOOP) {
            _genWhileLoop(nodeIdx);
        } else if (nt == NodeType.FOR_LOOP) {
            _genForLoop(nodeIdx);
        } else if (nt == NodeType.RETURN_STMT) {
            _genReturnStmt(nodeIdx);
        } else if (nt == NodeType.EXPR_STMT) {
            _genExpr(_c1(nodeIdx));
            _emitOp(OP_POP); // discard result
        } else if (nt == NodeType.PASS_STMT) {
            // no-op
        } else if (nt == NodeType.BREAK_STMT) {
            _emitOp(OP_JUMP);
            _emitUint32(0); // placeholder — backpatched when loop ends
            _breakPatches.push(code.length - 4);
        } else if (nt == NodeType.CONTINUE_STMT) {
            require(_continueContextStart.length > 0, "continue outside loop");
            _emitOp(OP_JUMP_BACK);
            _emitUint32(0); // placeholder — backpatched when loop ends
            _continuePatches.push(code.length - 4);
        } else if (nt == NodeType.CLASS_DEF) {
            _genClassDef(nodeIdx);
        } else if (nt == NodeType.IMPORT_STMT) {
            // No-op: imports are handled at the linker level
        } else if (nt == NodeType.TRY_STMT) {
            _genTryStmt(nodeIdx);
        } else if (nt == NodeType.RAISE_STMT) {
            _genRaiseStmt(nodeIdx);
        }
    }

    function _genAssign(uint256 nodeIdx) internal {
        uint256 lhsIdx = _c1(nodeIdx);
        if (_nt(lhsIdx) == NodeType.TUPLE_LITERAL) {
            // Tuple unpacking: a, b, c = expr
            _genExpr(_c2(nodeIdx)); // push RHS (tuple)
            uint256 count = _ac(lhsIdx);
            uint256 start = _ai(lhsIdx);
            for (uint256 i = 0; i < count; i++) {
                _emitOp(OP_DUP);          // duplicate tuple ID
                _genPush(uint256(i));      // push index
                _emitOp(OP_TUPLE_GET);    // get element
                uint256 target = _ea(start + i);
                _genStoreVar(target);     // store in target variable
            }
            _emitOp(OP_POP); // pop the tuple ID
            return;
        }
        if (_nt(lhsIdx) == NodeType.ATTR_ACCESS) {
            // obj.attr = val → push obj, push val, STORE_ATTR
            _genExpr(_c1(lhsIdx)); // push object
            _genExpr(_c2(nodeIdx)); // push RHS value
            _emitOp(OP_STORE_ATTR);
            _emitUint256(uint256(keccak256(bytes(_sv(lhsIdx)))));
            return;
        }
        _genExpr(_c2(nodeIdx)); // push RHS value
        if (_nt(lhsIdx) == NodeType.IDENTIFIER_REF) {
            _genStoreVar(lhsIdx);
        } else if (_nt(lhsIdx) == NodeType.INDEX_ACCESS) {
            // list[index] = value → push list, push index, LIST_SET
            // We already pushed the value. Need to push list and index before it.
            // But LIST_SET expects: value, index, list on stack (top to bottom).
            // We have value on top. We need to push list and index BELOW the value.
            // Use SWAP to rearrange.
            // Actually, LIST_SET pops value, index, list (top to bottom).
            // So we need: [list, index, value] on stack before LIST_SET.
            // We have [value] on stack. Push list and index on top, then swap.
            // [value] → push list → [value, list] → push index → [value, list, index]
            // → SWAP → [value, index, list] → hmm that's wrong.
            // LIST_SET pops: value (top), index (second), list (third)
            // So we need stack: [..., list, index, value]
            // We have [value]. Push list, index:
            // [value] → push list → [value, list] → push index → [value, list, index]
            // Need to move value to top: use DUP and SWAP tricks.
            // Actually, let's just emit the list and index first, then the value.
            // But we already pushed the value! We need to restructure.
            // The simplest fix: generate list and index first, then value, then LIST_SET.
            // But _genExpr(_c2) already pushed the value.
            // Let me just restructure: generate RHS last.
            // Pop the value, generate list and index, push value back.
            // This is complex. Let me use a different approach:
            // Store value in temp, generate list/index, push value, LIST_SET.
            // Actually, the easiest approach: rearrange the code generation order.
            // Let me re-emit this properly.

            // We need to undo the value push and redo it in the right order.
            // Instead, let me change the approach: push list, index, then value.
            // Since we already pushed value, we need to use SWAP/ROT.
            // With only SWAP (no ROT), this is tricky. Let me use a temp variable.

            // Store value in a temp variable
            string memory tempName = string.concat("__asgn", _toString(_forTempCounter));
            _forTempCounter++;
            _genStoreVarByName(tempName);

            // Push list and index
            _genExpr(_c1(lhsIdx)); // list
            _genExpr(_c2(lhsIdx)); // index

            // Push value
            _genLoadVarByName(tempName);

            // LIST_SET: pops value, index, list
            _emitOp(OP_LIST_SET);
        }
    }

    function _genAugAssign(uint256 nodeIdx) internal {
        uint256 lhsIdx = _c1(nodeIdx);
        if (_nt(lhsIdx) == NodeType.IDENTIFIER_REF) {
            _genLoadVar(lhsIdx);   // push current value
            _genExpr(_c2(nodeIdx)); // push RHS
            AugAssignOp op = AugAssignOp(_iv(nodeIdx));
            if (op == AugAssignOp.PLUS_ASSIGN) _emitOp(OP_ADD);
            else if (op == AugAssignOp.MINUS_ASSIGN) _emitOp(OP_SUB);
            else if (op == AugAssignOp.STAR_ASSIGN) _emitOp(OP_MUL);
            else _emitOp(OP_DIV);
            _genStoreVar(lhsIdx);
        }
    }

    function _genFuncDef(uint256 nodeIdx) internal {
        // Jump over function body (it's called, not executed inline)
        _emitOp(OP_JUMP);
        _emitUint32(0); // placeholder — backpatch later
        uint256 jumpOverOffset = code.length - 4;

        // Record function offset (relative to code section, not full bytecode)
        funcOffsets[keccak256(bytes(_sv(nodeIdx)))] = code.length - HEADER_SIZE;

        // Enter function scope
        currentScope++;

        // Setup frame
        uint256 paramCount = _ac(nodeIdx);
        _emitOp(OP_SETUP_FRAME);
        _emitUint16(uint16(paramCount));

        // Store params from stack into local vars (reverse order: last arg on top)
        for (uint256 i = paramCount; i > 0; i--) {
            string memory param = _sv(_ea(_ai(nodeIdx) + i - 1));
            uint256 slot = _getVarSlot(param);
            _emitOp(OP_STORE_VAR);
            _emitByte(1); // frame 1 (local)
            _emitByte(uint8(slot));
        }

        // Generate body
        if (_c2(nodeIdx) != 0) _genBlock(_c2(nodeIdx));

        // Implicit return None
        _genPushNone();
        _emitOp(OP_RETURN);

        // Exit function scope
        currentScope--;

        // Backpatch jump-over
        _patchUint32(jumpOverOffset, code.length - jumpOverOffset - 4);
    }

    function _genIfStmt(uint256 nodeIdx) internal {
        // Condition
        _genExpr(_c1(nodeIdx));
        _emitOp(OP_JUMP_IF_FALSE);
        _emitUint32(0); // placeholder
        uint256 falseJumpOffset = code.length - 4;

        // Body
        if (_c2(nodeIdx) != 0) _genBlock(_c2(nodeIdx));

        // Jump over else/elif
        _emitOp(OP_JUMP);
        _emitUint32(0); // placeholder
        uint256 endJumpOffset = code.length - 4;

        // Backpatch false jump
        _patchUint32(falseJumpOffset, code.length - falseJumpOffset - 4);

        // Elif branches
        uint256 elifStart = _ai(nodeIdx);
        uint256 elifCount = _ac(nodeIdx);
        uint256[] memory elifEndJumps = new uint256[](elifCount);
        for (uint256 i = 0; i < elifCount; i++) {
            uint256 elifIdx = _ea(elifStart + i);
            _genExpr(_c1(elifIdx));
            _emitOp(OP_JUMP_IF_FALSE);
            _emitUint32(0);
            elifEndJumps[i] = code.length - 4;
            if (_c2(elifIdx) != 0) _genBlock(_c2(elifIdx));
            _emitOp(OP_JUMP);
            _emitUint32(0);
            uint256 thisEnd = code.length - 4;
            _patchUint32(elifEndJumps[i], code.length - elifEndJumps[i] - 4);
            elifEndJumps[i] = thisEnd; // store end jump for later patching
        }

        // Else body
        if (_c3(nodeIdx) != 0) _genBlock(_c3(nodeIdx));

        // Backpatch all end jumps
        _patchUint32(endJumpOffset, code.length - endJumpOffset - 4);
        for (uint256 i = 0; i < elifCount; i++) {
            _patchUint32(elifEndJumps[i], code.length - elifEndJumps[i] - 4);
        }
    }

    function _genWhileLoop(uint256 nodeIdx) internal {
        // Push loop context for break/continue
        uint256 breakStart = _breakPatches.length;
        _breakContextStart.push(breakStart);
        uint256 continueStart = _continuePatches.length;
        _continueContextStart.push(continueStart);

        uint256 loopStart = code.length - HEADER_SIZE;

        _genExpr(_c1(nodeIdx)); // condition
        _emitOp(OP_JUMP_IF_FALSE);
        _emitUint32(0);
        uint256 exitJumpOffset = code.length - 4;

        if (_c2(nodeIdx) != 0) _genBlock(_c2(nodeIdx));

        // Backpatch continue jumps to loop start (condition)
        _backpatchContinues(continueStart, loopStart);

        _emitOp(OP_JUMP_BACK);
        _emitUint32(loopStart);

        // Exit: normal exit lands here (start of else block if present)
        _patchUint32(exitJumpOffset, code.length - exitJumpOffset - 4);

        // Else block (executes on normal exit, skipped by break)
        if (_c3(nodeIdx) != 0) _genBlock(_c3(nodeIdx));

        // Backpatch break jumps (land after else block)
        _backpatchBreaks(breakStart);

        // Pop loop context
        _breakContextStart.pop();
        _continueContextStart.pop();
    }

    function _genForLoop(uint256 nodeIdx) internal {
        // Desugar for x in range(...) into while loop with index counter
        // child1 = loop variable (IDENTIFIER_REF)
        // child2 = iterable (range() call or list)
        // child3 = body block

        uint256 iterIdx = _c2(nodeIdx);
        uint256 varIdx = _c1(nodeIdx);
        uint256 elseBody = _ai(nodeIdx); // auxIndex = else body (0 if none)

        // Push loop context for break/continue
        uint256 breakStart = _breakPatches.length;
        _breakContextStart.push(breakStart);
        uint256 continueStart = _continuePatches.length;
        _continueContextStart.push(continueStart);

        // Tuple target: for i, x in enumerate(lst) or zip(lst1, lst2)
        if (_nt(varIdx) == NodeType.TUPLE_LITERAL && _nt(iterIdx) == NodeType.FUNC_CALL) {
            string memory iterName = _sv(iterIdx);
            if (keccak256(bytes(iterName)) == keccak256("enumerate")) {
                _genForEnumerate(nodeIdx, iterIdx, varIdx, elseBody);
            } else if (keccak256(bytes(iterName)) == keccak256("zip")) {
                _genForZip(nodeIdx, iterIdx, varIdx, elseBody);
            }
        } else {
            string memory loopVar = _sv(varIdx);
            if (_nt(iterIdx) == NodeType.FUNC_CALL && keccak256(bytes(_sv(iterIdx))) == keccak256("range")) {
                _genForRange(nodeIdx, iterIdx, loopVar, elseBody);
            } else if (_nt(iterIdx) == NodeType.LIST_LITERAL) {
                _genForList(nodeIdx, iterIdx, loopVar, elseBody);
            } else {
                // General iterable (variable) — iterate using index
                _genForIterable(nodeIdx, iterIdx, loopVar, elseBody);
            }
        }

        // Pop loop context (break/continue patches already backpatched inside the helpers)
        _breakContextStart.pop();
        _continueContextStart.pop();
    }

    function _genForRange(uint256 nodeIdx, uint256 rangeIdx, string memory loopVar, uint256 elseBody) internal {
        uint256 argCount = _ac(rangeIdx);

        // Generate unique temp variable names
        string memory iName = string.concat("__fi", _toString(_forTempCounter));
        string memory stopName = string.concat("__fs", _toString(_forTempCounter));
        string memory stepName = string.concat("__fz", _toString(_forTempCounter));
        _forTempCounter++;

        // Determine start, stop, step based on arg count
        if (argCount == 1) {
            // range(n): start=0, stop=n, step=1
            _genPush(0);
            _genStoreVarByName(iName);
            _genExpr(_ea(_ai(rangeIdx)));
            _genStoreVarByName(stopName);
            _genPush(1);
            _genStoreVarByName(stepName);
        } else if (argCount == 2) {
            // range(start, stop): step=1
            _genExpr(_ea(_ai(rangeIdx)));
            _genStoreVarByName(iName);
            _genExpr(_ea(_ai(rangeIdx) + 1));
            _genStoreVarByName(stopName);
            _genPush(1);
            _genStoreVarByName(stepName);
        } else {
            // range(start, stop, step)
            _genExpr(_ea(_ai(rangeIdx)));
            _genStoreVarByName(iName);
            _genExpr(_ea(_ai(rangeIdx) + 1));
            _genStoreVarByName(stopName);
            _genExpr(_ea(_ai(rangeIdx) + 2));
            _genStoreVarByName(stepName);
        }

        // Loop start — condition: __i < __stop (or __i > __stop for negative step)
        uint256 loopStart = code.length - HEADER_SIZE;

        _genLoadVarByName(iName);
        _genLoadVarByName(stopName);
        if (argCount == 3) {
            // For 3-arg range, use GT for negative step, LT for positive step
            // We emit both LT and GT and let the runtime handle it via conditional
            // Actually, we need to check the step at compile time if possible.
            // For simplicity, always use the general approach:
            // if step < 0: condition is i > stop, else: i < stop
            // Since we can't know step at compile time, emit a conditional comparison
            _genLoadVarByName(stepName);
            _genPush(0);
            _emitOp(OP_LT); // step < 0?
            _emitOp(OP_JUMP_IF_FALSE);
            _emitUint32(0);
            uint256 positiveStepJump = code.length - 4;

            // Negative step path: i > stop
            _genLoadVarByName(iName);
            _genLoadVarByName(stopName);
            _emitOp(OP_GT);
            _emitOp(OP_JUMP);
            _emitUint32(0);
            uint256 afterPositiveJump = code.length - 4;

            // Positive step path: i < stop (backpatch the JUMP_IF_FALSE)
            _patchUint32(positiveStepJump, code.length - positiveStepJump - 4);
            _genLoadVarByName(iName);
            _genLoadVarByName(stopName);
            _emitOp(OP_LT);

            // Backpatch the jump to after positive path
            _patchUint32(afterPositiveJump, code.length - afterPositiveJump - 4);
        } else {
            _emitOp(OP_LT);
        }
        _emitOp(OP_JUMP_IF_FALSE);
        _emitUint32(0);
        uint256 exitJumpOffset = code.length - 4;

        // Assign loop variable: x = __i
        _genLoadVarByName(iName);
        _genStoreVarByName(loopVar);

        // Body
        if (_c3(nodeIdx) != 0) _genBlock(_c3(nodeIdx));

        // Backpatch continue jumps to increment code
        uint256 incTarget = code.length - HEADER_SIZE;
        uint256 continueStart = _continueContextStart[_continueContextStart.length - 1];
        _backpatchContinues(continueStart, incTarget);

        // Increment: __i += __step
        _genLoadVarByName(iName);
        _genLoadVarByName(stepName);
        _emitOp(OP_ADD);
        _genStoreVarByName(iName);

        // Jump back to loop start
        _emitOp(OP_JUMP_BACK);
        _emitUint32(loopStart);

        // Exit: normal exit lands here (start of else block if present)
        _patchUint32(exitJumpOffset, code.length - exitJumpOffset - 4);

        // Else block (executes on normal exit, skipped by break)
        if (elseBody != 0) _genBlock(elseBody);

        // Backpatch break jumps (land after else block)
        uint256 breakStart = _breakContextStart[_breakContextStart.length - 1];
        _backpatchBreaks(breakStart);
    }

    function _genForList(uint256 nodeIdx, uint256 listIdx, string memory loopVar, uint256 elseBody) internal {
        // Desugar: for x in [a, b, c] → __i=0; __lst=[a,b,c]; while __i<len(__lst): x=__lst[__i]; body; __i+=1

        string memory iName = string.concat("__fi", _toString(_forTempCounter));
        string memory lstName = string.concat("__fl", _toString(_forTempCounter));
        _forTempCounter++;

        // Generate list and store
        _genListLiteral(listIdx);
        _genStoreVarByName(lstName);

        // Init index
        _genPush(0);
        _genStoreVarByName(iName);

        // Loop condition: __i < len(__lst)
        uint256 loopStart = code.length - HEADER_SIZE;

        _genLoadVarByName(iName);
        _genLoadVarByName(lstName);
        _emitOp(OP_LIST_LEN);
        _emitOp(OP_LT);
        _emitOp(OP_JUMP_IF_FALSE);
        _emitUint32(0);
        uint256 exitJumpOffset = code.length - 4;

        // x = __lst[__i]
        _genLoadVarByName(lstName);
        _genLoadVarByName(iName);
        _emitOp(OP_LIST_GET);
        _genStoreVarByName(loopVar);

        // Body
        if (_c3(nodeIdx) != 0) _genBlock(_c3(nodeIdx));

        // Backpatch continue jumps to increment code
        uint256 incTarget = code.length - HEADER_SIZE;
        uint256 continueStart = _continueContextStart[_continueContextStart.length - 1];
        _backpatchContinues(continueStart, incTarget);

        // __i += 1
        _genLoadVarByName(iName);
        _genPush(1);
        _emitOp(OP_ADD);
        _genStoreVarByName(iName);

        // Jump back
        _emitOp(OP_JUMP_BACK);
        _emitUint32(loopStart);

        // Exit: normal exit lands here (start of else block if present)
        _patchUint32(exitJumpOffset, code.length - exitJumpOffset - 4);

        // Else block (executes on normal exit, skipped by break)
        if (elseBody != 0) _genBlock(elseBody);

        // Backpatch break jumps (land after else block)
        uint256 breakStart = _breakContextStart[_breakContextStart.length - 1];
        _backpatchBreaks(breakStart);
    }

    function _genForIterable(uint256 nodeIdx, uint256 iterableIdx, string memory loopVar, uint256 elseBody) internal {
        // General case: iterate over a variable that holds a list
        string memory iName = string.concat("__fi", _toString(_forTempCounter));
        string memory lstName = string.concat("__fl", _toString(_forTempCounter));
        _forTempCounter++;

        // Store iterable in temp
        _genExpr(iterableIdx);
        _genStoreVarByName(lstName);

        // Init index
        _genPush(0);
        _genStoreVarByName(iName);

        // Loop condition
        uint256 loopStart = code.length - HEADER_SIZE;

        _genLoadVarByName(iName);
        _genLoadVarByName(lstName);
        _emitOp(OP_LIST_LEN);
        _emitOp(OP_LT);
        _emitOp(OP_JUMP_IF_FALSE);
        _emitUint32(0);
        uint256 exitJumpOffset = code.length - 4;

        // x = lst[__i]
        _genLoadVarByName(lstName);
        _genLoadVarByName(iName);
        _emitOp(OP_LIST_GET);
        _genStoreVarByName(loopVar);

        // Body
        if (_c3(nodeIdx) != 0) _genBlock(_c3(nodeIdx));

        // Backpatch continue jumps to increment code
        uint256 incTarget = code.length - HEADER_SIZE;
        uint256 continueStart = _continueContextStart[_continueContextStart.length - 1];
        _backpatchContinues(continueStart, incTarget);

        // __i += 1
        _genLoadVarByName(iName);
        _genPush(1);
        _emitOp(OP_ADD);
        _genStoreVarByName(iName);

        // Jump back
        _emitOp(OP_JUMP_BACK);
        _emitUint32(loopStart);

        // Exit: normal exit lands here (start of else block if present)
        _patchUint32(exitJumpOffset, code.length - exitJumpOffset - 4);

        // Else block (executes on normal exit, skipped by break)
        if (elseBody != 0) _genBlock(elseBody);

        // Backpatch break jumps (land after else block)
        uint256 breakStart = _breakContextStart[_breakContextStart.length - 1];
        _backpatchBreaks(breakStart);
    }

    function _genForEnumerate(uint256 nodeIdx, uint256 iterIdx, uint256 tupleIdx, uint256 elseBody) internal {
        // for i, x in enumerate(lst) → i=index, x=lst[index]
        // iterIdx = enumerate(lst) FUNC_CALL, tupleIdx = (i, x) TUPLE_LITERAL
        uint256 lstArg = _ea(_ai(iterIdx)); // first arg to enumerate

        string memory iName = string.concat("__ei", _toString(_forTempCounter));
        string memory lstName = string.concat("__el", _toString(_forTempCounter));
        _forTempCounter++;

        // Store list
        _genExpr(lstArg);
        _genStoreVarByName(lstName);

        // Init counter
        _genPush(0);
        _genStoreVarByName(iName);

        // Get tuple target names
        uint256 tupleStart = _ai(tupleIdx);
        uint256 tupleCount = _ac(tupleIdx);
        string memory idxVar = _sv(_ea(tupleStart)); // first target = index
        string memory elemVar = tupleCount > 1 ? _sv(_ea(tupleStart + 1)) : idxVar; // second target = element

        // Loop condition: __ei < len(__el)
        uint256 loopStart = code.length - HEADER_SIZE;
        _genLoadVarByName(iName);
        _genLoadVarByName(lstName);
        _emitOp(OP_LIST_LEN);
        _emitOp(OP_LT);
        _emitOp(OP_JUMP_IF_FALSE);
        _emitUint32(0);
        uint256 exitJumpOffset = code.length - 4;

        // i = __ei
        _genLoadVarByName(iName);
        _genStoreVarByName(idxVar);

        // x = __el[__ei]
        _genLoadVarByName(lstName);
        _genLoadVarByName(iName);
        _emitOp(OP_LIST_GET);
        _genStoreVarByName(elemVar);

        // Body
        if (_c3(nodeIdx) != 0) _genBlock(_c3(nodeIdx));

        // Continue backpatch
        uint256 incTarget = code.length - HEADER_SIZE;
        uint256 continueStart = _continueContextStart[_continueContextStart.length - 1];
        _backpatchContinues(continueStart, incTarget);

        // __ei += 1
        _genLoadVarByName(iName);
        _genPush(1);
        _emitOp(OP_ADD);
        _genStoreVarByName(iName);

        // Jump back
        _emitOp(OP_JUMP_BACK);
        _emitUint32(loopStart);

        // Exit
        _patchUint32(exitJumpOffset, code.length - exitJumpOffset - 4);
        if (elseBody != 0) _genBlock(elseBody);
        uint256 breakStart = _breakContextStart[_breakContextStart.length - 1];
        _backpatchBreaks(breakStart);
    }

    function _genForZip(uint256 nodeIdx, uint256 iterIdx, uint256 tupleIdx, uint256 elseBody) internal {
        // for a, b in zip(lst1, lst2) → a=lst1[i], b=lst2[i]
        uint256 argStart = _ai(iterIdx);
        uint256 argCount = _ac(iterIdx);

        string memory iName = string.concat("__ei", _toString(_forTempCounter));
        _forTempCounter++;

        // Store each list and get target names
        string[] memory lstNames = new string[](argCount);
        for (uint256 i = 0; i < argCount; i++) {
            lstNames[i] = string.concat("__ez", _toString(_forTempCounter), "_", _toString(i));
            _genExpr(_ea(argStart + i));
            _genStoreVarByName(lstNames[i]);
        }

        // Init counter
        _genPush(0);
        _genStoreVarByName(iName);

        // Get tuple target names
        uint256 tupleStart = _ai(tupleIdx);
        uint256 tupleCount = _ac(tupleIdx);

        // Loop condition: __ei < min(len(lst_names))
        uint256 loopStart = code.length - HEADER_SIZE;
        _genLoadVarByName(iName);
        _genLoadVarByName(lstNames[0]);
        _emitOp(OP_LIST_LEN);
        _emitOp(OP_LT);
        for (uint256 i = 1; i < argCount; i++) {
            _genLoadVarByName(iName);
            _genLoadVarByName(lstNames[i]);
            _emitOp(OP_LIST_LEN);
            _emitOp(OP_LT);
            _emitOp(OP_AND);
        }
        _emitOp(OP_JUMP_IF_FALSE);
        _emitUint32(0);
        uint256 exitJumpOffset = code.length - 4;

        // Unpack: target[i] = lst[i][__ei]
        for (uint256 i = 0; i < tupleCount && i < argCount; i++) {
            _genLoadVarByName(lstNames[i]);
            _genLoadVarByName(iName);
            _emitOp(OP_LIST_GET);
            _genStoreVarByName(_sv(_ea(tupleStart + i)));
        }

        // Body
        if (_c3(nodeIdx) != 0) _genBlock(_c3(nodeIdx));

        // Continue backpatch
        uint256 incTarget = code.length - HEADER_SIZE;
        uint256 continueStart = _continueContextStart[_continueContextStart.length - 1];
        _backpatchContinues(continueStart, incTarget);

        // __ei += 1
        _genLoadVarByName(iName);
        _genPush(1);
        _emitOp(OP_ADD);
        _genStoreVarByName(iName);

        // Jump back
        _emitOp(OP_JUMP_BACK);
        _emitUint32(loopStart);

        // Exit
        _patchUint32(exitJumpOffset, code.length - exitJumpOffset - 4);
        if (elseBody != 0) _genBlock(elseBody);
        uint256 breakStart = _breakContextStart[_breakContextStart.length - 1];
        _backpatchBreaks(breakStart);
    }

    function _genMapBuiltin(uint256 nodeIdx) internal {
        // map(func, iterable) → desugar into for-loop building result list
        // nodeIdx = FUNC_CALL "map" with 2 args: arg0=func, arg1=iterable
        uint256 argStart = _ai(nodeIdx);
        uint256 funcArg = _ea(argStart);     // function name (IDENTIFIER_REF)
        uint256 iterArg = _ea(argStart + 1); // iterable

        string memory funcName = _sv(funcArg);

        string memory iName = string.concat("__mi", _toString(_forTempCounter));
        string memory lstName = string.concat("__ml", _toString(_forTempCounter));
        string memory resName = string.concat("__mr", _toString(_forTempCounter));
        _forTempCounter++;

        // Store iterable in temp
        _genExpr(iterArg);
        _genStoreVarByName(lstName);

        // Create empty result list
        _emitOp(OP_MAKE_LIST);
        _emitUint16(0);
        _genStoreVarByName(resName);

        // Init counter
        _genPush(0);
        _genStoreVarByName(iName);

        // Loop condition: i < len(lst)
        uint256 loopStart = code.length - HEADER_SIZE;
        _genLoadVarByName(iName);
        _genLoadVarByName(lstName);
        _emitOp(OP_LIST_LEN);
        _emitOp(OP_LT);
        _emitOp(OP_JUMP_IF_FALSE);
        _emitUint32(0);
        uint256 exitJumpOffset = code.length - 4;

        // Body: result.append(f(lst[i]))
        _genLoadVarByName(resName);          // push result list ID
        _genLoadVarByName(lstName);          // push lst
        _genLoadVarByName(iName);            // push i
        _emitOp(OP_LIST_GET);               // lst[i]
        _emitOp(OP_CALL);                    // call f with 1 arg
        _emitUint16(1);
        _emitUint32(0);                      // placeholder
        _backpatchFunc(funcName, code.length - 4);
        _emitOp(OP_LIST_APPEND);             // append return value to result

        // i += 1
        _genLoadVarByName(iName);
        _genPush(1);
        _emitOp(OP_ADD);
        _genStoreVarByName(iName);

        // Jump back
        _emitOp(OP_JUMP_BACK);
        _emitUint32(loopStart);

        // Exit
        _patchUint32(exitJumpOffset, code.length - exitJumpOffset - 4);

        // Push result list onto stack
        _genLoadVarByName(resName);
    }

    function _genFilterBuiltin(uint256 nodeIdx) internal {
        // filter(func, iterable) → desugar into for-loop building result list
        // nodeIdx = FUNC_CALL "filter" with 2 args: arg0=func, arg1=iterable
        uint256 argStart = _ai(nodeIdx);
        uint256 funcArg = _ea(argStart);     // function name (IDENTIFIER_REF)
        uint256 iterArg = _ea(argStart + 1); // iterable

        string memory funcName = _sv(funcArg);

        string memory iName = string.concat("__fi", _toString(_forTempCounter));
        string memory lstName = string.concat("__fl", _toString(_forTempCounter));
        string memory resName = string.concat("__fr", _toString(_forTempCounter));
        _forTempCounter++;

        // Store iterable in temp
        _genExpr(iterArg);
        _genStoreVarByName(lstName);

        // Create empty result list
        _emitOp(OP_MAKE_LIST);
        _emitUint16(0);
        _genStoreVarByName(resName);

        // Init counter
        _genPush(0);
        _genStoreVarByName(iName);

        // Loop condition: i < len(lst)
        uint256 loopStart = code.length - HEADER_SIZE;
        _genLoadVarByName(iName);
        _genLoadVarByName(lstName);
        _emitOp(OP_LIST_LEN);
        _emitOp(OP_LT);
        _emitOp(OP_JUMP_IF_FALSE);
        _emitUint32(0);
        uint256 exitJumpOffset = code.length - 4;

        // Body: if f(lst[i]): result.append(lst[i])
        _genLoadVarByName(lstName);          // push lst
        _genLoadVarByName(iName);            // push i
        _emitOp(OP_LIST_GET);               // lst[i] — arg for f
        _emitOp(OP_CALL);                    // call f with 1 arg
        _emitUint16(1);
        _emitUint32(0);                      // placeholder
        _backpatchFunc(funcName, code.length - 4);
        _emitOp(OP_JUMP_IF_FALSE);           // skip if f returns falsy
        _emitUint32(0);
        uint256 skipOffset = code.length - 4;

        // Append element to result
        _genLoadVarByName(resName);          // push result list ID
        _genLoadVarByName(lstName);          // push lst
        _genLoadVarByName(iName);            // push i
        _emitOp(OP_LIST_GET);               // lst[i]
        _emitOp(OP_LIST_APPEND);             // append element to result

        // Backpatch skip jump
        _patchUint32(skipOffset, code.length - skipOffset - 4);

        // i += 1
        _genLoadVarByName(iName);
        _genPush(1);
        _emitOp(OP_ADD);
        _genStoreVarByName(iName);

        // Jump back
        _emitOp(OP_JUMP_BACK);
        _emitUint32(loopStart);

        // Exit
        _patchUint32(exitJumpOffset, code.length - exitJumpOffset - 4);

        // Push result list onto stack
        _genLoadVarByName(resName);
    }

    function _genReturnStmt(uint256 nodeIdx) internal {
        if (_c1(nodeIdx) != 0) {
            _genExpr(_c1(nodeIdx));
        } else {
            _genPushNone();
        }
        _emitOp(OP_RETURN);
    }

    function _genClassDef(uint256 nodeIdx) internal {
        string memory className = _sv(nodeIdx);
        _classNames[keccak256(bytes(className))] = true;

        // Jump over method bodies (skip during module execution)
        _emitOp(OP_JUMP);
        _emitUint32(0); // placeholder
        uint256 jumpOverOffset = code.length - 4;

        // Process methods in class body (body is in child2)
        uint256 bodyNode = _c2(nodeIdx);
        uint256 bodyStart = _ai(bodyNode);
        uint256 bodyCount = _ac(bodyNode);
        uint256 methodCount = 0;

        // Track method info for MAKE_CLASS emission
        uint256[] memory methodHashes = new uint256[](bodyCount);
        uint256[] memory methodOffsets = new uint256[](bodyCount);

        for (uint256 i = 0; i < bodyCount; i++) {
            uint256 stmtIdx = _aux(bodyStart + i);
            if (_nt(stmtIdx) == NodeType.FUNCTION_DEF) {
                // Record method name hash
                string memory methodName = _sv(stmtIdx);
                methodHashes[methodCount] = uint256(keccak256(bytes(methodName)));
                if (keccak256(bytes(methodName)) == keccak256("__init__")) {
                    _classHasInit[keccak256(bytes(className))] = true;
                }

                // Jump over method body
                _emitOp(OP_JUMP);
                _emitUint32(0);
                uint256 methodJumpOffset = code.length - 4;

                // Record method offset
                methodOffsets[methodCount] = code.length - HEADER_SIZE;

                // Enter method scope
                currentScope++;

                // Setup frame (self + params)
                uint256 paramCount = _ac(stmtIdx);
                _emitOp(OP_SETUP_FRAME);
                _emitUint16(uint16(paramCount));

                // Store self (slot 0) — already on stack from CALL_METHOD
                // Store params from stack into local vars
                for (uint256 j = paramCount; j > 0; j--) {
                    string memory param = _sv(_ea(_ai(stmtIdx) + j - 1));
                    uint256 slot = _getVarSlot(param);
                    _emitOp(OP_STORE_VAR);
                    _emitByte(1); // frame 1 (local)
                    _emitByte(uint8(slot));
                }

                // Generate method body
                if (_c2(stmtIdx) != 0) _genBlock(_c2(stmtIdx));

                // Implicit return None
                _genPushNone();
                _emitOp(OP_RETURN);

                // Exit method scope
                currentScope--;

                // Backpatch method jump
                _patchUint32(methodJumpOffset, code.length - methodJumpOffset - 4);

                methodCount++;
            }
        }

        // Backpatch outer jump to land here (after method bodies, before MAKE_CLASS)
        _patchUint32(jumpOverOffset, code.length - jumpOverOffset - 4);

        // Emit MAKE_CLASS: push parent class ID, then (name_hash, func_offset) pairs, then MAKE_CLASS
        if (_c1(nodeIdx) != 0) {
            _genExpr(_c1(nodeIdx)); // push parent class ID
        } else {
            _genPush(0); // no parent
        }
        for (uint256 i = 0; i < methodCount; i++) {
            _genPush(methodHashes[i]);
            _genPush(methodOffsets[i]);
        }
        _emitOp(OP_MAKE_CLASS);
        _emitUint16(uint16(methodCount));

        // Store class name
        _genStoreVarByName(className);
    }

    function _genTryStmt(uint256 nodeIdx) internal {
        // child1 = try body
        // child2 = finally branch (0 if none)
        // auxIndex = except branches start, auxCount = except count

        // Emit TRY_BEGIN with placeholder handler PC
        _emitOp(OP_TRY_BEGIN);
        _emitUint32(0); // placeholder — backpatch to except handler
        uint256 tryBeginPatch = code.length - 4;

        // Try body
        if (_c1(nodeIdx) != 0) _genBlock(_c1(nodeIdx));

        // Try ended successfully — jump over except blocks
        _emitOp(OP_TRY_END);
        _emitOp(OP_JUMP);
        _emitUint32(0); // placeholder — backpatch to after all except/finally
        uint256 jumpOverPatch = code.length - 4;

        // Backpatch TRY_BEGIN handler to here (except handler)
        _patchUint32(tryBeginPatch, code.length - tryBeginPatch - 4);

        // Except branches
        uint256 exceptStart = _ai(nodeIdx);
        uint256 exceptCount = _ac(nodeIdx);
        for (uint256 i = 0; i < exceptCount; i++) {
            uint256 exceptIdx = _ea(exceptStart + i);
            // Catch the exception
            _emitOp(OP_CATCH);
            // Except body
            if (_c2(exceptIdx) != 0) _genBlock(_c2(exceptIdx));
            // Jump to after finally
            if (_c2(nodeIdx) != 0 || i < exceptCount - 1) {
                _emitOp(OP_JUMP);
                _emitUint32(0);
                // We'd need to backpatch this, but for simplicity, just emit
            }
        }

        // If no except branches, we still need to handle the case
        if (exceptCount == 0) {
            // No except — just catch and discard
            _emitOp(OP_CATCH);
            _emitOp(OP_POP);
        }

        // Finally branch
        if (_c2(nodeIdx) != 0) {
            _genBlock(_c2(nodeIdx));
        }

        // Backpatch jump over
        _patchUint32(jumpOverPatch, code.length - jumpOverPatch - 4);
    }

    function _genRaiseStmt(uint256 nodeIdx) internal {
        if (_c1(nodeIdx) != 0) {
            _genExpr(_c1(nodeIdx));
        } else {
            _genPush(0); // raise with no value
        }
        _emitOp(OP_RAISE);
    }

    // ==================== Expression Generation ====================

    function _genExpr(uint256 nodeIdx) internal {
        NodeType nt = _nt(nodeIdx);

        if (nt == NodeType.INT_LITERAL) {
            _genPush(_iv(nodeIdx));
        } else if (nt == NodeType.FLOAT_LITERAL) {
            _genPushFloat(_iv(nodeIdx)); // emit tagged float
        } else if (nt == NodeType.STRING_LITERAL) {
            _genPushString(_sv(nodeIdx));
        } else if (nt == NodeType.BOOL_LITERAL) {
            _genPush(_iv(nodeIdx));
        } else if (nt == NodeType.NONE_LITERAL) {
            _genPushNone();
        } else if (nt == NodeType.IDENTIFIER_REF) {
            _genLoadVar(nodeIdx);
        } else if (nt == NodeType.BINARY_OP) {
            _genBinaryOp(nodeIdx);
        } else if (nt == NodeType.UNARY_OP) {
            _genExpr(_c1(nodeIdx));
            if (UnaryOpType(_iv(nodeIdx)) == UnaryOpType.NEG) _emitOp(OP_NEG);
        } else if (nt == NodeType.COMPARISON) {
            _genComparison(nodeIdx);
        } else if (nt == NodeType.BOOL_AND) {
            _genExpr(_c1(nodeIdx));
            _genExpr(_c2(nodeIdx));
            _emitOp(OP_AND);
        } else if (nt == NodeType.BOOL_OR) {
            _genExpr(_c1(nodeIdx));
            _genExpr(_c2(nodeIdx));
            _emitOp(OP_OR);
        } else if (nt == NodeType.BOOL_NOT) {
            _genExpr(_c1(nodeIdx));
            _emitOp(OP_NOT);
        } else if (nt == NodeType.TERNARY_EXPR) {
            // a if cond else b
            _genExpr(_c2(nodeIdx)); // condition
            _emitOp(OP_JUMP_IF_FALSE);
            _emitUint32(0); // placeholder
            uint256 falseJumpOffset = code.length - 4;
            _genExpr(_c1(nodeIdx)); // true value
            _emitOp(OP_JUMP);
            _emitUint32(0); // placeholder
            uint256 endJumpOffset = code.length - 4;
            _patchUint32(falseJumpOffset, code.length - falseJumpOffset - 4);
            _genExpr(_c3(nodeIdx)); // false value
            _patchUint32(endJumpOffset, code.length - endJumpOffset - 4);
        } else if (nt == NodeType.FUNC_CALL) {
            _genFuncCall(nodeIdx);
        } else if (nt == NodeType.LIST_LITERAL) {
            _genListLiteral(nodeIdx);
        } else if (nt == NodeType.TUPLE_LITERAL) {
            _genTupleLiteral(nodeIdx);
        } else if (nt == NodeType.INDEX_ACCESS) {
            _genExpr(_c1(nodeIdx)); // target
            _genExpr(_c2(nodeIdx)); // index
            _emitOp(OP_LIST_GET); // default to list; VM handles dict at runtime
        } else if (nt == NodeType.DICT_LITERAL) {
            _genDictLiteral(nodeIdx);
        } else if (nt == NodeType.SET_LITERAL) {
            _genSetLiteral(nodeIdx);
        } else if (nt == NodeType.DICT_ACCESS) {
            _genExpr(_c1(nodeIdx)); // dict
            _genExpr(_c2(nodeIdx)); // key
            _emitOp(OP_DICT_GET);
        } else if (nt == NodeType.SLICE_ACCESS) {
            _genExpr(_c1(nodeIdx)); // target string
            // Push start index (0 if default)
            if (_c2(nodeIdx) == 0) {
                _genPush(0);
            } else {
                _genExpr(_c2(nodeIdx));
            }
            // Push end index (0 if default — VM will use string length)
            if (_c3(nodeIdx) == 0) {
                _genPush(0);
            } else {
                _genExpr(_c3(nodeIdx));
            }
            _emitOp(OP_STR_SLICE);
        } else if (nt == NodeType.ATTR_ACCESS) {
            _genExpr(_c1(nodeIdx)); // push object
            _emitOp(OP_LOAD_ATTR);
            _emitUint256(uint256(keccak256(bytes(_sv(nodeIdx)))));
        } else if (nt == NodeType.METHOD_CALL) {
            string memory methodName = _sv(nodeIdx);
            uint256 mcArgCount = _ac(nodeIdx);
            bytes4 methodHash = bytes4(keccak256(bytes(methodName)));

            // Check for string methods first
            if (methodHash == bytes4(keccak256("upper")) && mcArgCount == 0) {
                _genExpr(_c1(nodeIdx));
                _emitOp(OP_STR_UPPER);
            } else if (methodHash == bytes4(keccak256("lower")) && mcArgCount == 0) {
                _genExpr(_c1(nodeIdx));
                _emitOp(OP_STR_LOWER);
            } else if (methodHash == bytes4(keccak256("contains")) && mcArgCount == 1) {
                _genExpr(_c1(nodeIdx));
                _genExpr(_ea(_ai(nodeIdx)));
                _emitOp(OP_STR_CONTAINS);
            } else if (methodHash == bytes4(keccak256("split")) && mcArgCount == 1) {
                _genExpr(_c1(nodeIdx));
                _genExpr(_ea(_ai(nodeIdx)));
                _emitOp(OP_STR_SPLIT);
            } else if (methodHash == bytes4(keccak256("charAt")) && mcArgCount == 1) {
                _genExpr(_c1(nodeIdx));
                _genExpr(_ea(_ai(nodeIdx)));
                _emitOp(OP_STR_CHAR_AT);
            } else if (methodHash == bytes4(keccak256("keys")) && mcArgCount == 0) {
                _genExpr(_c1(nodeIdx));
                _emitOp(OP_DICT_KEYS);
            } else if (methodHash == bytes4(keccak256("values")) && mcArgCount == 0) {
                _genExpr(_c1(nodeIdx));
                _emitOp(OP_DICT_VALUES);
            } else if (methodHash == bytes4(keccak256("items")) && mcArgCount == 0) {
                _genExpr(_c1(nodeIdx));
                _emitOp(OP_DICT_ITEMS);
            } else if (methodHash == bytes4(keccak256("get")) && mcArgCount == 2) {
                _genExpr(_c1(nodeIdx));
                _genExpr(_ea(_ai(nodeIdx)));
                _genExpr(_ea(_ai(nodeIdx) + 1));
                _emitOp(OP_DICT_GET_DEFAULT);
            } else if (methodHash == bytes4(keccak256("update")) && mcArgCount == 1) {
                _genExpr(_c1(nodeIdx));
                _genExpr(_ea(_ai(nodeIdx)));
                _emitOp(OP_DICT_UPDATE);
            } else {
                // Object method call
                _genExpr(_c1(nodeIdx)); // push object
                _emitOp(OP_LOAD_ATTR);
                _emitUint256(uint256(keccak256(bytes(methodName))));
                uint256 mcArgStart = _ai(nodeIdx);
                for (uint256 i = 0; i < mcArgCount; i++) {
                    _genExpr(_ea(mcArgStart + i));
                }
                _emitOp(OP_CALL_METHOD);
                _emitUint16(uint16(mcArgCount));
            }
        } else if (nt == NodeType.FSTRING_EXPR) {
            _genFStringExpr(nodeIdx);
        }
    }

    function _genBinaryOp(uint256 nodeIdx) internal {
        BinaryOpType op = BinaryOpType(_iv(nodeIdx));

        // String formatting: "hello %s" % arg
        if (op == BinaryOpType.MOD && _nt(_c1(nodeIdx)) == NodeType.STRING_LITERAL) {
            _genStringFormat(nodeIdx);
            return;
        }

        _genExpr(_c1(nodeIdx));
        _genExpr(_c2(nodeIdx));
        if (op == BinaryOpType.ADD) _emitOp(OP_ADD);
        else if (op == BinaryOpType.SUB) _emitOp(OP_SUB);
        else if (op == BinaryOpType.MUL) _emitOp(OP_MUL);
        else if (op == BinaryOpType.DIV) _emitOp(OP_DIV);
        else if (op == BinaryOpType.FDIV) _emitOp(OP_DIV); // integer floor div
        else if (op == BinaryOpType.MOD) _emitOp(OP_MOD);
        else if (op == BinaryOpType.POW) _emitOp(OP_POW);
    }

    function _genComparison(uint256 nodeIdx) internal {
        _genExpr(_c1(nodeIdx));
        _genExpr(_c2(nodeIdx));
        CompOpType op = CompOpType(_iv(nodeIdx));
        if (op == CompOpType.EQ) _emitOp(OP_EQ);
        else if (op == CompOpType.NEQ) _emitOp(OP_NEQ);
        else if (op == CompOpType.LT) _emitOp(OP_LT);
        else if (op == CompOpType.GT) _emitOp(OP_GT);
        else if (op == CompOpType.LTE) _emitOp(OP_LTE);
        else if (op == CompOpType.GTE) _emitOp(OP_GTE);
        else if (op == CompOpType.IN) _emitOp(OP_IN);
        else if (op == CompOpType.NOT_IN) { _emitOp(OP_IN); _emitOp(OP_NOT); }
    }

    function _genStringFormat(uint256 nodeIdx) internal {
        // "hello %s" % arg or "hello %s %d" % (a, b)
        string memory fmt = _sv(_c1(nodeIdx));
        uint256 rightSide = _c2(nodeIdx);

        // For tuple args: extract elements; for single arg: use directly
        // For simplicity, handle single %s/%d replacement
        bytes memory fmtBytes = bytes(fmt);
        bool firstPart = true;
        uint256 i = 0;
        bool argConsumed = false;

        while (i < fmtBytes.length) {
            // Find next % or end
            uint256 textStart = i;
            while (i < fmtBytes.length && fmtBytes[i] != 0x25) { // not %
                i++;
            }
            // Emit text part if non-empty
            if (i > textStart) {
                bytes memory textPart = new bytes(i - textStart);
                for (uint256 j = 0; j < i - textStart; j++) {
                    textPart[j] = fmtBytes[textStart + j];
                }
                if (firstPart) {
                    _genPushString(string(textPart));
                    firstPart = false;
                } else {
                    _genPushString(string(textPart));
                    _emitOp(OP_STR_CONCAT);
                }
            }
            // Check if we hit %
            if (i < fmtBytes.length && fmtBytes[i] == 0x25) {
                i++; // skip %
                if (i < fmtBytes.length) {
                    bytes1 spec = fmtBytes[i];
                    i++; // skip specifier
                    if (!argConsumed) {
                        _genExpr(rightSide);
                        // Convert to string for both %s and %d
                        _emitOp(OP_INT_TO_STR);
                        argConsumed = true;
                    }
                    if (firstPart) {
                        firstPart = false;
                    } else {
                        _emitOp(OP_STR_CONCAT);
                    }
                }
            }
        }
        if (firstPart) {
            _genPushString("");
        }
    }

    function _genFStringExpr(uint256 nodeIdx) internal {
        // F-string: f"hello {name} world"
        // Split content on { and } to get text parts and variable references
        string memory content = _sv(nodeIdx);
        bytes memory cb = bytes(content);

        // Parse parts: alternating text and variable names
        // Start with empty string, concatenate each part
        bool firstPart = true;
        uint256 i = 0;
        while (i < cb.length) {
            // Find next { or end
            uint256 textStart = i;
            while (i < cb.length && cb[i] != 0x7B && cb[i] != 0x7D) { // not { or }
                i++;
            }
            // Emit text part if non-empty
            if (i > textStart) {
                bytes memory textPart = new bytes(i - textStart);
                for (uint256 j = 0; j < i - textStart; j++) {
                    textPart[j] = cb[textStart + j];
                }
                if (firstPart) {
                    _genPushString(string(textPart));
                    firstPart = false;
                } else {
                    _genPushString(string(textPart));
                    _emitOp(OP_STR_CONCAT);
                }
            }
            // Check if we hit a {
            if (i < cb.length && cb[i] == 0x7B) {
                i++; // skip {
                uint256 varStart = i;
                while (i < cb.length && cb[i] != 0x7D) {
                    i++;
                }
                // Extract variable name
                bytes memory varName = new bytes(i - varStart);
                for (uint256 j = 0; j < i - varStart; j++) {
                    varName[j] = cb[varStart + j];
                }
                if (i < cb.length && cb[i] == 0x7D) i++; // skip }

                // Generate code to load variable and convert to string
                string memory varNameStr = string(varName);
                // Check if it's a string literal (needs str() conversion)
                // For now, treat as variable reference
                _genLoadVarByName(varNameStr);
                // Convert to string (handles int->str)
                _emitOp(OP_INT_TO_STR);

                if (firstPart) {
                    firstPart = false;
                } else {
                    _emitOp(OP_STR_CONCAT);
                }
            }
        }
        // If empty f-string, push empty string
        if (firstPart) {
            _genPushString("");
        }
    }

    function _genFuncCall(uint256 nodeIdx) internal {
        string memory name = _sv(nodeIdx);
        uint256 argCount = _ac(nodeIdx);

        // Check for keyword arguments
        bool hasKwargs = false;
        for (uint256 i = 0; i < argCount; i++) {
            if (_nt(_ea(_ai(nodeIdx) + i)) == NodeType.KEYWORD_ARG) { hasKwargs = true; break; }
        }

        if (hasKwargs) {
            _genFuncCallWithKwargs(name, nodeIdx);
            return;
        }

        // Push arguments
        for (uint256 i = 0; i < argCount; i++) {
            _genExpr(_ea(_ai(nodeIdx) + i));
        }

        // Built-in: print
        if (keccak256(bytes(name)) == keccak256("print")) {
            // Check if single string argument — use PRINT_STR
            if (argCount == 1) {
                uint256 argNode = _ea(_ai(nodeIdx));
                if (_nt(argNode) == NodeType.STRING_LITERAL) {
                    // Already pushed string table index; use PRINT_STR
                    _emitOp(OP_PRINT_STR);
                    _genPushNone();
                    return;
                }
            }
            _emitOp(OP_PRINT);
            _emitByte(uint8(argCount));
            _genPushNone(); // return None so EXPR_STMT can pop it
            return;
        }

        // Built-in: len — dispatch based on argument type
        if (keccak256(bytes(name)) == keccak256("len")) {
            if (argCount == 1) {
                uint256 argNode = _ea(_ai(nodeIdx));
                NodeType argType = _nt(argNode);
                if (argType == NodeType.STRING_LITERAL) {
                    _emitOp(OP_STR_LEN);
                } else if (argType == NodeType.DICT_LITERAL || argType == NodeType.DICT_ACCESS) {
                    _emitOp(OP_DICT_LEN);
                } else if (argType == NodeType.SET_LITERAL) {
                    _emitOp(OP_SET_LEN);
                } else {
                    // For IDENTIFIER_REF and other types, use LIST_LEN
                    // VM will handle type checking at runtime
                    _emitOp(OP_LIST_LEN);
                }
            } else {
                _emitOp(OP_LIST_LEN);
            }
            return;
        }

        // Built-in: str — convert int to string
        if (keccak256(bytes(name)) == keccak256("str") && argCount == 1) {
            _emitOp(OP_INT_TO_STR);
            return;
        }

        // Built-in: int — convert string to int
        if (keccak256(bytes(name)) == keccak256("int") && argCount == 1) {
            _emitOp(OP_STR_TO_INT);
            return;
        }

        // Built-in: isinstance(x, type) — check runtime type
        if (keccak256(bytes(name)) == keccak256("isinstance") && argCount == 2) {
            uint256 typeArg = _ea(_ai(nodeIdx) + 1);
            if (_nt(typeArg) == NodeType.IDENTIFIER_REF) {
                bytes32 typeHash = keccak256(bytes(_sv(typeArg)));
                uint256 typeTag;
                if (typeHash == keccak256("int")) typeTag = 0;
                else if (typeHash == keccak256("str")) typeTag = 1;
                else if (typeHash == keccak256("list")) typeTag = 2;
                else if (typeHash == keccak256("bool")) typeTag = 3;
                else if (typeHash == keccak256("NoneType")) typeTag = 4;
                else if (typeHash == keccak256("dict")) typeTag = 5;
                else if (typeHash == keccak256("set")) typeTag = 6;
                else if (typeHash == keccak256("tuple")) typeTag = 7;
                else typeTag = 0; // default to int
                _genExpr(_ea(_ai(nodeIdx))); // push value
                _genPush(typeTag);
                _emitOp(OP_ISINSTANCE);
                return;
            }
        }

        // Built-in: type(x) — return type tag as int
        if (keccak256(bytes(name)) == keccak256("type") && argCount == 1) {
            _emitOp(OP_TYPEOF);
            return;
        }

        // Built-in: map(func, iterable) — apply func to each element, collect results
        if (keccak256(bytes(name)) == keccak256("map") && argCount == 2) {
            _genMapBuiltin(nodeIdx);
            return;
        }

        // Built-in: filter(func, iterable) — keep elements where func returns truthy
        if (keccak256(bytes(name)) == keccak256("filter") && argCount == 2) {
            _genFilterBuiltin(nodeIdx);
            return;
        }

        // String methods (called as method calls with object as first arg)
        if (argCount >= 1) {
            bytes4 nameHash = bytes4(keccak256(bytes(name)));

            // s.upper() — 1 arg (the string)
            if (nameHash == bytes4(keccak256("upper")) && argCount == 1) {
                _emitOp(OP_STR_UPPER);
                return;
            }

            // s.lower() — 1 arg (the string)
            if (nameHash == bytes4(keccak256("lower")) && argCount == 1) {
                _emitOp(OP_STR_LOWER);
                return;
            }

            // s.contains(sub) — 2 args (string, substring)
            if (nameHash == bytes4(keccak256("contains")) && argCount == 2) {
                _emitOp(OP_STR_CONTAINS);
                return;
            }

            // s.split(delim) — 2 args (string, delimiter)
            if (nameHash == bytes4(keccak256("split")) && argCount == 2) {
                _emitOp(OP_STR_SPLIT);
                return;
            }

            // s.charAt(i) — 2 args (string, index)
            if (nameHash == bytes4(keccak256("charAt")) && argCount == 2) {
                _emitOp(OP_STR_CHAR_AT);
                return;
            }
        }

        // Class instantiation
        if (_classNames[keccak256(bytes(name))]) {
            // Push class ID (stored as variable)
            _genLoadVarByName(name);
            _emitOp(OP_MAKE_INSTANCE);
            // Now instance_id is on stack

            if (_classHasInit[keccak256(bytes(name))]) {
                // DUP instance_id (keep for final result)
                _emitOp(OP_DUP);
                // LOAD_ATTR __init__ → pushes func_offset and instance_id
                _emitOp(OP_LOAD_ATTR);
                _emitUint256(uint256(keccak256("__init__")));
                // Push arguments
                for (uint256 i = 0; i < argCount; i++) {
                    _genExpr(_ea(_ai(nodeIdx) + i));
                }
                // Call __init__
                _emitOp(OP_CALL_METHOD);
                _emitUint16(uint16(argCount));
                // POP __init__'s return value (None)
                _emitOp(OP_POP);
            }
            return;
        }

        // User function — fill in default parameters if needed
        argCount = _fillDefaults(name, argCount);

        _emitOp(OP_CALL);
        _emitUint16(uint16(argCount));
        _emitUint32(0); // placeholder — backpatch after all functions are defined
        _backpatchFunc(name, code.length - 4);
    }

    function _fillDefaults(string memory name, uint256 argCount) internal returns (uint256) {
        uint256 expected = parser.getFuncParamCount(name);
        uint256 defCnt = parser.getFuncDefaultCount(name);
        if (expected == 0 || argCount >= expected || defCnt == 0) return argCount;
        uint256 firstDef = expected - defCnt;
        for (uint256 i = argCount; i < expected; i++) {
            uint256 di = i - firstDef;
            if (di < defCnt) {
                _genExpr(_c1(parser.getFuncDefaultNode(name, di)));
            }
        }
        return expected;
    }

    function _genFuncCallWithKwargs(string memory name, uint256 nodeIdx) internal {
        uint256 argCount = _ac(nodeIdx);
        uint256 argStart = _ai(nodeIdx);
        uint256 expected = parser.getFuncParamCount(name);
        uint256 defCnt = parser.getFuncDefaultCount(name);
        uint256 paramStart = parser.getFuncParamStart(name);

        // Initialize _kwargOrder with type(uint256).max = "not provided"
        while (_kwargOrder.length > 0) _kwargOrder.pop();
        for (uint256 i = 0; i < expected; i++) {
            _kwargOrder.push(type(uint256).max);
        }

        // Place positional args
        uint256 posIdx = 0;
        for (uint256 i = 0; i < argCount; i++) {
            uint256 argNode = _ea(argStart + i);
            if (_nt(argNode) != NodeType.KEYWORD_ARG) {
                _kwargOrder[posIdx] = argNode;
                posIdx++;
            }
        }

        // Place keyword args by matching name to param position
        for (uint256 i = 0; i < argCount; i++) {
            uint256 argNode = _ea(argStart + i);
            if (_nt(argNode) == NodeType.KEYWORD_ARG) {
                string memory kwName = _sv(argNode);
                for (uint256 j = 0; j < expected; j++) {
                    uint256 paramNode = parser.getExprAuxData(paramStart + j);
                    if (keccak256(bytes(parser.getStrValue(paramNode))) == keccak256(bytes(kwName))) {
                        _kwargOrder[j] = _c1(argNode);
                        break;
                    }
                }
            }
        }

        // Fill defaults for remaining slots
        uint256 firstDef = expected - defCnt;
        for (uint256 i = 0; i < expected; i++) {
            if (_kwargOrder[i] == type(uint256).max) {
                uint256 di = i - firstDef;
                if (di < defCnt) {
                    _kwargOrder[i] = _c1(parser.getFuncDefaultNode(name, di));
                }
            }
        }

        // Generate code: push args in param order
        for (uint256 i = 0; i < expected; i++) {
            _genExpr(_kwargOrder[i]);
        }

        // Emit CALL
        _emitOp(OP_CALL);
        _emitUint16(uint16(expected));
        _emitUint32(0);
        _backpatchFunc(name, code.length - 4);
    }

    function _genListLiteral(uint256 nodeIdx) internal {
        uint256 elemCount = _ac(nodeIdx);
        // Push elements in reverse order (so first element is on top after creation)
        for (uint256 i = elemCount; i > 0; i--) {
            _genExpr(_ea(_ai(nodeIdx) + i - 1));
        }
        _emitOp(OP_MAKE_LIST);
        _emitUint16(uint16(elemCount));
    }

    function _genTupleLiteral(uint256 nodeIdx) internal {
        uint256 elemCount = _ac(nodeIdx);
        // Push elements in reverse order (so first element is on top after creation)
        for (uint256 i = elemCount; i > 0; i--) {
            _genExpr(_ea(_ai(nodeIdx) + i - 1));
        }
        _emitOp(OP_MAKE_TUPLE);
        _emitUint16(uint16(elemCount));
    }

    function _genDictLiteral(uint256 nodeIdx) internal {
        uint256 pairCount = _ac(nodeIdx);
        // Push key-value pairs in reverse order: [k0, v0, k1, v1, ...] → push last pair first
        for (uint256 i = pairCount; i > 0; i--) {
            _genExpr(_ea(_ai(nodeIdx) + (i - 1) * 2 + 1)); // value
            _genExpr(_ea(_ai(nodeIdx) + (i - 1) * 2));     // key
        }
        _emitOp(OP_MAKE_DICT);
        _emitUint16(uint16(pairCount));
    }

    function _genSetLiteral(uint256 nodeIdx) internal {
        uint256 elemCount = _ac(nodeIdx);
        // Push elements in reverse order
        for (uint256 i = elemCount; i > 0; i--) {
            _genExpr(_ea(_ai(nodeIdx) + i - 1));
        }
        _emitOp(OP_MAKE_SET);
        _emitUint16(uint16(elemCount));
    }

    // ==================== Variable Helpers ====================

    function _genLoadVar(uint256 nodeIdx) internal {
        string memory name = _sv(nodeIdx);
        bytes32 key = keccak256(bytes(name));
        uint256 slot = varSlots[currentScope][key];
        if (slot == 0 && varCount[currentScope] == 0) {
            // Try global scope
            slot = varSlots[0][key];
        }
        _emitOp(OP_LOAD_VAR);
        _emitByte(uint8(currentScope > 0 ? 1 : 0)); // frame: 1 if local, 0 if global
        _emitByte(uint8(slot));
    }

    function _genStoreVar(uint256 nodeIdx) internal {
        string memory name = _sv(nodeIdx);
        bytes32 key = keccak256(bytes(name));
        if (varSlots[currentScope][key] == 0 && varCount[currentScope] == 0) {
            // New variable
            varCount[currentScope]++;
            varSlots[currentScope][key] = varCount[currentScope];
        } else if (varSlots[currentScope][key] == 0) {
            varCount[currentScope]++;
            varSlots[currentScope][key] = varCount[currentScope];
        }
        uint256 slot = varSlots[currentScope][key];
        _emitOp(OP_STORE_VAR);
        _emitByte(uint8(currentScope > 0 ? 1 : 0));
        _emitByte(uint8(slot));
    }

    function _getVarSlot(string memory name) internal returns (uint256) {
        bytes32 key = keccak256(bytes(name));
        if (varSlots[currentScope][key] == 0) {
            varCount[currentScope]++;
            varSlots[currentScope][key] = varCount[currentScope];
        }
        return varSlots[currentScope][key];
    }

    function _genPushNone() internal {
        _genPush(type(uint256).max);
    }

    function _genPushFloat(uint256 scaledValue) internal {
        _genPush((uint256(FLOAT_TAG) << FLOAT_TAG_SHIFT) | scaledValue);
    }

    function _genPush(uint256 value) internal {
        _emitOp(OP_PUSH);
        _emitUint256(value);
    }

    function _genPushString(string memory s) internal {
        uint256 idx = _getStringIndex(s);
        _genPush(idx + STATIC_STR_OFFSET);
    }

    function _getStringIndex(string memory s) internal returns (uint256) {
        bytes32 key = keccak256(bytes(s));
        if (stringCached[key]) return stringIndex[key];
        uint256 idx = stringTable.length;
        bytes memory sb = bytes(s);
        // 2-byte length prefix
        stringTable.push(bytes1(uint8(sb.length >> 8)));
        stringTable.push(bytes1(uint8(sb.length & 0xFF)));
        for (uint256 i = 0; i < sb.length; i++) {
            stringTable.push(sb[i]);
        }
        stringIndex[key] = idx;
        stringCached[key] = true;
        return idx;
    }

    // ==================== For-loop & Break/Continue Helpers ====================

    function _genStoreVarByName(string memory name) internal {
        bytes32 key = keccak256(bytes(name));
        if (varSlots[currentScope][key] == 0 && varCount[currentScope] == 0) {
            varCount[currentScope]++;
            varSlots[currentScope][key] = varCount[currentScope];
        } else if (varSlots[currentScope][key] == 0) {
            varCount[currentScope]++;
            varSlots[currentScope][key] = varCount[currentScope];
        }
        uint256 slot = varSlots[currentScope][key];
        _emitOp(OP_STORE_VAR);
        _emitByte(uint8(currentScope > 0 ? 1 : 0));
        _emitByte(uint8(slot));
    }

    function _genLoadVarByName(string memory name) internal {
        bytes32 key = keccak256(bytes(name));
        uint256 slot = varSlots[currentScope][key];
        if (slot == 0 && varCount[currentScope] == 0) {
            slot = varSlots[0][key];
        }
        _emitOp(OP_LOAD_VAR);
        _emitByte(uint8(currentScope > 0 ? 1 : 0));
        _emitByte(uint8(slot));
    }

    function _backpatchBreaks(uint256 fromIndex) internal {
        for (uint256 i = fromIndex; i < _breakPatches.length; i++) {
            _patchUint32(_breakPatches[i], code.length - _breakPatches[i] - 4);
        }
        while (_breakPatches.length > fromIndex) {
            _breakPatches.pop();
        }
    }

    function _backpatchContinues(uint256 fromIndex, uint256 target) internal {
        for (uint256 i = fromIndex; i < _continuePatches.length; i++) {
            _patchUint32(_continuePatches[i], target);
        }
        while (_continuePatches.length > fromIndex) {
            _continuePatches.pop();
        }
    }

    function _toString(uint256 value) internal pure returns (string memory) {
        if (value == 0) return "0";
        uint256 temp = value;
        uint256 digits;
        while (temp != 0) { digits++; temp /= 10; }
        bytes memory buffer = new bytes(digits);
        while (value != 0) {
            digits--;
            buffer[digits] = bytes1(uint8(48 + value % 10));
            value /= 10;
        }
        return string(buffer);
    }

    // ==================== Bytecode Emission ====================

    function _emitOp(uint8 op) internal {
        code.push(bytes1(op));
    }

    function _emitByte(uint8 b) internal {
        code.push(bytes1(b));
    }

    function _emitUint16(uint16 v) internal {
        code.push(bytes1(uint8(v >> 8)));
        code.push(bytes1(uint8(v & 0xFF)));
    }

    function _emitUint32(uint256 v) internal {
        code.push(bytes1(uint8((v >> 24) & 0xFF)));
        code.push(bytes1(uint8((v >> 16) & 0xFF)));
        code.push(bytes1(uint8((v >> 8) & 0xFF)));
        code.push(bytes1(uint8(v & 0xFF)));
    }

    function _emitUint256(uint256 v) internal {
        for (uint256 i = 0; i < 32; i++) {
            code.push(bytes1(uint8((v >> (8 * (31 - i))) & 0xFF)));
        }
    }

    function _patchUint32(uint256 offset, uint256 value) internal {
        code[offset] = bytes1(uint8((value >> 24) & 0xFF));
        code[offset + 1] = bytes1(uint8((value >> 16) & 0xFF));
        code[offset + 2] = bytes1(uint8((value >> 8) & 0xFF));
        code[offset + 3] = bytes1(uint8(value & 0xFF));
    }

    function _backpatchFunc(string memory name, uint256 offset) internal {
        bytes32 key = keccak256(bytes(name));
        if (funcOffsets[key] != 0) {
            _patchUint32(offset, funcOffsets[key]);
        }
        // If not found yet, leave as 0 — requires two-pass or forward declaration
    }

    // ==================== Parser Accessors ====================

    function _nt(uint256 idx) internal view returns (NodeType) { return parser.getNodeType(idx); }
    function _c1(uint256 idx) internal view returns (uint256) { return parser.getChild1(idx); }
    function _c2(uint256 idx) internal view returns (uint256) { return parser.getChild2(idx); }
    function _c3(uint256 idx) internal view returns (uint256) { return parser.getChild3(idx); }
    function _ai(uint256 idx) internal view returns (uint256) { return parser.getAuxIndex(idx); }
    function _ac(uint256 idx) internal view returns (uint256) { return parser.getAuxCount(idx); }
    function _iv(uint256 idx) internal view returns (uint256) { return parser.getIntValue(idx); }
    function _sv(uint256 idx) internal view returns (string memory) { return parser.getStrValue(idx); }
    function _aux(uint256 idx) internal view returns (uint256) { return parser.getAuxData(idx); }
    function _ea(uint256 idx) internal view returns (uint256) { return parser.getExprAuxData(idx); }

    // ==================== Public Getters ====================

    function getCode() public view returns (bytes memory) { return code; }
    function getCodeLength() public view returns (uint256) { return code.length; }
}
