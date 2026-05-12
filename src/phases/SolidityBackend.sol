// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {NodeType, BinaryOpType, UnaryOpType, CompOpType, AugAssignOp} from "../types/ASTNode.sol";
import {Parser} from "./Parser.sol";

/// @title SolidityBackend — AST to Solidity source code transpiler
/// @notice Walks the AST and emits Solidity source code as a string.
///         Python functions become Solidity internal functions.
///         Variables become contract-level state or local variables.
contract SolidityBackend {
    // Output buffer
    bytes private _out;

    // Indentation level
    uint256 private _indent;

    // Variable tracking for scope
    mapping(uint256 => mapping(bytes32 => bool)) private _declaredVars; // scope → name → declared
    mapping(uint256 => uint256) private _scopeVarCount;
    uint256 private _currentScope;

    // Function names (to emit forward declarations as internal functions)
    string[] private _funcNames;
    mapping(bytes32 => bool) private _funcDefined;

    // Temp counter for unique names
    uint256 private _tempCounter;

    // Parser reference
    Parser private _parser;

    // ==================== Entry Point ====================

    function generate(Parser parser) public returns (string memory) {
        _parser = parser;
        _out = new bytes(0);
        _indent = 0;
        _currentScope = 0;
        _tempCounter = 0;

        // Contract header
        _writeln("// SPDX-License-Identifier: MIT");
        _writeln("pragma solidity ^0.8.20;");
        _writeln("");
        _writeln("contract Transpiled {");
        _writeln("    event Print(uint256[] values);");
        _writeln("    event PrintString(string value);");
        _writeln("    event Result(uint256 value);");
        _writeln("");

        // First pass: collect function names
        _collectFuncDefs(0);

        // Second pass: emit state variables and functions
        _indent = 1;
        _emitContractBody(0);
        _indent = 0;

        _writeln("}");
        return string(_out);
    }

    // ==================== First Pass: Collect Functions ====================

    function _collectFuncDefs(uint256 nodeIdx) internal {
        uint256 start = _ai(nodeIdx);
        uint256 count = _ac(nodeIdx);
        for (uint256 i = 0; i < count; i++) {
            uint256 stmtIdx = _aux(start + i);
            if (_nt(stmtIdx) == NodeType.FUNCTION_DEF) {
                string memory name = _sv(stmtIdx);
                bytes32 key = keccak256(bytes(name));
                if (!_funcDefined[key]) {
                    _funcNames.push(name);
                    _funcDefined[key] = true;
                }
            }
        }
    }

    // ==================== Second Pass: Emit Contract Body ====================

    function _emitContractBody(uint256 nodeIdx) internal {
        uint256 start = _ai(nodeIdx);
        uint256 count = _ac(nodeIdx);

        // First emit function definitions
        bool hasFuncs = false;
        for (uint256 i = 0; i < count; i++) {
            uint256 stmtIdx = _aux(start + i);
            if (_nt(stmtIdx) == NodeType.FUNCTION_DEF) {
                _emitFuncDef(stmtIdx);
                hasFuncs = true;
            }
        }

        // Then emit execute() function with remaining statements
        _writeln("    function execute() public {");
        _indent = 2;
        for (uint256 i = 0; i < count; i++) {
            uint256 stmtIdx = _aux(start + i);
            if (_nt(stmtIdx) != NodeType.FUNCTION_DEF) {
                _emitStmt(stmtIdx);
            }
        }
        _indent = 1;
        _writeln("    }");
    }

    // ==================== Statement Emission ====================

    function _emitStmt(uint256 nodeIdx) internal {
        NodeType nt = _nt(nodeIdx);

        if (nt == NodeType.ASSIGN) {
            _emitAssign(nodeIdx);
        } else if (nt == NodeType.AUG_ASSIGN) {
            _emitAugAssign(nodeIdx);
        } else if (nt == NodeType.FUNCTION_DEF) {
            // Already handled in _emitContractBody
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
            _writeln(";");
        } else if (nt == NodeType.PASS_STMT) {
            // no-op in Solidity
        } else if (nt == NodeType.BREAK_STMT) {
            _writeIndent();
            _writeln("break;");
        } else if (nt == NodeType.CONTINUE_STMT) {
            _writeIndent();
            _writeln("continue;");
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
                _write("uint256 ");
                _declaredVars[_currentScope][key] = true;
            }
            _write(name);
            _write(" = ");
            _emitExpr(_c2(nodeIdx));
            _writeln(";");
        } else if (_nt(lhsIdx) == NodeType.INDEX_ACCESS) {
            // list[index] = value
            _writeIndent();
            _emitExpr(_c1(lhsIdx));
            _write("[");
            _emitExpr(_c2(lhsIdx));
            _write("] = ");
            _emitExpr(_c2(nodeIdx));
            _writeln(";");
        } else if (_nt(lhsIdx) == NodeType.DICT_ACCESS) {
            // dict[key] = value — not directly supported as assignment in Solidity
            // Skip for now (dicts aren't really Solidity-compatible)
            _writeIndent();
            _writeln("// dict assignment not supported in Solidity backend");
        }
    }

    function _emitAugAssign(uint256 nodeIdx) internal {
        string memory name = _sv(_c1(nodeIdx));
        AugAssignOp op = AugAssignOp(_iv(nodeIdx));
        _writeIndent();
        _write(name);
        if (op == AugAssignOp.PLUS_ASSIGN) _write(" += ");
        else if (op == AugAssignOp.MINUS_ASSIGN) _write(" -= ");
        else if (op == AugAssignOp.STAR_ASSIGN) _write(" *= ");
        else _write(" /= ");
        _emitExpr(_c2(nodeIdx));
        _writeln(";");
    }

    function _emitIfStmt(uint256 nodeIdx) internal {
        _writeIndent();
        _write("if (");
        _emitExpr(_c1(nodeIdx));
        _writeln(") {");
        _indent++;
        if (_c2(nodeIdx) != 0) _emitBlock(_c2(nodeIdx));
        _indent--;

        // Elif branches → else if
        uint256 elifStart = _ai(nodeIdx);
        uint256 elifCount = _ac(nodeIdx);
        for (uint256 i = 0; i < elifCount; i++) {
            uint256 elifIdx = _ea(elifStart + i);
            _writeIndent();
            _write("} else if (");
            _emitExpr(_c1(elifIdx));
            _writeln(") {");
            _indent++;
            if (_c2(elifIdx) != 0) _emitBlock(_c2(elifIdx));
            _indent--;
        }

        // Else body
        if (_c3(nodeIdx) != 0) {
            _writeIndent();
            _writeln("} else {");
            _indent++;
            _emitBlock(_c3(nodeIdx));
            _indent--;
        }

        _writeIndent();
        _writeln("}");
    }

    function _emitWhileLoop(uint256 nodeIdx) internal {
        _writeIndent();
        _write("while (");
        _emitExpr(_c1(nodeIdx));
        _writeln(") {");
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
            // General iterable: for-list or variable
            _emitForGeneral(nodeIdx, iterIdx, loopVar);
        }
    }

    function _emitForRange(uint256 nodeIdx, uint256 rangeIdx, string memory loopVar) internal {
        uint256 argCount = _ac(rangeIdx);

        // Generate unique temp names
        string memory iName = string.concat("__fi", _toString(_tempCounter));
        string memory stopName = string.concat("__fs", _tempCounter > 0 ? _toString(_tempCounter) : "");
        if (_tempCounter == 0) stopName = "__fs0";
        else stopName = string.concat("__fs", _toString(_tempCounter));
        string memory stepName = string.concat("__fz", _toString(_tempCounter));
        _tempCounter++;

        // Declare loop variables
        _writeIndent();
        _writeln(string.concat("uint256 ", iName, ";"));
        _writeIndent();
        _writeln(string.concat("uint256 ", stopName, ";"));
        _writeIndent();
        _writeln(string.concat("uint256 ", stepName, ";"));

        // Initialize based on arg count
        _writeIndent();
        if (argCount == 1) {
            _writeln(string.concat(iName, " = 0;"));
            _writeIndent();
            _write(string.concat(stopName, " = "));
            _emitExpr(_ea(_ai(rangeIdx)));
            _writeln(";");
            _writeIndent();
            _writeln(string.concat(stepName, " = 1;"));
        } else if (argCount == 2) {
            _write(string.concat(iName, " = "));
            _emitExpr(_ea(_ai(rangeIdx)));
            _writeln(";");
            _writeIndent();
            _write(string.concat(stopName, " = "));
            _emitExpr(_ea(_ai(rangeIdx) + 1));
            _writeln(";");
            _writeIndent();
            _writeln(string.concat(stepName, " = 1;"));
        } else {
            _write(string.concat(iName, " = "));
            _emitExpr(_ea(_ai(rangeIdx)));
            _writeln(";");
            _writeIndent();
            _write(string.concat(stopName, " = "));
            _emitExpr(_ea(_ai(rangeIdx) + 1));
            _writeln(";");
            _writeIndent();
            _write(string.concat(stepName, " = "));
            _emitExpr(_ea(_ai(rangeIdx) + 2));
            _writeln(";");
        }

        // For loop with index
        _writeIndent();
        _writeln(string.concat("for (", iName, " = ", iName, "; ", iName, " < ", stopName, "; ", iName, " += ", stepName, ") {"));
        _indent++;

        // Assign loop variable
        _writeIndent();
        _writeln(string.concat("uint256 ", loopVar, " = ", iName, ";"));

        // Body
        if (_c3(nodeIdx) != 0) _emitBlock(_c3(nodeIdx));

        _indent--;
        _writeIndent();
        _writeln("}");
    }

    function _emitForGeneral(uint256 nodeIdx, uint256 iterableIdx, string memory loopVar) internal {
        string memory lstName = string.concat("__fl", _toString(_tempCounter));
        string memory iName = string.concat("__fi", _toString(_tempCounter));
        _tempCounter++;

        // Store iterable
        _writeIndent();
        _writeln(string.concat("uint256[] memory ", lstName, ";"));
        _writeIndent();
        _write(string.concat(lstName, " = "));
        if (_nt(iterableIdx) == NodeType.LIST_LITERAL) {
            _emitListLiteralExpr(iterableIdx);
        } else {
            _emitExpr(iterableIdx);
        }
        _writeln(";");

        _writeIndent();
        _writeln(string.concat("uint256 ", iName, ";"));

        _writeIndent();
        _writeln(string.concat("for (", iName, " = 0; ", iName, " < ", lstName, ".length; ", iName, "++) {"));
        _indent++;

        _writeIndent();
        _writeln(string.concat("uint256 ", loopVar, " = ", lstName, "[", iName, "];"));

        if (_c3(nodeIdx) != 0) _emitBlock(_c3(nodeIdx));

        _indent--;
        _writeIndent();
        _writeln("}");
    }

    function _emitReturnStmt(uint256 nodeIdx) internal {
        _writeIndent();
        if (_c1(nodeIdx) != 0) {
            _write("return ");
            _emitExpr(_c1(nodeIdx));
            _writeln(";");
        } else {
            _writeln("return;");
        }
    }

    // ==================== Function Definition ====================

    function _emitFuncDef(uint256 nodeIdx) internal {
        string memory name = _sv(nodeIdx);
        uint256 paramCount = _ac(nodeIdx);

        _writeIndent();
        _write(string.concat("function ", name, "("));

        // Parameters
        for (uint256 i = 0; i < paramCount; i++) {
            if (i > 0) _write(", ");
            string memory param = _sv(_ea(_ai(nodeIdx) + i));
            _write(string.concat("uint256 ", param));
        }

        _writeln(") internal pure returns (uint256) {");

        // Enter function scope
        _currentScope++;
        _indent++;

        // Declare params as local vars
        for (uint256 i = 0; i < paramCount; i++) {
            string memory param = _sv(_ea(_ai(nodeIdx) + i));
            bytes32 key = keccak256(bytes(param));
            _declaredVars[_currentScope][key] = true;
        }

        // Body
        if (_c2(nodeIdx) != 0) _emitBlock(_c2(nodeIdx));

        // Default return 0
        _writeIndent();
        _writeln("return 0;");

        _indent--;
        _currentScope--;
        _writeIndent();
        _writeln("}");
        _writeln("");
    }

    // ==================== Expression Emission ====================

    function _emitExpr(uint256 nodeIdx) internal {
        NodeType nt = _nt(nodeIdx);

        if (nt == NodeType.INT_LITERAL) {
            _write(_toString(_iv(nodeIdx)));
        } else if (nt == NodeType.FLOAT_LITERAL) {
            _write(_toString(_iv(nodeIdx)));
        } else if (nt == NodeType.STRING_LITERAL) {
            _write("\"");
            _write(_sv(nodeIdx));
            _write("\"");
        } else if (nt == NodeType.BOOL_LITERAL) {
            _write(_iv(nodeIdx) == 1 ? "true" : "false");
        } else if (nt == NodeType.NONE_LITERAL) {
            _write("0"); // None → 0 in Solidity
        } else if (nt == NodeType.IDENTIFIER_REF) {
            _write(_sv(nodeIdx));
        } else if (nt == NodeType.BINARY_OP) {
            _emitBinaryOp(nodeIdx);
        } else if (nt == NodeType.UNARY_OP) {
            _emitUnaryOp(nodeIdx);
        } else if (nt == NodeType.COMPARISON) {
            _emitComparison(nodeIdx);
        } else if (nt == NodeType.BOOL_AND) {
            _emitExpr(_c1(nodeIdx));
            _write(" && ");
            _emitExpr(_c2(nodeIdx));
        } else if (nt == NodeType.BOOL_OR) {
            _emitExpr(_c1(nodeIdx));
            _write(" || ");
            _emitExpr(_c2(nodeIdx));
        } else if (nt == NodeType.BOOL_NOT) {
            _write("!");
            _emitExpr(_c1(nodeIdx));
        } else if (nt == NodeType.FUNC_CALL) {
            _emitFuncCall(nodeIdx);
        } else if (nt == NodeType.LIST_LITERAL) {
            _emitListLiteralExpr(nodeIdx);
        } else if (nt == NodeType.INDEX_ACCESS) {
            _emitExpr(_c1(nodeIdx));
            _write("[");
            _emitExpr(_c2(nodeIdx));
            _write("]");
        } else if (nt == NodeType.SLICE_ACCESS) {
            // Solidity doesn't have slice syntax — emit a comment
            _write("/* slice not supported */");
        } else if (nt == NodeType.DICT_LITERAL) {
            _write("/* dict not supported */");
        } else if (nt == NodeType.SET_LITERAL) {
            _write("/* set not supported */");
        } else if (nt == NodeType.DICT_ACCESS) {
            _write("/* dict access not supported */");
        }
    }

    function _emitBinaryOp(uint256 nodeIdx) internal {
        BinaryOpType op = BinaryOpType(_iv(nodeIdx));
        _write("(");
        _emitExpr(_c1(nodeIdx));
        if (op == BinaryOpType.ADD) _write(" + ");
        else if (op == BinaryOpType.SUB) _write(" - ");
        else if (op == BinaryOpType.MUL) _write(" * ");
        else if (op == BinaryOpType.DIV) _write(" / ");
        else if (op == BinaryOpType.FDIV) _write(" / ");
        else if (op == BinaryOpType.MOD) _write(" % ");
        else if (op == BinaryOpType.POW) {
            // No ** in Solidity — would need a loop. Emit comment for now.
            _write(" /* pow */ ");
        }
        _emitExpr(_c2(nodeIdx));
        _write(")");
    }

    function _emitUnaryOp(uint256 nodeIdx) internal {
        UnaryOpType op = UnaryOpType(_iv(nodeIdx));
        if (op == UnaryOpType.NEG) {
            _write("(-");
            _emitExpr(_c1(nodeIdx));
            _write(")");
        } else {
            _write("!");
            _emitExpr(_c1(nodeIdx));
        }
    }

    function _emitComparison(uint256 nodeIdx) internal {
        CompOpType op = CompOpType(_iv(nodeIdx));
        _write("(");
        _emitExpr(_c1(nodeIdx));
        if (op == CompOpType.EQ) _write(" == ");
        else if (op == CompOpType.NEQ) _write(" != ");
        else if (op == CompOpType.LT) _write(" < ");
        else if (op == CompOpType.GT) _write(" > ");
        else if (op == CompOpType.LTE) _write(" <= ");
        else _write(" >= ");
        _emitExpr(_c2(nodeIdx));
        _write(")");
    }

    function _emitFuncCall(uint256 nodeIdx) internal {
        string memory name = _sv(nodeIdx);
        uint256 argCount = _ac(nodeIdx);

        // Built-in: print
        if (keccak256(bytes(name)) == keccak256("print")) {
            _write("/* print(");
            for (uint256 i = 0; i < argCount; i++) {
                if (i > 0) _write(", ");
                _emitExpr(_ea(_ai(nodeIdx) + i));
            }
            _write(") */");
            return;
        }

        // Built-in: len
        if (keccak256(bytes(name)) == keccak256("len")) {
            _emitExpr(_ea(_ai(nodeIdx)));
            _write(".length");
            return;
        }

        // Built-in: int
        if (keccak256(bytes(name)) == keccak256("int")) {
            _emitExpr(_ea(_ai(nodeIdx)));
            return;
        }

        // Built-in: str
        if (keccak256(bytes(name)) == keccak256("str")) {
            _emitExpr(_ea(_ai(nodeIdx)));
            return;
        }

        // User function call
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
        _write("new uint256[](");
        _write(_toString(elemCount));
        _write(")");
        if (elemCount > 0) {
            _writeln(" {");
            _indent++;
            for (uint256 i = 0; i < elemCount; i++) {
                _writeIndent();
                _emitExpr(_ea(_ai(nodeIdx) + i));
                if (i < elemCount - 1) _writeln(",");
                else _writeln("");
            }
            _indent--;
            _writeIndent();
            _write("}");
        }
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
