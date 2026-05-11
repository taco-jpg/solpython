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

    // Lists: listId => elements
    mapping(uint256 => uint256[]) private lists;
    uint256 private nextListId;

    // String table
    bytes private stringTable;

    // Bytecode
    bytes private code;
    uint256 private codeStart;
    uint256 private pc;

    // Events
    event Print(uint256[] values);
    event Result(uint256 value);
    event Error(string message);

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
            else if (op == OP_HALT) break;
            else {
                emit Error("Unknown opcode");
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

    function _execAdd() internal {
        uint256 a = _pop();
        uint256 b = _pop();
        stack.push(b + a);
    }

    function _execSub() internal {
        uint256 a = _pop();
        uint256 b = _pop();
        stack.push(b - a);
    }

    function _execMul() internal {
        uint256 a = _pop();
        uint256 b = _pop();
        stack.push(b * a);
    }

    function _execDiv() internal {
        uint256 a = _pop();
        uint256 b = _pop();
        require(a != 0, "Division by zero");
        stack.push(b / a);
    }

    function _execMod() internal {
        uint256 a = _pop();
        uint256 b = _pop();
        require(a != 0, "Modulo by zero");
        stack.push(b % a);
    }

    function _execPow() internal {
        uint256 a = _pop();
        uint256 b = _pop();
        stack.push(_pow(b, a));
    }

    function _execNeg() internal {
        uint256 a = _pop();
        stack.push(type(uint256).max - a + 1); // two's complement negation
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
        stack.push(b < a ? 1 : 0);
    }

    function _execGt() internal {
        uint256 a = _pop();
        uint256 b = _pop();
        stack.push(b > a ? 1 : 0);
    }

    function _execLte() internal {
        uint256 a = _pop();
        uint256 b = _pop();
        stack.push(b <= a ? 1 : 0);
    }

    function _execGte() internal {
        uint256 a = _pop();
        uint256 b = _pop();
        stack.push(b >= a ? 1 : 0);
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
        uint16 numArgs = _readUint16();
        uint256 funcOffset = _readUint32();

        // Save return state
        returnPC.push(pc);
        returnFrame.push(frameCount - 1);

        // Create new frame
        frameCount++;
        frameVarCounts.push(0);

        // Args remain on stack — function body's STORE_VAR handles them

        pc = funcOffset;
    }

    function _execReturn() internal {
        uint256 retVal = _pop();

        // Tear frame
        frameCount--;
        frameVarCounts.pop();

        // Restore PC
        pc = returnPC[returnPC.length - 1];
        returnPC.pop();
        returnFrame.pop();

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
        stack.push(listId);
    }

    function _execListGet() internal {
        uint256 index = _pop();
        uint256 listId = _pop();
        require(index < lists[listId].length, "List index out of bounds");
        stack.push(lists[listId][index]);
    }

    function _execListSet() internal {
        uint256 value = _pop();
        uint256 index = _pop();
        uint256 listId = _pop();
        require(index < lists[listId].length, "List index out of bounds");
        lists[listId][index] = value;
    }

    function _execListLen() internal {
        uint256 listId = _pop();
        stack.push(lists[listId].length);
    }

    // ==================== I/O ====================

    function _execPrint() internal {
        uint8 numArgs = uint8(code[pc]); pc++;
        uint256[] memory values = new uint256[](numArgs);
        for (uint256 i = numArgs; i > 0; i--) {
            values[i - 1] = _pop();
        }
        emit Print(values);
    }

    function _execEmit() internal {
        uint256 value = _pop();
        emit Result(value);
    }

    // ==================== Helpers ====================

    function _pop() internal returns (uint256) {
        require(stack.length > 0, "Stack underflow");
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
        if (index >= stringTable.length) return "";
        uint256 len = (uint256(uint8(stringTable[index])) << 8) | uint256(uint8(stringTable[index + 1]));
        bytes memory result = new bytes(len);
        for (uint256 i = 0; i < len; i++) {
            result[i] = stringTable[index + 2 + i];
        }
        return string(result);
    }

    function getPC() public view returns (uint256) { return pc; }
}
