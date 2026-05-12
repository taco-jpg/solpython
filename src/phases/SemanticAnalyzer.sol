// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {NodeType} from "../types/ASTNode.sol";
import {TypeTag} from "../types/TypeInfo.sol";
import {Parser} from "./Parser.sol";

contract SemanticAnalyzer {
    // Type storage
    TypeTag[] private typeTags;
    uint256[] private innerTypes;
    uint256[] private auxTypeStarts;
    uint256[] private auxTypeCounts;
    uint256[] private auxTypes;

    // Symbol table: scopeId => name(bytes32) => typeIndex
    mapping(uint256 => mapping(bytes32 => uint256)) private symTypes;
    mapping(uint256 => mapping(bytes32 => bool)) private symDefined;

    // Scope metadata
    uint256[] private scopeParents;
    uint256[] private scopeSymbolCounts;
    uint256[] private scopeStack;

    // Per-node type results
    mapping(uint256 => uint256) private nodeTypes;

    // Unbound local tracking
    mapping(uint256 => mapping(bytes32 => bool)) private scopeIsLocal; // scope => nameHash => is local (assigned in function)
    mapping(uint256 => mapping(bytes32 => bool)) private scopeAssigned; // scope => nameHash => assigned before current point

    // Errors
    string[] private errors;

    // Parser reference
    Parser private parser;

    function analyze(Parser _parser) public returns (bool) {
        parser = _parser;

        // Create global scope
        scopeParents.push(0);
        scopeSymbolCounts.push(0);
        scopeStack.push(0);

        // Analyze program (node 0)
        _analyzeBlock(0);

        return errors.length == 0;
    }

    // ==================== Node Access Helpers ====================

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

    // ==================== Block / Statement Analysis ====================

    function _analyzeBlock(uint256 nodeIdx) internal {
        uint256 start = _ai(nodeIdx);
        uint256 count = _ac(nodeIdx);
        for (uint256 i = 0; i < count; i++) {
            _analyzeStmt(_aux(start + i));
        }
    }

    function _analyzeStmt(uint256 nodeIdx) internal {
        NodeType nt = _nt(nodeIdx);

        if (nt == NodeType.ASSIGN) {
            _analyzeAssign(nodeIdx);
        } else if (nt == NodeType.AUG_ASSIGN) {
            _analyzeAugAssign(nodeIdx);
        } else if (nt == NodeType.FUNCTION_DEF) {
            _analyzeFuncDef(nodeIdx);
        } else if (nt == NodeType.IF_STATEMENT) {
            _analyzeIfStmt(nodeIdx);
        } else if (nt == NodeType.WHILE_LOOP) {
            _analyzeWhileLoop(nodeIdx);
        } else if (nt == NodeType.FOR_LOOP) {
            _analyzeForLoop(nodeIdx);
        } else if (nt == NodeType.RETURN_STMT) {
            _analyzeReturnStmt(nodeIdx);
        } else if (nt == NodeType.CLASS_DEF) {
            _analyzeClassDef(nodeIdx);
        } else if (nt == NodeType.IMPORT_STMT) {
            // No-op: imports resolved at compiler level
        } else if (nt == NodeType.TRY_STMT) {
            if (_c1(nodeIdx) != 0) _analyzeBlock(_c1(nodeIdx));
            uint256 es = _ai(nodeIdx);
            uint256 ec = _ac(nodeIdx);
            for (uint256 i = 0; i < ec; i++) {
                uint256 excIdx = _ea(es + i);
                if (_c2(excIdx) != 0) _analyzeBlock(_c2(excIdx));
            }
            if (_c2(nodeIdx) != 0) _analyzeBlock(_c2(nodeIdx));
        } else if (nt == NodeType.RAISE_STMT) {
            if (_c1(nodeIdx) != 0) _analyzeExpr(_c1(nodeIdx));
        } else if (nt == NodeType.EXPR_STMT) {
            _analyzeExpr(_c1(nodeIdx));
        }
    }

    // Pre-scan a block for all assigned variables to determine locals
    function _prescanAssignments(uint256 nodeIdx, uint256 scope) internal {
        uint256 start = _ai(nodeIdx);
        uint256 count = _ac(nodeIdx);
        for (uint256 i = 0; i < count; i++) {
            uint256 stmtIdx = _aux(start + i);
            NodeType nt = _nt(stmtIdx);
            if (nt == NodeType.ASSIGN) {
                uint256 lhsIdx = _c1(stmtIdx);
                if (_nt(lhsIdx) == NodeType.IDENTIFIER_REF) {
                    scopeIsLocal[scope][keccak256(bytes(_sv(lhsIdx)))] = true;
                }
            } else if (nt == NodeType.AUG_ASSIGN) {
                uint256 lhsIdx = _c1(stmtIdx);
                if (_nt(lhsIdx) == NodeType.IDENTIFIER_REF) {
                    scopeIsLocal[scope][keccak256(bytes(_sv(lhsIdx)))] = true;
                }
            } else if (nt == NodeType.FOR_LOOP) {
                uint256 varIdx = _c1(stmtIdx);
                if (_nt(varIdx) == NodeType.IDENTIFIER_REF) {
                    scopeIsLocal[scope][keccak256(bytes(_sv(varIdx)))] = true;
                }
            }
        }
    }

    function _analyzeAssign(uint256 nodeIdx) internal {
        uint256 rhsType = _analyzeExpr(_c2(nodeIdx));
        uint256 lhsIdx = _c1(nodeIdx);
        if (_nt(lhsIdx) == NodeType.IDENTIFIER_REF) {
            bytes32 key = keccak256(bytes(_sv(lhsIdx)));
            scopeAssigned[_currentScope()][key] = true;
            _defineSymbol(_sv(lhsIdx), rhsType);
        }
        nodeTypes[nodeIdx] = rhsType;
    }

    function _analyzeAugAssign(uint256 nodeIdx) internal {
        uint256 rhsType = _analyzeExpr(_c2(nodeIdx));
        uint256 lhsType = _analyzeExpr(_c1(nodeIdx));
        nodeTypes[nodeIdx] = _inferBinaryType(lhsType, rhsType);
    }

    function _analyzeFuncDef(uint256 nodeIdx) internal {
        uint256 paramStart = _ai(nodeIdx);
        uint256 paramCount = _ac(nodeIdx);

        // Create function type
        uint256 funcTypeIdx = _createType(TypeTag.FUNCTION, 0, auxTypes.length, paramCount);
        for (uint256 i = 0; i < paramCount; i++) {
            auxTypes.push(0);
        }

        _defineSymbol(_sv(nodeIdx), funcTypeIdx);

        // Enter function scope
        uint256 newScope = scopeParents.length;
        scopeParents.push(_currentScope());
        scopeSymbolCounts.push(0);
        scopeStack.push(newScope);

        // Define params
        for (uint256 i = 0; i < paramCount; i++) {
            _defineSymbol(_sv(_ea(paramStart + i)), 0);
        }

        // Pre-scan body for assigned variables (determines what's local)
        uint256 bodyIdx = _c2(nodeIdx);
        if (bodyIdx != 0) _prescanAssignments(bodyIdx, newScope);

        // Analyze body
        if (bodyIdx != 0) _analyzeBlock(bodyIdx);

        scopeStack.pop();
        nodeTypes[nodeIdx] = funcTypeIdx;
    }

    function _analyzeIfStmt(uint256 nodeIdx) internal {
        _analyzeExpr(_c1(nodeIdx));
        if (_c2(nodeIdx) != 0) _analyzeBlock(_c2(nodeIdx));

        uint256 elifStart = _ai(nodeIdx);
        uint256 elifCount = _ac(nodeIdx);
        for (uint256 i = 0; i < elifCount; i++) {
            uint256 elifIdx = _ea(elifStart + i);
            _analyzeExpr(_c1(elifIdx));
            if (_c2(elifIdx) != 0) _analyzeBlock(_c2(elifIdx));
        }

        if (_c3(nodeIdx) != 0) _analyzeBlock(_c3(nodeIdx));
    }

    function _analyzeWhileLoop(uint256 nodeIdx) internal {
        _analyzeExpr(_c1(nodeIdx));
        if (_c2(nodeIdx) != 0) _analyzeBlock(_c2(nodeIdx));
    }

    function _analyzeForLoop(uint256 nodeIdx) internal {
        uint256 iterType = _analyzeExpr(_c2(nodeIdx));
        uint256 varIdx = _c1(nodeIdx);
        if (_nt(varIdx) == NodeType.IDENTIFIER_REF) {
            uint256 elemType = 0;
            if (iterType != 0 && typeTags[iterType] == TypeTag.LIST) {
                elemType = innerTypes[iterType];
            }
            _defineSymbol(_sv(varIdx), elemType);
        }
        if (_c3(nodeIdx) != 0) _analyzeBlock(_c3(nodeIdx));
    }

    function _analyzeReturnStmt(uint256 nodeIdx) internal {
        if (_c1(nodeIdx) != 0) _analyzeExpr(_c1(nodeIdx));
    }

    function _analyzeClassDef(uint256 nodeIdx) internal {
        // Create a type for the class so typeTags index is valid
        uint256 classTypeIdx = _createType(TypeTag.INT, 0, 0, 0);
        _defineSymbol(_sv(nodeIdx), classTypeIdx);
        uint256 newScope = scopeParents.length;
        scopeParents.push(_currentScope());
        scopeSymbolCounts.push(0);
        scopeStack.push(newScope);
        if (_c2(nodeIdx) != 0) _analyzeBlock(_c2(nodeIdx));
        scopeStack.pop();
    }

    // ==================== Expression Analysis ====================

    function _analyzeExpr(uint256 nodeIdx) internal returns (uint256) {
        NodeType nt = _nt(nodeIdx);

        if (nt == NodeType.INT_LITERAL) {
            nodeTypes[nodeIdx] = _getOrCreateType(TypeTag.INT, 0, 0, 0);
        } else if (nt == NodeType.FLOAT_LITERAL) {
            nodeTypes[nodeIdx] = _getOrCreateType(TypeTag.FLOAT, 0, 0, 0);
        } else if (nt == NodeType.STRING_LITERAL) {
            nodeTypes[nodeIdx] = _getOrCreateType(TypeTag.STRING, 0, 0, 0);
        } else if (nt == NodeType.BOOL_LITERAL) {
            nodeTypes[nodeIdx] = _getOrCreateType(TypeTag.BOOL, 0, 0, 0);
        } else if (nt == NodeType.NONE_LITERAL) {
            nodeTypes[nodeIdx] = _getOrCreateType(TypeTag.NONE, 0, 0, 0);
        } else if (nt == NodeType.IDENTIFIER_REF) {
            _checkUnboundLocal(_sv(nodeIdx), nodeIdx);
            nodeTypes[nodeIdx] = _lookupSymbolAt(_sv(nodeIdx), nodeIdx);
        } else if (nt == NodeType.BINARY_OP) {
            uint256 lt = _analyzeExpr(_c1(nodeIdx));
            uint256 rt = _analyzeExpr(_c2(nodeIdx));
            nodeTypes[nodeIdx] = _inferBinaryType(lt, rt);
        } else if (nt == NodeType.UNARY_OP) {
            nodeTypes[nodeIdx] = _analyzeExpr(_c1(nodeIdx));
        } else if (nt == NodeType.COMPARISON) {
            _analyzeExpr(_c1(nodeIdx));
            _analyzeExpr(_c2(nodeIdx));
            nodeTypes[nodeIdx] = _getOrCreateType(TypeTag.BOOL, 0, 0, 0);
        } else if (nt == NodeType.BOOL_AND || nt == NodeType.BOOL_OR) {
            _analyzeExpr(_c1(nodeIdx));
            _analyzeExpr(_c2(nodeIdx));
            nodeTypes[nodeIdx] = _getOrCreateType(TypeTag.BOOL, 0, 0, 0);
        } else if (nt == NodeType.BOOL_NOT) {
            _analyzeExpr(_c1(nodeIdx));
            nodeTypes[nodeIdx] = _getOrCreateType(TypeTag.BOOL, 0, 0, 0);
        } else if (nt == NodeType.FUNC_CALL) {
            nodeTypes[nodeIdx] = _analyzeFuncCall(nodeIdx);
        } else if (nt == NodeType.LIST_LITERAL) {
            nodeTypes[nodeIdx] = _analyzeListLiteral(nodeIdx);
        } else if (nt == NodeType.INDEX_ACCESS) {
            uint256 targetType = _analyzeExpr(_c1(nodeIdx));
            _analyzeExpr(_c2(nodeIdx));
            if (targetType != 0 && typeTags[targetType] == TypeTag.LIST) {
                nodeTypes[nodeIdx] = innerTypes[targetType];
            }
        } else if (nt == NodeType.ATTR_ACCESS) {
            _analyzeExpr(_c1(nodeIdx));
        } else if (nt == NodeType.METHOD_CALL) {
            _analyzeExpr(_c1(nodeIdx));
            uint256 mcArgStart = _ai(nodeIdx);
            uint256 mcArgCount = _ac(nodeIdx);
            for (uint256 i = 0; i < mcArgCount; i++) {
                _analyzeExpr(_ea(mcArgStart + i));
            }
        }

        return nodeTypes[nodeIdx];
    }

    function _analyzeFuncCall(uint256 nodeIdx) internal returns (uint256) {
        uint256 argStart = _ai(nodeIdx);
        uint256 argCount = _ac(nodeIdx);
        for (uint256 i = 0; i < argCount; i++) {
            _analyzeExpr(_ea(argStart + i));
        }

        string memory name = _sv(nodeIdx);

        // Check built-ins first to avoid spurious "undefined" errors
        if (_isBuiltin(name)) {
            if (_strEq(name, "print")) return _getOrCreateType(TypeTag.NONE, 0, 0, 0);
            if (_strEq(name, "len")) return _getOrCreateType(TypeTag.INT, 0, 0, 0);
            if (_strEq(name, "int")) return _getOrCreateType(TypeTag.INT, 0, 0, 0);
            if (_strEq(name, "str")) return _getOrCreateType(TypeTag.STRING, 0, 0, 0);
            if (_strEq(name, "bool")) return _getOrCreateType(TypeTag.BOOL, 0, 0, 0);
            if (_strEq(name, "range")) {
                uint256 intType = _getOrCreateType(TypeTag.INT, 0, 0, 0);
                return _getOrCreateType(TypeTag.LIST, intType, 0, 0);
            }
        }

        // Check string methods (method calls with object as first arg)
        if (argCount >= 1) {
            bytes32 nameHash = keccak256(bytes(name));
            uint256 stringType = _getOrCreateType(TypeTag.STRING, 0, 0, 0);
            uint256 boolType = _getOrCreateType(TypeTag.BOOL, 0, 0, 0);
            uint256 intType = _getOrCreateType(TypeTag.INT, 0, 0, 0);

            // s.upper() → STRING
            if (nameHash == keccak256("upper") && argCount == 1) {
                return stringType;
            }
            // s.lower() → STRING
            if (nameHash == keccak256("lower") && argCount == 1) {
                return stringType;
            }
            // s.contains(sub) → BOOL
            if (nameHash == keccak256("contains") && argCount == 2) {
                return boolType;
            }
            // s.split(delim) → LIST[STRING]
            if (nameHash == keccak256("split") && argCount == 2) {
                return _getOrCreateType(TypeTag.LIST, stringType, 0, 0);
            }
            // s.charAt(i) → INT
            if (nameHash == keccak256("charAt") && argCount == 2) {
                return intType;
            }
        }

        uint256 funcTypeIdx = _lookupSymbolAt(name, nodeIdx);
        if (funcTypeIdx != NOT_FOUND && typeTags[funcTypeIdx] == TypeTag.FUNCTION) {
            if (auxTypeCounts[funcTypeIdx] != argCount) {
                _addErrorAt(string(abi.encodePacked(
                    "Function '", name, "' expects ", _toString(auxTypeCounts[funcTypeIdx]),
                    " args, got ", _toString(argCount)
                )), nodeIdx);
            }
            return innerTypes[funcTypeIdx];
        }

        return 0;
    }

    function _analyzeListLiteral(uint256 nodeIdx) internal returns (uint256) {
        uint256 elemStart = _ai(nodeIdx);
        uint256 elemCount = _ac(nodeIdx);
        uint256 elemType = 0;
        for (uint256 i = 0; i < elemCount; i++) {
            uint256 t = _analyzeExpr(_ea(elemStart + i));
            if (i == 0) elemType = t;
        }
        uint256 listType = _getOrCreateType(TypeTag.LIST, elemType, 0, 0);
        nodeTypes[nodeIdx] = listType;
        return listType;
    }

    // ==================== Type Helpers ====================

    function _inferBinaryType(uint256 lt, uint256 rt) internal returns (uint256) {
        TypeTag lTag = lt < typeTags.length ? typeTags[lt] : TypeTag.UNKNOWN;
        TypeTag rTag = rt < typeTags.length ? typeTags[rt] : TypeTag.UNKNOWN;

        if (lTag == TypeTag.STRING && rTag == TypeTag.STRING) return lt;
        if (lTag == TypeTag.FLOAT || rTag == TypeTag.FLOAT) {
            return _getOrCreateType(TypeTag.FLOAT, 0, 0, 0);
        }
        if (lTag == TypeTag.INT && rTag == TypeTag.INT) return lt;
        if (lTag == TypeTag.LIST && rTag == TypeTag.LIST) return lt;
        return 0;
    }

    function _getOrCreateType(TypeTag tag, uint256 inner, uint256 auxStart, uint256 auxCount) internal returns (uint256) {
        for (uint256 i = 0; i < typeTags.length; i++) {
            if (typeTags[i] == tag && innerTypes[i] == inner &&
                auxTypeStarts[i] == auxStart && auxTypeCounts[i] == auxCount) {
                return i;
            }
        }
        return _createType(tag, inner, auxStart, auxCount);
    }

    function _createType(TypeTag tag, uint256 inner, uint256 auxStart, uint256 auxCount) internal returns (uint256) {
        uint256 idx = typeTags.length;
        typeTags.push(tag);
        innerTypes.push(inner);
        auxTypeStarts.push(auxStart);
        auxTypeCounts.push(auxCount);
        return idx;
    }

    // ==================== Symbol Table ====================

    function _defineSymbol(string memory name, uint256 typeIdx) internal {
        uint256 scope = _currentScope();
        bytes32 key = keccak256(bytes(name));
        symTypes[scope][key] = typeIdx;
        symDefined[scope][key] = true;
        scopeSymbolCounts[scope]++;
    }

    function _checkUnboundLocal(string memory name, uint256 nodeIdx) internal {
        bytes32 key = keccak256(bytes(name));
        uint256 scope = _currentScope();
        // Walk up scopes to find if this variable is local to any enclosing function
        while (true) {
            if (scopeIsLocal[scope][key]) {
                // Variable is local to this scope — check if it's been assigned yet
                if (!scopeAssigned[scope][key]) {
                    _addErrorAt(string(abi.encodePacked("UnboundLocalError: '", name, "' referenced before assignment")), nodeIdx);
                }
                return;
            }
            if (scope == 0) break;
            scope = scopeParents[scope];
        }
    }

    function _lookupSymbol(string memory name) internal returns (uint256) {
        return _lookupSymbolAt(name, 0);
    }

    uint256 constant NOT_FOUND = type(uint256).max;

    function _lookupSymbolAt(string memory name, uint256 nodeIdx) internal returns (uint256) {
        bytes32 key = keccak256(bytes(name));
        uint256 scope = _currentScope();
        while (true) {
            if (symDefined[scope][key]) {
                return symTypes[scope][key];
            }
            if (scope == 0) break;
            scope = scopeParents[scope];
        }
        if (nodeIdx > 0) {
            _addErrorAt(string(abi.encodePacked("Undefined variable '", name, "'")), nodeIdx);
        } else {
            _addError(string(abi.encodePacked("Undefined variable '", name, "'")));
        }
        return NOT_FOUND;
    }

    function _currentScope() internal view returns (uint256) {
        return scopeStack[scopeStack.length - 1];
    }

    // ==================== Helpers ====================

    function _isBuiltin(string memory name) internal pure returns (bool) {
        bytes32 h = keccak256(bytes(name));
        return h == keccak256("print") || h == keccak256("len") ||
               h == keccak256("int") || h == keccak256("str") ||
               h == keccak256("bool") || h == keccak256("range") ||
               h == keccak256("abs") || h == keccak256("min") ||
               h == keccak256("max") || h == keccak256("type");
    }

    function _addError(string memory msg) internal {
        errors.push(msg);
    }

    function _addErrorAt(string memory msg, uint256 nodeIdx) internal {
        uint256 ln = parser.getLine(nodeIdx);
        uint256 col = parser.getColumn(nodeIdx);
        errors.push(string(abi.encodePacked("Line ", _toString(ln), ", Col ", _toString(col), ": ", msg)));
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

    function _strEq(string memory a, string memory b) internal pure returns (bool) {
        return keccak256(bytes(a)) == keccak256(bytes(b));
    }

    // ==================== Public Getters ====================

    function getNodeTypeResult(uint256 nodeIdx) public view returns (TypeTag) {
        uint256 ti = nodeTypes[nodeIdx];
        return ti < typeTags.length ? typeTags[ti] : TypeTag.UNKNOWN;
    }

    function getNodeTypeIndex(uint256 nodeIdx) public view returns (uint256) {
        return nodeTypes[nodeIdx];
    }

    function getTypeTag(uint256 typeIdx) public view returns (TypeTag) {
        return typeIdx < typeTags.length ? typeTags[typeIdx] : TypeTag.UNKNOWN;
    }

    function getInnerType(uint256 typeIdx) public view returns (uint256) {
        return typeIdx < innerTypes.length ? innerTypes[typeIdx] : 0;
    }

    function getErrorCount() public view returns (uint256) {
        return errors.length;
    }

    function getError(uint256 idx) public view returns (string memory) {
        return errors[idx];
    }
}
