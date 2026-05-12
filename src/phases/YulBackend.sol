// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {NodeType, BinaryOpType, UnaryOpType, CompOpType, AugAssignOp} from "../types/ASTNode.sol";
import {Parser} from "./Parser.sol";

/// @title YulBackend — AST to Yul IR transpiler
/// @notice Walks the AST and emits Yul intermediate representation.
///         Yul is Solidity's intermediate language that compiles to EVM bytecode.
contract YulBackend {
    bytes private _out;
    uint256 private _indent;
    uint256 private _tempCounter;

    // Variable tracking
    mapping(uint256 => mapping(bytes32 => bool)) private _declaredVars;
    uint256 private _currentScope;

    // Parser reference
    Parser private _parser;

    // ==================== Entry Point ====================

    function generate(Parser parser) public returns (string memory) {
        _parser = parser;
        _out = new bytes(0);
        _indent = 0;
        _tempCounter = 0;
        _currentScope = 0;

        _writeln("object \"Transpiled\" {");
        _indent++;
        _writeln("code {");
        _indent++;

        // Allocate memory pointer
        _writeln("mstore(0x40, 0x80)");

        // Emit top-level statements (skip function defs, they go into blocks)
        _emitTopLevel(0);

        // Stop execution
        _writeln("stop()");
        _writeln("");

        // Emit functions as sub-objects
        _emitFunctions(0);

        _indent--;
        _writeln("}");
        _indent--;
        _writeln("}");

        return string(_out);
    }

    // ==================== Top-Level Statements ====================

    function _emitTopLevel(uint256 nodeIdx) internal {
        uint256 start = _ai(nodeIdx);
        uint256 count = _ac(nodeIdx);
        for (uint256 i = 0; i < count; i++) {
            uint256 stmtIdx = _aux(start + i);
            if (_nt(stmtIdx) != NodeType.FUNCTION_DEF) {
                _emitStmt(stmtIdx);
            }
        }
    }

    // ==================== Functions as Sub-Objects ====================

    function _emitFunctions(uint256 nodeIdx) internal {
        uint256 start = _ai(nodeIdx);
        uint256 count = _ac(nodeIdx);
        for (uint256 i = 0; i < count; i++) {
            uint256 stmtIdx = _aux(start + i);
            if (_nt(stmtIdx) == NodeType.FUNCTION_DEF) {
                _emitYulFunc(stmtIdx);
            }
        }
    }

    function _emitYulFunc(uint256 nodeIdx) internal {
        string memory name = _sv(nodeIdx);
        uint256 paramCount = _ac(nodeIdx);

        _writeln("");
        _writeIndent();
        _write(string.concat("function ", name, "("));

        // Parameters
        for (uint256 i = 0; i < paramCount; i++) {
            if (i > 0) _write(", ");
            string memory param = _sv(_ea(_ai(nodeIdx) + i));
            _write(param);
        }

        _writeln(") -> result {");
        _indent++;

        // Enter function scope
        _currentScope++;

        // Declare params
        for (uint256 i = 0; i < paramCount; i++) {
            string memory param = _sv(_ea(_ai(nodeIdx) + i));
            bytes32 key = keccak256(bytes(param));
            _declaredVars[_currentScope][key] = true;
        }

        // Body
        if (_c2(nodeIdx) != 0) _emitBlock(_c2(nodeIdx));

        // Default return 0
        _writeIndent();
        _writeln("result := 0");

        _indent--;
        _currentScope--;
        _writeIndent();
        _writeln("}");
    }

    // ==================== Statement Emission ====================

    function _emitStmt(uint256 nodeIdx) internal {
        NodeType nt = _nt(nodeIdx);

        if (nt == NodeType.ASSIGN) {
            _emitAssign(nodeIdx);
        } else if (nt == NodeType.AUG_ASSIGN) {
            _emitAugAssign(nodeIdx);
        } else if (nt == NodeType.IF_STATEMENT) {
            _emitIfStmt(nodeIdx);
        } else if (nt == NodeType.WHILE_LOOP) {
            _emitWhileLoop(nodeIdx);
        } else if (nt == NodeType.FOR_LOOP) {
            _emitForLoop(nodeIdx);
        } else if (nt == NodeType.RETURN_STMT) {
            _emitReturnStmt(nodeIdx);
        } else if (nt == NodeType.EXPR_STMT) {
            _writeIndent();
            _emitExpr(_c1(nodeIdx));
            _writeln("");
        } else if (nt == NodeType.PASS_STMT) {
            // no-op
        } else if (nt == NodeType.BREAK_STMT) {
            _writeIndent();
            _writeln("// break");
        } else if (nt == NodeType.CONTINUE_STMT) {
            _writeIndent();
            _writeln("// continue");
        } else if (nt == NodeType.IMPORT_STMT) {
            _writeIndent();
            _writeln(string.concat("// import ", _sv(nodeIdx)));
        }
    }

    function _emitAssign(uint256 nodeIdx) internal {
        uint256 lhsIdx = _c1(nodeIdx);
        if (_nt(lhsIdx) == NodeType.IDENTIFIER_REF) {
            string memory name = _sv(lhsIdx);
            bytes32 key = keccak256(bytes(name));
            _writeIndent();
            if (!_declaredVars[_currentScope][key]) {
                _write(string.concat("let ", name, " := "));
                _declaredVars[_currentScope][key] = true;
            } else {
                _write(string.concat(name, " := "));
            }
            _emitExpr(_c2(nodeIdx));
            _writeln("");
        } else if (_nt(lhsIdx) == NodeType.INDEX_ACCESS) {
            // list[index] = value → mstore(list + 32 + index * 32, value)
            _writeIndent();
            _write("mstore(add(");
            _emitExpr(_c1(lhsIdx));
            _write(", mul(add(");
            _emitExpr(_c2(lhsIdx));
            _write(", 1), 32)), ");
            _emitExpr(_c2(nodeIdx));
            _writeln(")");
        }
    }

    function _emitAugAssign(uint256 nodeIdx) internal {
        string memory name = _sv(_c1(nodeIdx));
        AugAssignOp op = AugAssignOp(_iv(nodeIdx));
        _writeIndent();
        _write(string.concat(name, " := "));
        if (op == AugAssignOp.PLUS_ASSIGN) _write("add(");
        else if (op == AugAssignOp.MINUS_ASSIGN) _write("sub(");
        else if (op == AugAssignOp.STAR_ASSIGN) _write("mul(");
        else _write("div(");
        _write(string.concat(name, ", "));
        _emitExpr(_c2(nodeIdx));
        _writeln(")");
    }

    function _emitIfStmt(uint256 nodeIdx) internal {
        _writeIndent();
        _write("if ");
        _emitExpr(_c1(nodeIdx));
        _writeln(" {");
        _indent++;
        if (_c2(nodeIdx) != 0) _emitBlock(_c2(nodeIdx));
        _indent--;

        // Elif → else { if ... }
        uint256 elifStart = _ai(nodeIdx);
        uint256 elifCount = _ac(nodeIdx);
        for (uint256 i = 0; i < elifCount; i++) {
            uint256 elifIdx = _ea(elifStart + i);
            _writeIndent();
            _writeln("} {");
            _writeIndent();
            _write("if ");
            _emitExpr(_c1(elifIdx));
            _writeln(" {");
            _indent++;
            if (_c2(elifIdx) != 0) _emitBlock(_c2(elifIdx));
            _indent--;
        }

        if (_c3(nodeIdx) != 0) {
            _writeIndent();
            _writeln("} {");
            _indent++;
            _emitBlock(_c3(nodeIdx));
            _indent--;
        }

        _writeIndent();
        _writeln("}");
        // Close extra braces for elif
        for (uint256 i = 0; i < elifCount; i++) {
            _writeIndent();
            _writeln("}");
        }
    }

    function _emitWhileLoop(uint256 nodeIdx) internal {
        // Yul doesn't have while, use for(init; cond; post)
        _writeIndent();
        _write("for { } ");
        _emitExpr(_c1(nodeIdx));
        _writeln(" {");
        _indent++;
        if (_c2(nodeIdx) != 0) _emitBlock(_c2(nodeIdx));
        _indent--;
        _writeIndent();
        _writeln("}");
    }

    function _emitForLoop(uint256 nodeIdx) internal {
        uint256 iterIdx = _c2(nodeIdx);
        string memory loopVar = _sv(_c1(nodeIdx));

        if (_nt(iterIdx) == NodeType.FUNC_CALL && keccak256(bytes(_sv(iterIdx))) == keccak256("range")) {
            _emitForRange(nodeIdx, iterIdx, loopVar);
        } else {
            _emitForGeneral(nodeIdx, iterIdx, loopVar);
        }
    }

    function _emitForRange(uint256 nodeIdx, uint256 rangeIdx, string memory loopVar) internal {
        uint256 argCount = _ac(rangeIdx);

        string memory iName = string.concat("__i", _toString(_tempCounter));
        string memory stopName = string.concat("__s", _toString(_tempCounter));
        string memory stepName = string.concat("__z", _toString(_tempCounter));
        _tempCounter++;

        // Init
        _writeIndent();
        _write(string.concat("let ", iName, " := "));
        if (argCount >= 2) _emitExpr(_ea(_ai(rangeIdx)));
        else _write("0");
        _writeln("");

        _writeIndent();
        _write(string.concat("let ", stopName, " := "));
        if (argCount == 1) _emitExpr(_ea(_ai(rangeIdx)));
        else _emitExpr(_ea(_ai(rangeIdx) + 1));
        _writeln("");

        _writeIndent();
        _write(string.concat("let ", stepName, " := "));
        if (argCount == 3) _emitExpr(_ea(_ai(rangeIdx) + 2));
        else _write("1");
        _writeln("");

        // For loop
        _writeIndent();
        _write(string.concat("for { let ", loopVar, " := ", iName, " } "));
        _write(string.concat("lt(", loopVar, ", ", stopName, ")"));
        _write(string.concat(" { ", iName, " := add(", iName, ", ", stepName, ") }"));
        _writeln(" {");
        _indent++;
        if (_c3(nodeIdx) != 0) _emitBlock(_c3(nodeIdx));
        _indent--;
        _writeIndent();
        _writeln("}");
    }

    function _emitForGeneral(uint256 nodeIdx, uint256 iterableIdx, string memory loopVar) internal {
        string memory lstName = string.concat("__l", _toString(_tempCounter));
        string memory iName = string.concat("__i", _toString(_tempCounter));
        _tempCounter++;

        _writeIndent();
        _write(string.concat("let ", lstName, " := "));
        if (_nt(iterableIdx) == NodeType.LIST_LITERAL) {
            _emitListLiteralExpr(iterableIdx);
        } else {
            _emitExpr(iterableIdx);
        }
        _writeln("");

        _writeIndent();
        _writeln(string.concat("let ", iName, " := 0"));

        _writeIndent();
        _write(string.concat("for { let ", loopVar, " := mload(add(", lstName, ", mul(0, 32))) } "));
        _write(string.concat("lt(", iName, ", mload(", lstName, "))"));
        _write(string.concat(" { ", iName, " := add(", iName, ", 1) }"));
        _writeln(" {");
        _indent++;

        _writeIndent();
        _writeln(string.concat(loopVar, " := mload(add(", lstName, ", mul(add(", iName, ", 1), 32)))"));

        if (_c3(nodeIdx) != 0) _emitBlock(_c3(nodeIdx));

        _indent--;
        _writeIndent();
        _writeln("}");
    }

    function _emitReturnStmt(uint256 nodeIdx) internal {
        _writeIndent();
        if (_c1(nodeIdx) != 0) {
            _write("result := ");
            _emitExpr(_c1(nodeIdx));
            _writeln("");
        } else {
            _writeln("result := 0");
        }
    }

    // ==================== Expression Emission ====================

    function _emitExpr(uint256 nodeIdx) internal {
        NodeType nt = _nt(nodeIdx);

        if (nt == NodeType.INT_LITERAL) {
            _write(_toString(_iv(nodeIdx)));
        } else if (nt == NodeType.FLOAT_LITERAL) {
            _write(_toString(_iv(nodeIdx)));
        } else if (nt == NodeType.STRING_LITERAL) {
            // Store string in memory and push pointer
            _write("0"); // placeholder — strings need memory allocation
        } else if (nt == NodeType.BOOL_LITERAL) {
            _write(_iv(nodeIdx) == 1 ? "1" : "0");
        } else if (nt == NodeType.NONE_LITERAL) {
            _write("0");
        } else if (nt == NodeType.IDENTIFIER_REF) {
            _write(_sv(nodeIdx));
        } else if (nt == NodeType.BINARY_OP) {
            _emitBinaryOp(nodeIdx);
        } else if (nt == NodeType.UNARY_OP) {
            _emitUnaryOp(nodeIdx);
        } else if (nt == NodeType.COMPARISON) {
            _emitComparison(nodeIdx);
        } else if (nt == NodeType.BOOL_AND) {
            _write("and(");
            _emitExpr(_c1(nodeIdx));
            _write(", ");
            _emitExpr(_c2(nodeIdx));
            _write(")");
        } else if (nt == NodeType.BOOL_OR) {
            _write("or(");
            _emitExpr(_c1(nodeIdx));
            _write(", ");
            _emitExpr(_c2(nodeIdx));
            _write(")");
        } else if (nt == NodeType.BOOL_NOT) {
            _write("iszero(");
            _emitExpr(_c1(nodeIdx));
            _write(")");
        } else if (nt == NodeType.FUNC_CALL) {
            _emitFuncCall(nodeIdx);
        } else if (nt == NodeType.LIST_LITERAL) {
            _emitListLiteralExpr(nodeIdx);
        } else if (nt == NodeType.INDEX_ACCESS) {
            _write("mload(add(");
            _emitExpr(_c1(nodeIdx));
            _write(", mul(add(");
            _emitExpr(_c2(nodeIdx));
            _write(", 1), 32)))");
        } else if (nt == NodeType.DICT_LITERAL || nt == NodeType.SET_LITERAL || nt == NodeType.DICT_ACCESS) {
            _write("0 // dict/set not supported in Yul");
        } else if (nt == NodeType.SLICE_ACCESS) {
            _write("0 // slice not supported in Yul");
        }
    }

    function _emitBinaryOp(uint256 nodeIdx) internal {
        BinaryOpType op = BinaryOpType(_iv(nodeIdx));
        if (op == BinaryOpType.ADD) _write("add(");
        else if (op == BinaryOpType.SUB) _write("sub(");
        else if (op == BinaryOpType.MUL) _write("mul(");
        else if (op == BinaryOpType.DIV) _write("div(");
        else if (op == BinaryOpType.FDIV) _write("div(");
        else if (op == BinaryOpType.MOD) _write("mod(");
        else if (op == BinaryOpType.POW) _write("exp(");
        _emitExpr(_c1(nodeIdx));
        _write(", ");
        _emitExpr(_c2(nodeIdx));
        _write(")");
    }

    function _emitUnaryOp(uint256 nodeIdx) internal {
        UnaryOpType op = UnaryOpType(_iv(nodeIdx));
        if (op == UnaryOpType.NEG) {
            _write("sub(0, ");
            _emitExpr(_c1(nodeIdx));
            _write(")");
        } else {
            _write("iszero(");
            _emitExpr(_c1(nodeIdx));
            _write(")");
        }
    }

    function _emitComparison(uint256 nodeIdx) internal {
        CompOpType op = CompOpType(_iv(nodeIdx));
        if (op == CompOpType.EQ) _write("eq(");
        else if (op == CompOpType.NEQ) _write("iszero(eq(");
        else if (op == CompOpType.LT) _write("lt(");
        else if (op == CompOpType.GT) _write("gt(");
        else if (op == CompOpType.LTE) _write("iszero(gt(");
        else _write("iszero(lt(");
        _emitExpr(_c1(nodeIdx));
        _write(", ");
        _emitExpr(_c2(nodeIdx));
        _write(")");
        if (op == CompOpType.NEQ || op == CompOpType.LTE || op == CompOpType.GTE) {
            _write(")");
        }
    }

    function _emitFuncCall(uint256 nodeIdx) internal {
        string memory name = _sv(nodeIdx);
        uint256 argCount = _ac(nodeIdx);

        // Built-in: print → log1
        if (keccak256(bytes(name)) == keccak256("print")) {
            _write("log1(0, 0, ");
            if (argCount > 0) _emitExpr(_ea(_ai(nodeIdx)));
            else _write("0");
            _write(")");
            return;
        }

        // Built-in: len
        if (keccak256(bytes(name)) == keccak256("len")) {
            _write("mload(");
            _emitExpr(_ea(_ai(nodeIdx)));
            _write(")");
            return;
        }

        // User function
        _write(name);
        _write("(");
        for (uint256 i = 0; i < argCount; i++) {
            if (i > 0) _write(", ");
            _emitExpr(_ea(_ai(nodeIdx) + i));
        }
        _write(")");
    }

    function _emitListLiteralExpr(uint256 nodeIdx) internal {
        uint256 elemCount = _ac(nodeIdx);
        string memory ptrName = string.concat("__lp", _toString(_tempCounter));
        _tempCounter++;

        // Allocate memory: length slot + elements
        _writeln("");
        _writeIndent();
        _write(string.concat("{ let ", ptrName, " := mload(0x40) "));
        _write(string.concat("mstore(", ptrName, ", ", _toString(elemCount), ") "));
        for (uint256 i = 0; i < elemCount; i++) {
            _write(string.concat("mstore(add(", ptrName, ", ", _toString((i + 1) * 32), "), "));
            _emitExpr(_ea(_ai(nodeIdx) + i));
            _write(") ");
        }
        _write(string.concat("mstore(0x40, add(", ptrName, ", ", _toString((elemCount + 1) * 32), ")) "));
        _write(string.concat(ptrName, " }"));
    }

    // ==================== Block ====================

    function _emitBlock(uint256 nodeIdx) internal {
        uint256 start = _ai(nodeIdx);
        uint256 count = _ac(nodeIdx);
        for (uint256 i = 0; i < count; i++) {
            _emitStmt(_aux(start + i));
        }
    }

    // ==================== Output Helpers ====================

    function _write(string memory s) internal {
        bytes memory b = bytes(s);
        for (uint256 i = 0; i < b.length; i++) {
            _out.push(b[i]);
        }
    }

    function _writeln(string memory s) internal {
        _write(s);
        _write("\n");
    }

    function _writeIndent() internal {
        for (uint256 i = 0; i < _indent; i++) {
            _write("    ");
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

    // ==================== Parser Accessors ====================

    function _nt(uint256 idx) internal view returns (NodeType) { return _parser.getNodeType(idx); }
    function _c1(uint256 idx) internal view returns (uint256) { return _parser.getChild1(idx); }
    function _c2(uint256 idx) internal view returns (uint256) { return _parser.getChild2(idx); }
    function _c3(uint256 idx) internal view returns (uint256) { return _parser.getChild3(idx); }
    function _ai(uint256 idx) internal view returns (uint256) { return _parser.getAuxIndex(idx); }
    function _ac(uint256 idx) internal view returns (uint256) { return _parser.getAuxCount(idx); }
    function _iv(uint256 idx) internal view returns (uint256) { return _parser.getIntValue(idx); }
    function _sv(uint256 idx) internal view returns (string memory) { return _parser.getStrValue(idx); }
    function _aux(uint256 idx) internal view returns (uint256) { return _parser.getAuxData(idx); }
    function _ea(uint256 idx) internal view returns (uint256) { return _parser.getExprAuxData(idx); }

    // ==================== Public Getters ====================

    function getOutput() public view returns (string memory) {
        return string(_out);
    }
}
