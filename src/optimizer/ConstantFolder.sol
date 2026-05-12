// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {NodeType, BinaryOpType, UnaryOpType, CompOpType} from "../types/ASTNode.sol";
import {Parser} from "../phases/Parser.sol";

contract ConstantFolder {
    Parser private parser;

    function fold(Parser _parser) public {
        parser = _parser;
        _foldNode(0); // fold from program root
    }

    function _foldNode(uint256 idx) internal {
        NodeType nt = _nt(idx);

        if (nt == NodeType.PROGRAM) {
            _foldBlock(idx);
        } else if (nt == NodeType.FUNCTION_DEF) {
            // Don't fold inside function bodies (params may be used)
            // But fold the body for constant expressions that don't involve params
            if (_c2(idx) != 0) _foldBlock(_c2(idx));
        } else if (nt == NodeType.IF_STATEMENT) {
            _foldIfStmt(idx);
        } else if (nt == NodeType.WHILE_LOOP) {
            _foldExpr(_c1(idx));
            if (_c2(idx) != 0) _foldBlock(_c2(idx));
        } else if (nt == NodeType.FOR_LOOP) {
            if (_c3(idx) != 0) _foldBlock(_c3(idx));
        } else if (nt == NodeType.ASSIGN) {
            _foldExpr(_c2(idx));
        } else if (nt == NodeType.AUG_ASSIGN) {
            _foldExpr(_c2(idx));
        } else if (nt == NodeType.RETURN_STMT) {
            if (_c1(idx) != 0) _foldExpr(_c1(idx));
        } else if (nt == NodeType.EXPR_STMT) {
            _foldExpr(_c1(idx));
        } else if (nt == NodeType.CLASS_DEF) {
            if (_c2(idx) != 0) _foldBlock(_c2(idx));
        }
    }

    function _foldBlock(uint256 nodeIdx) internal {
        uint256 start = _ai(nodeIdx);
        uint256 count = _ac(nodeIdx);
        for (uint256 i = 0; i < count; i++) {
            _foldNode(_aux(start + i));
        }
    }

    function _foldIfStmt(uint256 idx) internal {
        // Fold the condition first
        _foldExpr(_c1(idx));

        // Check if condition is a constant
        NodeType condType = _nt(_c1(idx));

        if (condType == NodeType.BOOL_LITERAL && _iv(_c1(idx)) == 0) {
            // if False: → dead code, remove body
            // Keep else body if present
            if (_c3(idx) != 0) {
                // Replace if statement with else body by making it a pass
                // Actually, we can't easily replace the if statement node itself.
                // Instead, set auxCount=0 to remove elif branches, and set child2=0 to remove if body.
                // The else body (child3) remains — but the code generator won't execute it
                // because the if statement is now effectively: if False: pass else: <body>
                // We need a different approach: fold the condition to 0, code generator will handle it.
                // Actually the code generator already handles this: if condition is false, it jumps over body.
                // The issue is that we want to eliminate the dead code entirely.
                // For dead code elimination: set child2=0 (no if body), keep child3 (else body).
                // But the code generator checks child2!=0 before generating body.
                // So setting child2=0 effectively removes the if body.
                // The else body will still be generated because _genIfStmt checks _c3(nodeIdx)!=0.
                // But wait — if condition is always false, the else body always executes.
                // We can't just remove the if and keep the else body inline because
                // the else body is only accessible through the if statement node.
                // Let's just set child2=0 so the if body is dead, else body still executes.
                parser.setChild2(idx, 0);
                // Also fold the else body
                _foldBlock(_c3(idx));
            } else {
                // No else: entire if is dead code
                // Set auxCount=0 and child2=0
                parser.setChild2(idx, 0);
                parser.setAuxCount(idx, 0);
            }
        } else if (condType == NodeType.BOOL_LITERAL && _iv(_c1(idx)) == 1) {
            // if True: → always execute body, skip else
            // Fold the body
            if (_c2(idx) != 0) _foldBlock(_c2(idx));
            // Remove else body by setting child3=0
            parser.setChild3(idx, 0);
            // Remove elif branches
            parser.setAuxCount(idx, 0);
        } else {
            // Condition not constant — fold body normally
            if (_c2(idx) != 0) _foldBlock(_c2(idx));

            // Fold elif branches
            uint256 elifStart = _ai(idx);
            uint256 elifCount = _ac(idx);
            for (uint256 i = 0; i < elifCount; i++) {
                uint256 elifIdx = _ea(elifStart + i);
                _foldExpr(_c1(elifIdx));
                if (_c2(elifIdx) != 0) _foldBlock(_c2(elifIdx));
            }

            if (_c3(idx) != 0) _foldBlock(_c3(idx));
        }
    }

    function _foldExpr(uint256 idx) internal {
        NodeType nt = _nt(idx);

        if (nt == NodeType.BINARY_OP) {
            _foldBinaryOp(idx);
        } else if (nt == NodeType.UNARY_OP) {
            _foldUnaryOp(idx);
        } else if (nt == NodeType.COMPARISON) {
            _foldComparison(idx);
        } else if (nt == NodeType.BOOL_AND) {
            _foldBoolAnd(idx);
        } else if (nt == NodeType.BOOL_OR) {
            _foldBoolOr(idx);
        } else if (nt == NodeType.BOOL_NOT) {
            _foldBoolNot(idx);
        } else if (nt == NodeType.FUNC_CALL) {
            // Don't fold function calls (may have side effects)
            uint256 argStart = _ai(idx);
            uint256 argCount = _ac(idx);
            for (uint256 i = 0; i < argCount; i++) {
                _foldExpr(_ea(argStart + i));
            }
        } else if (nt == NodeType.LIST_LITERAL) {
            uint256 elemStart = _ai(idx);
            uint256 elemCount = _ac(idx);
            for (uint256 i = 0; i < elemCount; i++) {
                _foldExpr(_ea(elemStart + i));
            }
        } else if (nt == NodeType.INDEX_ACCESS) {
            _foldExpr(_c1(idx));
            _foldExpr(_c2(idx));
        }
        // Literals and IDENTIFIER_REF: nothing to fold
    }

    function _foldBinaryOp(uint256 idx) internal {
        // First fold children
        _foldExpr(_c1(idx));
        _foldExpr(_c2(idx));

        // Check if both children are INT_LITERAL
        if (_nt(_c1(idx)) == NodeType.INT_LITERAL && _nt(_c2(idx)) == NodeType.INT_LITERAL) {
            uint256 left = _iv(_c1(idx));
            uint256 right = _iv(_c2(idx));
            BinaryOpType op = BinaryOpType(_iv(idx));
            uint256 result;

            if (op == BinaryOpType.ADD) {
                result = left + right;
            } else if (op == BinaryOpType.SUB) {
                result = left - right;
            } else if (op == BinaryOpType.MUL) {
                result = left * right;
            } else if (op == BinaryOpType.DIV || op == BinaryOpType.FDIV) {
                if (right == 0) return; // don't fold div by zero
                result = left / right;
            } else if (op == BinaryOpType.MOD) {
                if (right == 0) return;
                result = left % right;
            } else if (op == BinaryOpType.POW) {
                result = _pow(left, right);
            } else {
                return;
            }

            // Replace this node with INT_LITERAL
            parser.setNodeType(idx, NodeType.INT_LITERAL);
            parser.setIntValue(idx, result);
            parser.setChild1(idx, 0);
            parser.setChild2(idx, 0);
        }
    }

    function _foldUnaryOp(uint256 idx) internal {
        _foldExpr(_c1(idx));

        if (UnaryOpType(_iv(idx)) == UnaryOpType.NEG && _nt(_c1(idx)) == NodeType.INT_LITERAL) {
            uint256 val = _iv(_c1(idx));
            // Negate: two's complement
            uint256 negated = type(uint256).max - val + 1;
            parser.setNodeType(idx, NodeType.INT_LITERAL);
            parser.setIntValue(idx, negated);
            parser.setChild1(idx, 0);
        }
    }

    function _foldComparison(uint256 idx) internal {
        _foldExpr(_c1(idx));
        _foldExpr(_c2(idx));

        if (_nt(_c1(idx)) == NodeType.INT_LITERAL && _nt(_c2(idx)) == NodeType.INT_LITERAL) {
            uint256 left = _iv(_c1(idx));
            uint256 right = _iv(_c2(idx));
            CompOpType op = CompOpType(_iv(idx));
            uint256 result;

            if (op == CompOpType.EQ) result = left == right ? 1 : 0;
            else if (op == CompOpType.NEQ) result = left != right ? 1 : 0;
            else if (op == CompOpType.LT) result = left < right ? 1 : 0;
            else if (op == CompOpType.GT) result = left > right ? 1 : 0;
            else if (op == CompOpType.LTE) result = left <= right ? 1 : 0;
            else result = left >= right ? 1 : 0;

            parser.setNodeType(idx, NodeType.BOOL_LITERAL);
            parser.setIntValue(idx, result);
            parser.setChild1(idx, 0);
            parser.setChild2(idx, 0);
        }
    }

    function _foldBoolAnd(uint256 idx) internal {
        _foldExpr(_c1(idx));
        _foldExpr(_c2(idx));

        if (_nt(_c1(idx)) == NodeType.BOOL_LITERAL && _nt(_c2(idx)) == NodeType.BOOL_LITERAL) {
            uint256 result = (_iv(_c1(idx)) != 0 && _iv(_c2(idx)) != 0) ? 1 : 0;
            parser.setNodeType(idx, NodeType.BOOL_LITERAL);
            parser.setIntValue(idx, result);
            parser.setChild1(idx, 0);
            parser.setChild2(idx, 0);
        }
    }

    function _foldBoolOr(uint256 idx) internal {
        _foldExpr(_c1(idx));
        _foldExpr(_c2(idx));

        if (_nt(_c1(idx)) == NodeType.BOOL_LITERAL && _nt(_c2(idx)) == NodeType.BOOL_LITERAL) {
            uint256 result = (_iv(_c1(idx)) != 0 || _iv(_c2(idx)) != 0) ? 1 : 0;
            parser.setNodeType(idx, NodeType.BOOL_LITERAL);
            parser.setIntValue(idx, result);
            parser.setChild1(idx, 0);
            parser.setChild2(idx, 0);
        }
    }

    function _foldBoolNot(uint256 idx) internal {
        _foldExpr(_c1(idx));

        if (_nt(_c1(idx)) == NodeType.BOOL_LITERAL) {
            uint256 result = _iv(_c1(idx)) == 0 ? 1 : 0;
            parser.setNodeType(idx, NodeType.BOOL_LITERAL);
            parser.setIntValue(idx, result);
            parser.setChild1(idx, 0);
        }
    }

    // ==================== Helpers ====================

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

    function _pow(uint256 base, uint256 exp) internal pure returns (uint256) {
        uint256 result = 1;
        while (exp > 0) {
            if (exp & 1 == 1) result *= base;
            base *= base;
            exp >>= 1;
        }
        return result;
    }
}
