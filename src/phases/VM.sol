// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract VM {
    // Stack
    uint256[] private stack;

    // Call frames: each frame has local variables
    // frameLocals[frameIndex][varIndex] = value
    mapping(uint256 => mapping(uint256 => uint256)) private frameLocals;
    uint256 private frameCount;
    uint256[] private frameVarCounts;

    // Return stack (for function calls)
    uint256[] private returnPC;
    uint256[] private returnFrame;

    // Lists: listId => elements (IDs 0 to 2^60 - 1)
    mapping(uint256 => uint256[]) private lists;
    uint256 private nextListId;

    // Dicts: dictId => key => value (IDs 2^60 to 2^61 - 1)
    mapping(uint256 => mapping(uint256 => uint256)) private dictValues;
    mapping(uint256 => mapping(uint256 => bool)) private dictHasKey;
    mapping(uint256 => uint256[]) private dictKeyList;
    uint256 private nextDictId;
    uint256 constant DICT_ID_OFFSET = 2**60;

    // Sets: setId => value => bool (IDs 2^61 to 2^62 - 1)
    mapping(uint256 => mapping(uint256 => bool)) private setMembers;
    mapping(uint256 => uint256) private setSize;
    uint256 private nextSetId;
    uint256 constant SET_ID_OFFSET = 2**61;

    // String table
    bytes private stringTable;
    uint256 constant STATIC_STR_OFFSET = 2**62;

    // Bytecode
    bytes private code;
    uint256 private codeStart;
    uint256 private pc;

    // GC: reference counting
    mapping(uint256 => uint256) private gcRefcounts;
    mapping(uint256 => bool) private gcLive;
    uint256 private gcTotalAllocated;
    uint256 private gcTotalFreed;
    // Track objects per frame for cleanup
    mapping(uint256 => uint256[]) private frameObjects; // frameIndex => objectIds

    // Exception handling
    uint256[] private tryStack;       // stack of handler PCs
    bool private exceptionActive;
    uint256 private exceptionValue;

    // Events
    event Print(uint256[] values);
    event PrintString(string value);
    event Result(uint256 value);
    event Error(string message);
    event VMError(string message, uint256 pc);
    event Trace(uint256 pc, uint8 op, uint256 stackTop);

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

    // GC opcodes
    uint8 constant OP_GC_REF = 0xB0;    // Increment refcount of TOS
    uint8 constant OP_GC_UNREF = 0xB1;  // Decrement refcount of TOS, free if 0
    uint8 constant OP_GC_CLEANUP = 0xB2; // Cleanup all objects in current frame
    uint8 constant OP_GC_STATS = 0xB3;  // Emit GC stats as event

    // Exception handling opcodes
    uint8 constant OP_TRY_BEGIN = 0xC0;  // Push try context (handler PC)
    uint8 constant OP_TRY_END = 0xC1;    // Pop try context
    uint8 constant OP_RAISE = 0xC2;      // Raise exception
    uint8 constant OP_CATCH = 0xC3;      // Catch exception (store in variable)

    uint8 constant OP_HALT = 0xFF;

    // ==================== Entry Point ====================

    function execute(bytes memory bytecode) public {
        _parseHeader(bytecode);

        // Init global frame
        frameCount = 1;
        frameVarCounts.push(0);

        uint256 maxSteps = 100000; // gas limit safeguard
        uint256 steps = 0;

        while (pc < code.length && steps < maxSteps) {
            steps++;
            uint8 op = uint8(code[pc]);
            pc++;

            if (op == OP_PUSH) _execPush();
            else if (op == OP_POP) _execPop();
            else if (op == OP_DUP) _execDup();
            else if (op == OP_SWAP) _execSwap();
            else if (op == OP_ADD) _execAdd();
            else if (op == OP_SUB) _execSub();
            else if (op == OP_MUL) _execMul();
            else if (op == OP_DIV) _execDiv();
            else if (op == OP_MOD) _execMod();
            else if (op == OP_POW) _execPow();
            else if (op == OP_NEG) _execNeg();
            else if (op == OP_EQ) _execEq();
            else if (op == OP_NEQ) _execNeq();
            else if (op == OP_LT) _execLt();
            else if (op == OP_GT) _execGt();
            else if (op == OP_LTE) _execLte();
            else if (op == OP_GTE) _execGte();
            else if (op == OP_AND) _execAnd();
            else if (op == OP_OR) _execOr();
            else if (op == OP_NOT) _execNot();
            else if (op == OP_LOAD_VAR) _execLoadVar();
            else if (op == OP_STORE_VAR) _execStoreVar();
            else if (op == OP_JUMP) _execJump();
            else if (op == OP_JUMP_IF_FALSE) _execJumpIfFalse();
            else if (op == OP_JUMP_IF_TRUE) _execJumpIfTrue();
            else if (op == OP_JUMP_BACK) _execJumpBack();
            else if (op == OP_CALL) _execCall();
            else if (op == OP_RETURN) _execReturn();
            else if (op == OP_SETUP_FRAME) _execSetupFrame();
            else if (op == OP_TEAR_FRAME) _execTearFrame();
            else if (op == OP_MAKE_LIST) _execMakeList();
            else if (op == OP_LIST_GET) _execListGet();
            else if (op == OP_LIST_SET) _execListSet();
            else if (op == OP_LIST_LEN) _execListLen();
            else if (op == OP_PRINT) _execPrint();
            else if (op == OP_EMIT) _execEmit();
            else if (op == OP_PRINT_STR) _execPrintStr();
            else if (op == OP_MAKE_DICT) _execMakeDict();
            else if (op == OP_DICT_GET) _execDictGet();
            else if (op == OP_DICT_SET) _execDictSet();
            else if (op == OP_DICT_HAS) _execDictHas();
            else if (op == OP_DICT_KEYS) _execDictKeys();
            else if (op == OP_DICT_LEN) _execDictLen();
            else if (op == OP_MAKE_SET) _execMakeSet();
            else if (op == OP_SET_ADD) _execSetAdd();
            else if (op == OP_SET_HAS) _execSetHas();
            else if (op == OP_SET_LEN) _execSetLen();
            else if (op == OP_STR_LEN) _execStrLen();
            else if (op == OP_STR_CONCAT) _execStrConcat();
            else if (op == OP_STR_UPPER) _execStrUpper();
            else if (op == OP_STR_LOWER) _execStrLower();
            else if (op == OP_STR_SLICE) _execStrSlice();
            else if (op == OP_STR_EQ) _execStrEq();
            else if (op == OP_STR_TO_INT) _execStrToInt();
            else if (op == OP_INT_TO_STR) _execIntToStr();
            else if (op == OP_STR_CONTAINS) _execStrContains();
            else if (op == OP_STR_SPLIT) _execStrSplit();
            else if (op == OP_STR_CHAR_AT) _execStrCharAt();
            else if (op == OP_GC_REF) _execGcRef();
            else if (op == OP_GC_UNREF) _execGcUnref();
            else if (op == OP_GC_CLEANUP) _execGcCleanup();
            else if (op == OP_GC_STATS) _execGcStats();
            else if (op == OP_TRY_BEGIN) _execTryBegin();
            else if (op == OP_TRY_END) _execTryEnd();
            else if (op == OP_RAISE) _execRaise();
            else if (op == OP_CATCH) _execCatch();
            else if (op == OP_HALT) break;
            else {
                emit VMError("Unknown opcode", pc - 1);
                break;
            }
        }
    }

    // ==================== Header Parsing ====================

    function _parseHeader(bytes memory bc) internal {
        require(bc.length >= 7, "Invalid bytecode: too short");
        require(uint8(bc[0]) == 0x50 && uint8(bc[1]) == 0x59, "Invalid magic bytes");
        require(uint8(bc[2]) == 0x01, "Unsupported version");

        uint256 codeLen = uint256(uint8(bc[3])) << 24 |
                          uint256(uint8(bc[4])) << 16 |
                          uint256(uint8(bc[5])) << 8 |
                          uint256(uint8(bc[6]));

        codeStart = 7;
        // Extract code section
        code = new bytes(codeLen);
        for (uint256 i = 0; i < codeLen; i++) {
            code[i] = bc[codeStart + i];
        }

        // Parse string table
        uint256 stOffset = codeStart + codeLen;
        if (stOffset + 4 <= bc.length) {
            uint256 stLen = uint256(uint8(bc[stOffset])) << 24 |
                            uint256(uint8(bc[stOffset + 1])) << 16 |
                            uint256(uint8(bc[stOffset + 2])) << 8 |
                            uint256(uint8(bc[stOffset + 3]));
            stringTable = new bytes(stLen);
            for (uint256 i = 0; i < stLen; i++) {
                stringTable[i] = bc[stOffset + 4 + i];
            }
        }

        pc = 0;
    }

    // ==================== Stack Operations ====================

    function _execPush() internal {
        uint256 value = _readUint256();
        stack.push(value);
    }

    function _execPop() internal {
        require(stack.length > 0, "Stack underflow: POP");
        stack.pop();
    }

    function _execDup() internal {
        require(stack.length > 0, "Stack underflow: DUP");
        stack.push(stack[stack.length - 1]);
    }

    function _execSwap() internal {
        require(stack.length >= 2, "Stack underflow: SWAP");
        uint256 a = stack[stack.length - 1];
        uint256 b = stack[stack.length - 2];
        stack[stack.length - 1] = b;
        stack[stack.length - 2] = a;
    }

    // ==================== Arithmetic ====================

    function _isStringId(uint256 val) internal view returns (bool) {
        if (val >= STATIC_STR_OFFSET && val < STATIC_STR_OFFSET + stringTable.length) return true;
        if (val >= RUNTIME_STR_OFFSET && val < RUNTIME_STR_OFFSET + nextRuntimeStringId) return true;
        return false;
    }

    function _execAdd() internal {
        uint256 a = _pop();
        uint256 b = _pop();

        // Check if either operand is a string (static or runtime)
        if (_isStringId(a) || _isStringId(b)) {
            // String concatenation: b (left) + a (right)
            string memory strA = _getAnyString(a);
            string memory strB = _getAnyString(b);
            bytes memory result = new bytes(bytes(strB).length + bytes(strA).length);
            for (uint256 i = 0; i < bytes(strB).length; i++) result[i] = bytes(strB)[i];
            for (uint256 i = 0; i < bytes(strA).length; i++) result[bytes(strB).length + i] = bytes(strA)[i];
            uint256 newIdx = _addRuntimeString(result);
            stack.push(newIdx);
        } else {
            unchecked { stack.push(b + a); }
        }
    }

    function _execSub() internal {
        uint256 a = _pop();
        uint256 b = _pop();
        unchecked { stack.push(b - a); }
    }

    function _execMul() internal {
        uint256 a = _pop();
        uint256 b = _pop();
        unchecked {
            uint256 result = b * a;
            emit Trace(pc - 1, 0x12, result);
            stack.push(result);
        }
    }

    function _execDiv() internal {
        uint256 a = _pop();
        uint256 b = _pop();
        if (a == 0) {
            emit VMError("Division by zero", pc - 1);
            pc = code.length; // halt
            return;
        }
        stack.push(b / a);
    }

    function _execMod() internal {
        uint256 a = _pop();
        uint256 b = _pop();
        if (a == 0) {
            emit VMError("Modulo by zero", pc - 1);
            pc = code.length; // halt
            return;
        }
        stack.push(b % a);
    }

    function _execPow() internal {
        uint256 a = _pop();
        uint256 b = _pop();
        stack.push(_pow(b, a));
    }

    function _execNeg() internal {
        uint256 a = _pop();
        unchecked { stack.push(type(uint256).max - a + 1); } // two's complement negation
    }

    // ==================== Comparison ====================

    function _execEq() internal {
        uint256 a = _pop();
        uint256 b = _pop();
        stack.push(b == a ? 1 : 0);
    }

    function _execNeq() internal {
        uint256 a = _pop();
        uint256 b = _pop();
        stack.push(b != a ? 1 : 0);
    }

    function _execLt() internal {
        uint256 a = _pop();
        uint256 b = _pop();
        stack.push(int256(b) < int256(a) ? 1 : 0);
    }

    function _execGt() internal {
        uint256 a = _pop();
        uint256 b = _pop();
        stack.push(int256(b) > int256(a) ? 1 : 0);
    }

    function _execLte() internal {
        uint256 a = _pop();
        uint256 b = _pop();
        stack.push(int256(b) <= int256(a) ? 1 : 0);
    }

    function _execGte() internal {
        uint256 a = _pop();
        uint256 b = _pop();
        stack.push(int256(b) >= int256(a) ? 1 : 0);
    }

    // ==================== Boolean ====================

    function _execAnd() internal {
        uint256 a = _pop();
        uint256 b = _pop();
        stack.push((b != 0 && a != 0) ? 1 : 0);
    }

    function _execOr() internal {
        uint256 a = _pop();
        uint256 b = _pop();
        stack.push((b != 0 || a != 0) ? 1 : 0);
    }

    function _execNot() internal {
        uint256 a = _pop();
        stack.push(a == 0 ? 1 : 0);
    }

    // ==================== Variables ====================

    function _execLoadVar() internal {
        uint8 frame = uint8(code[pc]); pc++;
        uint8 varIdx = uint8(code[pc]); pc++;
        uint256 f = frame == 0 ? 0 : frameCount - 1;
        stack.push(frameLocals[f][varIdx]);
    }

    function _execStoreVar() internal {
        uint8 frame = uint8(code[pc]); pc++;
        uint8 varIdx = uint8(code[pc]); pc++;
        uint256 value = _pop();
        uint256 f = frame == 0 ? 0 : frameCount - 1;
        frameLocals[f][varIdx] = value;
        if (varIdx >= frameVarCounts[f]) {
            frameVarCounts[f] = varIdx + 1;
        }
    }

    // ==================== Control Flow ====================

    function _execJump() internal {
        uint256 offset = _readUint32();
        pc = pc + offset;
    }

    function _execJumpIfFalse() internal {
        uint256 offset = _readUint32();
        uint256 cond = _pop();
        if (cond == 0) pc = pc + offset;
    }

    function _execJumpIfTrue() internal {
        uint256 offset = _readUint32();
        uint256 cond = _pop();
        if (cond != 0) pc = pc + offset;
    }

    function _execJumpBack() internal {
        uint256 target = _readUint32();
        pc = target;
    }

    // ==================== Functions ====================

    function _execCall() internal {
        uint256 callPC = pc - 1; // PC of the CALL opcode
        uint16 numArgs = _readUint16();
        uint256 funcOffset = _readUint32();

        // Save return state
        returnPC.push(pc);
        returnFrame.push(frameCount - 1);

        // Create new frame
        frameCount++;
        frameVarCounts.push(0);

        // Args remain on stack — function body's STORE_VAR handles them

        emit Trace(callPC, 0x60, funcOffset);
        pc = funcOffset;
    }

    function _execReturn() internal {
        uint256 retPC = pc - 1; // PC of the RETURN opcode
        uint256 retVal = _pop();

        // Tear frame
        frameCount--;
        frameVarCounts.pop();

        // Restore PC
        pc = returnPC[returnPC.length - 1];
        returnPC.pop();
        returnFrame.pop();

        emit Trace(retPC, 0x61, retVal);

        // Push return value
        stack.push(retVal);
    }

    function _execSetupFrame() internal {
        uint16 numLocals = _readUint16();
        // Frame is already created by CALL — just ensure var count
        // This is a no-op in the current implementation since CALL creates the frame
        (numLocals); // silence unused warning
    }

    function _execTearFrame() internal {
        // Frame is torn by RETURN — this is a no-op
    }

    // ==================== Lists ====================

    function _execMakeList() internal {
        uint16 numElements = _readUint16();
        uint256 listId = nextListId++;
        for (uint256 i = 0; i < numElements; i++) {
            lists[listId].push(0); // pre-allocate
        }
        for (uint256 i = numElements; i > 0; i--) {
            lists[listId][i - 1] = _pop();
        }
        _gcRegister(listId);
        stack.push(listId);
    }

    function _execListGet() internal {
        uint256 index = _pop();
        uint256 listId = _pop();
        if (index >= lists[listId].length) {
            emit VMError("List index out of bounds", pc - 1);
            pc = code.length; // halt
            stack.push(0);
            return;
        }
        stack.push(lists[listId][index]);
    }

    function _execListSet() internal {
        uint256 value = _pop();
        uint256 index = _pop();
        uint256 listId = _pop();
        if (index >= lists[listId].length) {
            emit VMError("List index out of bounds", pc - 1);
            pc = code.length; // halt
            return;
        }
        lists[listId][index] = value;
    }

    function _execListLen() internal {
        uint256 id = _pop();

        // Check if it's a static string (from string table)
        if (id >= STATIC_STR_OFFSET && id < RUNTIME_STR_OFFSET) {
            string memory s = _getStringFromTable(id);
            stack.push(bytes(s).length);
            return;
        }

        // Check if it's a runtime string
        if (id >= RUNTIME_STR_OFFSET) {
            string memory s = _getAnyString(id);
            stack.push(bytes(s).length);
            return;
        }

        // Check if it's a dict (ID range: DICT_ID_OFFSET to DICT_ID_OFFSET + nextDictId - 1)
        if (id >= DICT_ID_OFFSET && id < DICT_ID_OFFSET + nextDictId) {
            stack.push(dictKeyList[id].length);
            return;
        }

        // Check if it's a set (ID range: SET_ID_OFFSET to SET_ID_OFFSET + nextSetId - 1)
        if (id >= SET_ID_OFFSET && id < SET_ID_OFFSET + nextSetId) {
            stack.push(setSize[id]);
            return;
        }

        // Otherwise, treat as list
        stack.push(lists[id].length);
    }

    // ==================== I/O ====================

    function _execPrint() internal {
        uint8 numArgs = uint8(code[pc]); pc++;
        uint256[] memory values = new uint256[](numArgs);
        for (uint256 i = numArgs; i > 0; i--) {
            values[i - 1] = _pop();
        }
        emit Trace(pc - 2, 0x80, values[0]);

        // Check if single value is a string (static or runtime)
        if (numArgs == 1 && _isStringId(values[0])) {
            string memory s = _getAnyString(values[0]);
            emit PrintString(s);
        } else {
            emit Print(values);
        }
    }

    function _execEmit() internal {
        uint256 value = _pop();
        emit Result(value);
    }

    function _execPrintStr() internal {
        uint256 tableIdx = _pop();
        string memory s = _getAnyString(tableIdx);
        emit PrintString(s);
    }

    function _getStringFromTable(uint256 index) internal view returns (string memory) {
        // Subtract offset to get actual string table index
        uint256 actualIndex = index - STATIC_STR_OFFSET;
        if (actualIndex >= stringTable.length) return "";
        uint256 len = (uint256(uint8(stringTable[actualIndex])) << 8) | uint256(uint8(stringTable[actualIndex + 1]));
        bytes memory result = new bytes(len);
        for (uint256 i = 0; i < len; i++) {
            result[i] = stringTable[actualIndex + 2 + i];
        }
        return string(result);
    }

    // ==================== Dicts ====================

    function _execMakeDict() internal {
        uint16 numPairs = _readUint16();
        uint256 dictId = DICT_ID_OFFSET + nextDictId++;
        for (uint256 i = 0; i < numPairs; i++) {
            uint256 key = _pop();
            uint256 value = _pop();
            if (!dictHasKey[dictId][key]) {
                dictKeyList[dictId].push(key);
                dictHasKey[dictId][key] = true;
            }
            dictValues[dictId][key] = value;
        }
        _gcRegister(dictId);
        stack.push(dictId);
    }

    function _execDictGet() internal {
        uint256 key = _pop();
        uint256 dictId = _pop();
        if (dictHasKey[dictId][key]) {
            stack.push(dictValues[dictId][key]);
        } else {
            stack.push(type(uint256).max); // NONE
        }
    }

    function _execDictSet() internal {
        uint256 value = _pop();
        uint256 key = _pop();
        uint256 dictId = _pop();
        if (!dictHasKey[dictId][key]) {
            dictKeyList[dictId].push(key);
            dictHasKey[dictId][key] = true;
        }
        dictValues[dictId][key] = value;
    }

    function _execDictHas() internal {
        uint256 key = _pop();
        uint256 dictId = _pop();
        stack.push(dictHasKey[dictId][key] ? 1 : 0);
    }

    function _execDictKeys() internal {
        uint256 dictId = _pop();
        uint256 listId = nextListId++;
        uint256 len = dictKeyList[dictId].length;
        for (uint256 i = 0; i < len; i++) {
            lists[listId].push(dictKeyList[dictId][i]);
        }
        stack.push(listId);
    }

    function _execDictLen() internal {
        uint256 dictId = _pop();
        stack.push(dictKeyList[dictId].length);
    }

    // ==================== Sets ====================

    function _execMakeSet() internal {
        uint16 numElements = _readUint16();
        uint256 setId = SET_ID_OFFSET + nextSetId++;
        for (uint256 i = 0; i < numElements; i++) {
            uint256 value = _pop();
            if (!setMembers[setId][value]) {
                setMembers[setId][value] = true;
                setSize[setId]++;
            }
        }
        _gcRegister(setId);
        stack.push(setId);
    }

    function _execSetAdd() internal {
        uint256 value = _pop();
        uint256 setId = _pop();
        if (!setMembers[setId][value]) {
            setMembers[setId][value] = true;
            setSize[setId]++;
        }
    }

    function _execSetHas() internal {
        uint256 value = _pop();
        uint256 setId = _pop();
        stack.push(setMembers[setId][value] ? 1 : 0);
    }

    function _execSetLen() internal {
        uint256 setId = _pop();
        stack.push(setSize[setId]);
    }

    // ==================== String Operations ====================

    // Runtime string storage (for dynamically created strings)
    mapping(uint256 => bytes) private runtimeStrings;
    uint256 private nextRuntimeStringId;
    // Offset for runtime string IDs to avoid collision with static string table
    uint256 constant RUNTIME_STR_OFFSET = 2**240;

    function _addRuntimeString(bytes memory s) internal returns (uint256) {
        uint256 id = RUNTIME_STR_OFFSET + nextRuntimeStringId;
        runtimeStrings[id] = s;
        nextRuntimeStringId++;
        return id;
    }

    function _getAnyString(uint256 idx) internal view returns (string memory) {
        if (idx >= RUNTIME_STR_OFFSET) {
            return string(runtimeStrings[idx]);
        }
        if (idx >= STATIC_STR_OFFSET) {
            return _getStringFromTable(idx);
        }
        // Fallback: treat as raw string table index (for backwards compatibility)
        return _getStringFromTable(idx + STATIC_STR_OFFSET);
    }

    function _execStrLen() internal {
        uint256 strIdx = _pop();
        string memory s = _getAnyString(strIdx);
        stack.push(bytes(s).length);
    }

    function _execStrConcat() internal {
        uint256 bIdx = _pop();
        uint256 aIdx = _pop();
        string memory a = _getAnyString(aIdx);
        string memory b = _getAnyString(bIdx);
        bytes memory result = new bytes(bytes(a).length + bytes(b).length);
        for (uint256 i = 0; i < bytes(a).length; i++) result[i] = bytes(a)[i];
        for (uint256 i = 0; i < bytes(b).length; i++) result[bytes(a).length + i] = bytes(b)[i];
        uint256 newIdx = _addRuntimeString(result);
        stack.push(newIdx);
    }

    function _execStrUpper() internal {
        uint256 strIdx = _pop();
        string memory s = _getAnyString(strIdx);
        bytes memory result = _upper(bytes(s));
        uint256 newIdx = _addRuntimeString(result);
        stack.push(newIdx);
    }

    function _execStrLower() internal {
        uint256 strIdx = _pop();
        string memory s = _getAnyString(strIdx);
        bytes memory result = _lower(bytes(s));
        uint256 newIdx = _addRuntimeString(result);
        stack.push(newIdx);
    }

    function _execStrSlice() internal {
        uint256 end = _pop();
        uint256 start = _pop();
        uint256 strIdx = _pop();
        string memory s = _getAnyString(strIdx);
        bytes memory sb = bytes(s);
        if (end == 0 || end > sb.length) end = sb.length;
        if (start >= sb.length) {
            uint256 newIdx = _addRuntimeString(new bytes(0));
            stack.push(newIdx);
            return;
        }
        if (start >= end) {
            uint256 newIdx = _addRuntimeString(new bytes(0));
            stack.push(newIdx);
            return;
        }
        bytes memory result = new bytes(end - start);
        for (uint256 i = start; i < end; i++) {
            result[i - start] = sb[i];
        }
        uint256 newIdx = _addRuntimeString(result);
        stack.push(newIdx);
    }

    function _execStrEq() internal {
        uint256 bIdx = _pop();
        uint256 aIdx = _pop();
        string memory a = _getAnyString(aIdx);
        string memory b = _getAnyString(bIdx);
        stack.push(keccak256(bytes(a)) == keccak256(bytes(b)) ? 1 : 0);
    }

    function _execStrToInt() internal {
        uint256 strIdx = _pop();
        string memory s = _getAnyString(strIdx);
        (int256 val, bool ok) = _bytesToInt(bytes(s));
        if (ok) {
            stack.push(uint256(val));
        } else {
            stack.push(0);
        }
    }

    function _execIntToStr() internal {
        uint256 val = _pop();
        bytes memory result = _intToBytes(int256(val));
        uint256 newIdx = _addRuntimeString(result);
        stack.push(newIdx);
    }

    function _execStrContains() internal {
        uint256 needleIdx = _pop();
        uint256 haystackIdx = _pop();
        string memory haystack = _getAnyString(haystackIdx);
        string memory needle = _getAnyString(needleIdx);
        bool found = _strContains(bytes(haystack), bytes(needle));
        stack.push(found ? 1 : 0);
    }

    function _execStrSplit() internal {
        uint256 delimIdx = _pop();
        uint256 strIdx = _pop();
        string memory s = _getAnyString(strIdx);
        string memory delim = _getAnyString(delimIdx);
        bytes[] memory parts = _strSplit(bytes(s), bytes(delim));
        uint256 listId = nextListId++;
        for (uint256 i = 0; i < parts.length; i++) {
            uint256 partStrIdx = _addRuntimeString(parts[i]);
            lists[listId].push(partStrIdx);
        }
        stack.push(listId);
    }

    function _execStrCharAt() internal {
        uint256 index = _pop();
        uint256 strIdx = _pop();
        string memory s = _getAnyString(strIdx);
        bytes memory sb = bytes(s);
        if (index >= sb.length) {
            stack.push(type(uint256).max); // NONE
            return;
        }
        bytes memory char = new bytes(1);
        char[0] = sb[index];
        uint256 newIdx = _addRuntimeString(char);
        stack.push(newIdx);
    }

    // ==================== String Helpers ====================

    function _upper(bytes memory b) internal pure returns (bytes memory) {
        bytes memory result = new bytes(b.length);
        for (uint256 i = 0; i < b.length; i++) {
            if (b[i] >= 0x61 && b[i] <= 0x7A) {
                result[i] = bytes1(uint8(b[i]) - 32);
            } else {
                result[i] = b[i];
            }
        }
        return result;
    }

    function _lower(bytes memory b) internal pure returns (bytes memory) {
        bytes memory result = new bytes(b.length);
        for (uint256 i = 0; i < b.length; i++) {
            if (b[i] >= 0x41 && b[i] <= 0x5A) {
                result[i] = bytes1(uint8(b[i]) + 32);
            } else {
                result[i] = b[i];
            }
        }
        return result;
    }

    function _strContains(bytes memory haystack, bytes memory needle) internal pure returns (bool) {
        if (needle.length == 0) return true;
        if (needle.length > haystack.length) return false;
        for (uint256 i = 0; i <= haystack.length - needle.length; i++) {
            bool found = true;
            for (uint256 j = 0; j < needle.length; j++) {
                if (haystack[i + j] != needle[j]) { found = false; break; }
            }
            if (found) return true;
        }
        return false;
    }

    function _strSplit(bytes memory b, bytes memory delim) internal pure returns (bytes[] memory) {
        if (delim.length == 0) {
            bytes[] memory r = new bytes[](1);
            r[0] = b;
            return r;
        }
        uint256 count = 1;
        for (uint256 i = 0; i <= b.length - delim.length; i++) {
            bool isMatch = true;
            for (uint256 j = 0; j < delim.length; j++) {
                if (b[i + j] != delim[j]) { isMatch = false; break; }
            }
            if (isMatch) { count++; i += delim.length - 1; }
        }
        bytes[] memory result = new bytes[](count);
        uint256 partIdx = 0;
        uint256 start = 0;
        for (uint256 i = 0; i <= b.length - delim.length; i++) {
            bool isMatch = true;
            for (uint256 j = 0; j < delim.length; j++) {
                if (b[i + j] != delim[j]) { isMatch = false; break; }
            }
            if (isMatch) {
                bytes memory part = new bytes(i - start);
                for (uint256 k = start; k < i; k++) part[k - start] = b[k];
                result[partIdx] = part;
                partIdx++;
                start = i + delim.length;
                i += delim.length - 1;
            }
        }
        bytes memory last = new bytes(b.length - start);
        for (uint256 k = start; k < b.length; k++) last[k - start] = b[k];
        result[partIdx] = last;
        return result;
    }

    function _intToBytes(int256 value) internal pure returns (bytes memory) {
        if (value == 0) return "0";
        bool neg = value < 0;
        uint256 absVal = neg ? uint256(-value) : uint256(value);
        // Count digits
        uint256 temp = absVal;
        uint256 digits = 0;
        while (temp != 0) { digits++; temp /= 10; }
        bytes memory result = new bytes(digits + (neg ? 1 : 0));
        uint256 pos = digits;
        while (absVal != 0) {
            pos--;
            result[pos + (neg ? 1 : 0)] = bytes1(uint8(48 + absVal % 10));
            absVal /= 10;
        }
        if (neg) result[0] = 0x2D; // '-'
        return result;
    }

    function _bytesToInt(bytes memory b) internal pure returns (int256, bool) {
        if (b.length == 0) return (0, false);
        bool neg = false;
        uint256 start = 0;
        if (b[0] == 0x2D) { neg = true; start = 1; }
        uint256 result = 0;
        bool valid = false;
        for (uint256 i = start; i < b.length; i++) {
            if (b[i] >= 0x30 && b[i] <= 0x39) {
                result = result * 10 + (uint8(b[i]) - 48);
                valid = true;
            } else {
                return (0, false);
            }
        }
        if (!valid) return (0, false);
        return (neg ? -int256(result) : int256(result), true);
    }

    // ==================== Helpers ====================

    function _pop() internal returns (uint256) {
        if (stack.length == 0) {
            emit VMError("Stack underflow", pc - 1);
            pc = code.length; // halt
            return 0;
        }
        uint256 value = stack[stack.length - 1];
        stack.pop();
        return value;
    }

    function _readUint256() internal returns (uint256) {
        uint256 value = 0;
        for (uint256 i = 0; i < 32; i++) {
            value = (value << 8) | uint256(uint8(code[pc]));
            pc++;
        }
        return value;
    }

    function _readUint32() internal returns (uint256) {
        uint256 value = uint256(uint8(code[pc])) << 24 |
                        uint256(uint8(code[pc + 1])) << 16 |
                        uint256(uint8(code[pc + 2])) << 8 |
                        uint256(uint8(code[pc + 3]));
        pc += 4;
        return value;
    }

    function _readUint16() internal returns (uint16) {
        uint16 value = uint16(uint8(code[pc])) << 8 | uint16(uint8(code[pc + 1]));
        pc += 2;
        return value;
    }

    function _pow(uint256 base, uint256 exp) internal pure returns (uint256) {
        uint256 result = 1;
        while (exp > 0) {
            if (exp & 1 == 1) result *= base;
            base *= base;
            exp >>= 1;
        }
        return result;
    }

    // ==================== Public Getters ====================

    function getStackLength() public view returns (uint256) { return stack.length; }

    function getStackTop() public view returns (uint256) {
        require(stack.length > 0, "Empty stack");
        return stack[stack.length - 1];
    }

    function getStack(uint256 index) public view returns (uint256) {
        return stack[index];
    }

    function getStringFromTable(uint256 index) public view returns (string memory) {
        uint256 actualIndex = index - STATIC_STR_OFFSET;
        if (actualIndex >= stringTable.length) return "";
        uint256 len = (uint256(uint8(stringTable[actualIndex])) << 8) | uint256(uint8(stringTable[actualIndex + 1]));
        bytes memory result = new bytes(len);
        for (uint256 i = 0; i < len; i++) {
            result[i] = stringTable[actualIndex + 2 + i];
        }
        return string(result);
    }

    function getPC() public view returns (uint256) { return pc; }

    function getStringTableLength() public view returns (uint256) { return stringTable.length; }

    // ==================== GC Functions ====================

    event GCStats(uint256 allocated, uint256 freed, uint256 live);

    function _gcRegister(uint256 id) internal {
        gcRefcounts[id] = 1;
        gcLive[id] = true;
        gcTotalAllocated++;
        frameObjects[frameCount - 1].push(id);
    }

    function _gcIncRef(uint256 id) internal {
        if (id == 0 || !gcLive[id]) return;
        gcRefcounts[id]++;
    }

    function _gcDecRef(uint256 id) internal {
        if (id == 0 || !gcLive[id]) return;
        gcRefcounts[id]--;
        if (gcRefcounts[id] == 0) {
            gcLive[id] = false;
            gcTotalFreed++;
        }
    }

    function _execGcRef() internal {
        uint256 id = _pop();
        _gcIncRef(id);
        stack.push(id); // push back (non-destructive)
    }

    function _execGcUnref() internal {
        uint256 id = _pop();
        _gcDecRef(id);
    }

    function _execGcCleanup() internal {
        // Cleanup all objects in the current frame
        uint256 fi = frameCount - 1;
        uint256 count = frameObjects[fi].length;
        for (uint256 i = 0; i < count; i++) {
            _gcDecRef(frameObjects[fi][i]);
        }
        // Clear the frame's object list
        delete frameObjects[fi];
    }

    function _execGcStats() internal {
        emit GCStats(gcTotalAllocated, gcTotalFreed, gcTotalAllocated - gcTotalFreed);
    }

    // GC public getters
    function getGCAllocated() public view returns (uint256) { return gcTotalAllocated; }
    function getGCFreed() public view returns (uint256) { return gcTotalFreed; }
    function getGCLive() public view returns (uint256) { return gcTotalAllocated - gcTotalFreed; }
    function getGCRefcount(uint256 id) public view returns (uint256) { return gcRefcounts[id]; }
    function getGCLiveStatus(uint256 id) public view returns (bool) { return gcLive[id]; }

    // ==================== Exception Handling ====================

    function _execTryBegin() internal {
        // Read 4-byte handler PC offset
        uint256 handlerPC = _readUint32();
        tryStack.push(handlerPC);
    }

    function _execTryEnd() internal {
        if (tryStack.length > 0) {
            tryStack.pop();
        }
    }

    function _execRaise() internal {
        uint256 val = _pop();
        exceptionValue = val;
        exceptionActive = true;

        if (tryStack.length > 0) {
            uint256 handlerPC = tryStack[tryStack.length - 1];
            tryStack.pop();
            pc = handlerPC;
        } else {
            emit VMError("Unhandled exception", pc - 1);
            pc = code.length; // halt
        }
    }

    function _execCatch() internal {
        // Push the exception value onto the stack and clear exception state
        stack.push(exceptionValue);
        exceptionActive = false;
        exceptionValue = 0;
    }

    // Exception public getters
    function isExceptionActive() public view returns (bool) { return exceptionActive; }
    function getExceptionValue() public view returns (uint256) { return exceptionValue; }
    function getTryStackDepth() public view returns (uint256) { return tryStack.length; }
}
