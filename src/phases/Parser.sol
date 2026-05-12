// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Token, TokenType} from "../types/Token.sol";
import {ASTNode, NodeType, BinaryOpType, UnaryOpType, CompOpType, AugAssignOp} from "../types/ASTNode.sol";
import {Lexer} from "./Lexer.sol";

contract Parser {
    Lexer private lexer;
    uint256 private tokenCount;
    uint256 private p;

    // AST building — main arrays
    NodeType[] private nts;
    uint256[] private c1s;
    uint256[] private c2s;
    uint256[] private c3s;
    uint256[] private ais;
    uint256[] private acs;
    uint256[] private ivs;
    string[] private svs;
    uint256[] private nls;
    uint256[] private ncs;
    uint256[] private aux;

    // Expression auxiliary data (function call args, list elements)
    uint256[] private exprAux;

    // Body statement stack for nested suites
    // Each level is a dynamic array of statement node indices.
    // bodyStackIdx[level] = index into bodyStack where that level's array lives.
    // bodyNodeIdx[level] = the AST node index that owns this body.
    // _bodyNesting is a stack of bodyStack indices tracking current nesting depth.
    uint256[][] private bodyStack;
    uint256[] private bodyStackIdx;
    uint256[] private bodyNodeIdx;
    uint256[] private _bodyNesting;

    function parse(Lexer _lexer) public returns (ASTNode[] memory) {
        lexer = _lexer;
        tokenCount = _lexer.getTokenCount();
        p = 0;

        _emit(NodeType.PROGRAM, 0, 0, 0, 0, 0, 0, "", 0, 0);

        uint256 stmtStart = aux.length;
        uint256 stmtCount = 0;

        while (!_end()) {
            _skipNL();
            if (_end()) break;
            aux.push(_stmt());
            stmtCount++;
            _expectNL();
        }

        // Merge bodyStack levels into aux and fix up node references
        for (uint256 i = 0; i < bodyStackIdx.length; i++) {
            uint256 bi = bodyStackIdx[i];
            uint256 nodeIdx = bodyNodeIdx[i];
            uint256 start = aux.length;
            uint256 cnt = bodyStack[bi].length;
            for (uint256 j = 0; j < cnt; j++) {
                aux.push(bodyStack[bi][j]);
            }
            ais[nodeIdx] = start;
            acs[nodeIdx] = cnt;
        }

        // Set PROGRAM node's aux AFTER all merges so indices are correct
        ais[0] = stmtStart;
        acs[0] = stmtCount;

        return _build();
    }

    function _stmt() internal returns (uint256) {
        TokenType t = _cur();
        if (t == TokenType.KW_DEF) return _funcDef();
        if (t == TokenType.KW_IF) return _ifStmt();
        if (t == TokenType.KW_WHILE) return _whileLoop();
        if (t == TokenType.KW_FOR) return _forLoop();
        if (t == TokenType.KW_RETURN) return _retStmt();
        if (t == TokenType.KW_PASS) return _passStmt();
        if (t == TokenType.KW_BREAK) return _breakStmt();
        if (t == TokenType.KW_CONTINUE) return _contStmt();
        if (t == TokenType.KW_CLASS) return _classDef();
        if (t == TokenType.KW_IMPORT) return _importStmt();
        if (t == TokenType.KW_FROM) return _fromImportStmt();
        if (t == TokenType.KW_TRY) return _tryStmt();
        if (t == TokenType.KW_RAISE) return _raiseStmt();
        return _assignOrExpr();
    }

    function _funcDef() internal returns (uint256) {
        uint256 ln = _ln(); uint256 col = _col();
        _adv();
        string memory name = _lex();
        _adv();
        _exp(TokenType.LPAREN);

        uint256 pc = 0;
        while (_cur() != TokenType.RPAREN && !_end()) {
            string memory param = _lex();
            _exp(TokenType.IDENTIFIER);
            exprAux.push(_emit(NodeType.IDENTIFIER_REF, 0, 0, 0, 0, 0, 0, param, _ln(), _col()));
            pc++;
            if (_cur() == TokenType.COMMA) _adv();
        }
        uint256 ps = exprAux.length - pc;
        _exp(TokenType.RPAREN);
        _skipNL();
        _exp(TokenType.COLON);

        uint256 lvl = _bodyPush();
        uint256 body = _suite();
        _bodyPopTo(lvl, body);
        return _emit(NodeType.FUNCTION_DEF, 0, body, 0, ps, pc, 0, name, ln, col);
    }

    function _ifStmt() internal returns (uint256) {
        uint256 ln = _ln(); uint256 col = _col();
        _adv();
        uint256 cond = _expr();
        _skipNL();
        _exp(TokenType.COLON);
        uint256 lvl = _bodyPush();
        uint256 body = _suite();
        _bodyPopTo(lvl, body);

        uint256 node = _emit(NodeType.IF_STATEMENT, cond, body, 0, 0, 0, 0, "", ln, col);

        uint256 ec = 0;
        while (_cur() == TokenType.KW_ELIF) {
            exprAux.push(_elifBranch());
            ec++;
        }
        uint256 es = exprAux.length - ec;

        uint256 eb = 0;
        if (_cur() == TokenType.KW_ELSE) {
            _adv();
            _skipNL();
            _exp(TokenType.COLON);
            uint256 elvl = _bodyPush();
            eb = _suite();
            _bodyPopTo(elvl, eb);
        }

        c3s[node] = eb;
        ais[node] = es;
        acs[node] = ec;
        return node;
    }

    function _elifBranch() internal returns (uint256) {
        uint256 ln = _ln(); uint256 col = _col();
        _adv();
        uint256 cond = _expr();
        _skipNL();
        _exp(TokenType.COLON);
        uint256 lvl = _bodyPush();
        uint256 body = _suite();
        _bodyPopTo(lvl, body);
        return _emit(NodeType.ELIF_BRANCH, cond, body, 0, 0, 0, 0, "", ln, col);
    }

    function _whileLoop() internal returns (uint256) {
        uint256 ln = _ln(); uint256 col = _col();
        _adv();
        uint256 cond = _expr();
        _skipNL();
        _exp(TokenType.COLON);
        uint256 lvl = _bodyPush();
        uint256 body = _suite();
        _bodyPopTo(lvl, body);
        return _emit(NodeType.WHILE_LOOP, cond, body, 0, 0, 0, 0, "", ln, col);
    }

    function _forLoop() internal returns (uint256) {
        uint256 ln = _ln(); uint256 col = _col();
        _adv();
        string memory varName = _lex();
        _exp(TokenType.IDENTIFIER);
        _skipNL();
        _exp(TokenType.KW_IN);
        uint256 iter = _expr();
        _skipNL();
        _exp(TokenType.COLON);
        uint256 lvl = _bodyPush();
        uint256 body = _suite();
        _bodyPopTo(lvl, body);
        uint256 varNode = _emit(NodeType.IDENTIFIER_REF, 0, 0, 0, 0, 0, 0, varName, ln, col);
        return _emit(NodeType.FOR_LOOP, varNode, iter, body, 0, 0, 0, "", ln, col);
    }

    function _retStmt() internal returns (uint256) {
        uint256 ln = _ln(); uint256 col = _col();
        _adv();
        uint256 val = 0;
        if (_cur() != TokenType.NEWLINE && _cur() != TokenType.EOF) val = _expr();
        return _emit(NodeType.RETURN_STMT, val, 0, 0, 0, 0, 0, "", ln, col);
    }

    function _passStmt() internal returns (uint256) {
        uint256 ln = _ln(); uint256 col = _col();
        _adv();
        return _emit(NodeType.PASS_STMT, 0, 0, 0, 0, 0, 0, "", ln, col);
    }

    function _breakStmt() internal returns (uint256) {
        uint256 ln = _ln(); uint256 col = _col();
        _adv();
        return _emit(NodeType.BREAK_STMT, 0, 0, 0, 0, 0, 0, "", ln, col);
    }

    function _contStmt() internal returns (uint256) {
        uint256 ln = _ln(); uint256 col = _col();
        _adv();
        return _emit(NodeType.CONTINUE_STMT, 0, 0, 0, 0, 0, 0, "", ln, col);
    }

    function _classDef() internal returns (uint256) {
        uint256 ln = _ln(); uint256 col = _col();
        _adv();
        string memory name = _lex();
        _exp(TokenType.IDENTIFIER);

        uint256 parent = 0;
        if (_cur() == TokenType.LPAREN) {
            _adv();
            if (_cur() == TokenType.IDENTIFIER) {
                string memory pn = _lex();
                parent = _emit(NodeType.IDENTIFIER_REF, 0, 0, 0, 0, 0, 0, pn, _ln(), _col());
                _adv();
            }
            _exp(TokenType.RPAREN);
        }

        _skipNL();
        _exp(TokenType.COLON);
        uint256 lvl = _bodyPush();
        uint256 body = _suite();
        _bodyPopTo(lvl, body);
        return _emit(NodeType.CLASS_DEF, parent, body, 0, 0, 0, 0, name, ln, col);
    }

    function _importStmt() internal returns (uint256) {
        // import module_name
        uint256 ln = _ln(); uint256 col = _col();
        _adv(); // skip 'import'
        string memory moduleName = _lex();
        _exp(TokenType.IDENTIFIER);
        // IMPORT_STMT: strValue = module name, no children
        return _emit(NodeType.IMPORT_STMT, 0, 0, 0, 0, 0, 0, moduleName, ln, col);
    }

    function _fromImportStmt() internal returns (uint256) {
        // from module_name import name1 [, name2, ...]
        uint256 ln = _ln(); uint256 col = _col();
        _adv(); // skip 'from'
        string memory moduleName = _lex();
        _exp(TokenType.IDENTIFIER);
        _exp(TokenType.KW_IMPORT);

        uint256 nc = 0;
        while (_cur() == TokenType.IDENTIFIER && !_end()) {
            string memory name = _lex();
            _adv();
            exprAux.push(_emit(NodeType.IDENTIFIER_REF, 0, 0, 0, 0, 0, 0, name, _ln(), _col()));
            nc++;
            if (_cur() == TokenType.COMMA) _adv();
        }
        uint256 ns = exprAux.length - nc;

        // IMPORT_STMT: strValue = module name, auxIndex = names start, auxCount = name count
        return _emit(NodeType.IMPORT_STMT, 0, 0, 0, ns, nc, 0, moduleName, ln, col);
    }

    function _tryStmt() internal returns (uint256) {
        uint256 ln = _ln(); uint256 col = _col();
        _adv(); // skip 'try'
        _skipNL();
        _exp(TokenType.COLON);

        // Try body
        uint256 tryLvl = _bodyPush();
        uint256 tryBody = _suite();
        _bodyPopTo(tryLvl, tryBody);

        // Except branches
        uint256 exceptStart = exprAux.length;
        uint256 exceptCount = 0;
        while (_cur() == TokenType.KW_EXCEPT) {
            _adv(); // skip 'except'
            uint256 eln = _ln(); uint256 ecol = _col();

            // Optional exception type
            uint256 excType = 0;
            if (_cur() == TokenType.IDENTIFIER) {
                string memory typeName = _lex();
                _adv();
                excType = _emit(NodeType.IDENTIFIER_REF, 0, 0, 0, 0, 0, 0, typeName, _ln(), _col());
            }

            _skipNL();
            _exp(TokenType.COLON);

            uint256 excLvl = _bodyPush();
            uint256 excBody = _suite();
            _bodyPopTo(excLvl, excBody);

            exprAux.push(_emit(NodeType.EXCEPT_BRANCH, excType, excBody, 0, 0, 0, 0, "", eln, ecol));
            exceptCount++;
        }

        // Finally branch
        uint256 finallyBranch = 0;
        if (_cur() == TokenType.KW_FINALLY) {
            _adv(); // skip 'finally'
            uint256 fln = _ln(); uint256 fcol = _col();
            _skipNL();
            _exp(TokenType.COLON);
            uint256 finLvl = _bodyPush();
            uint256 finBody = _suite();
            _bodyPopTo(finLvl, finBody);
            finallyBranch = _emit(NodeType.FINALLY_BRANCH, finBody, 0, 0, 0, 0, 0, "", fln, fcol);
        }

        return _emit(NodeType.TRY_STMT, tryBody, finallyBranch, 0, exceptStart, exceptCount, 0, "", ln, col);
    }

    function _raiseStmt() internal returns (uint256) {
        uint256 ln = _ln(); uint256 col = _col();
        _adv(); // skip 'raise'

        uint256 excExpr = 0;
        if (_cur() != TokenType.NEWLINE && _cur() != TokenType.EOF) {
            excExpr = _expr();
        }

        return _emit(NodeType.RAISE_STMT, excExpr, 0, 0, 0, 0, 0, "", ln, col);
    }

    function _assignOrExpr() internal returns (uint256) {
        uint256 ln = _ln(); uint256 col = _col();
        uint256 lhs = _expr();

        TokenType t = _cur();
        if (t == TokenType.OP_ASSIGN) {
            _adv();
            return _emit(NodeType.ASSIGN, lhs, _expr(), 0, 0, 0, 0, "", ln, col);
        }
        if (_isAugAssign(t)) {
            _adv();
            return _emit(NodeType.AUG_ASSIGN, lhs, _expr(), 0, 0, 0, uint256(_augOp(t)), "", ln, col);
        }
        return _emit(NodeType.EXPR_STMT, lhs, 0, 0, 0, 0, 0, "", ln, col);
    }

    function _isAugAssign(TokenType t) internal pure returns (bool) {
        return t == TokenType.OP_PLUS_ASSIGN || t == TokenType.OP_MINUS_ASSIGN ||
               t == TokenType.OP_STAR_ASSIGN || t == TokenType.OP_SLASH_ASSIGN;
    }

    function _augOp(TokenType t) internal pure returns (AugAssignOp) {
        if (t == TokenType.OP_PLUS_ASSIGN) return AugAssignOp.PLUS_ASSIGN;
        if (t == TokenType.OP_MINUS_ASSIGN) return AugAssignOp.MINUS_ASSIGN;
        if (t == TokenType.OP_STAR_ASSIGN) return AugAssignOp.STAR_ASSIGN;
        return AugAssignOp.SLASH_ASSIGN;
    }

    // ==================== Suite (indented blocks) ====================

    function _suite() internal returns (uint256) {
        _skipNL();
        if (_cur() == TokenType.INDENT) {
            _adv();
            while (_cur() != TokenType.DEDENT && !_end()) {
                _skipNL();
                if (_cur() == TokenType.DEDENT || _end()) break;
                _bodyCur().push(_stmt());
                _expectNL();
            }
            if (_cur() == TokenType.DEDENT) _adv();
            // Return placeholder — caller fixes up via _bodyPopTo
            return _emit(NodeType.PROGRAM, 0, 0, 0, 0, 0, 0, "", 0, 0);
        }
        return _stmt();
    }

    // ==================== Body stack helpers ====================

    function _bodyPush() internal returns (uint256) {
        uint256 idx = bodyStack.length;
        bodyStack.push();       // new empty dynamic array
        bodyStackIdx.push(idx); // record mapping: level -> bodyStack index
        bodyNodeIdx.push(0);    // placeholder, filled by _bodyPopTo
        _bodyNesting.push(idx); // track current nesting level
        return bodyStackIdx.length - 1; // return level number
    }

    function _bodyPopTo(uint256 lvl, uint256 nodeIdx) internal {
        bodyNodeIdx[lvl] = nodeIdx;
        _bodyNesting.pop(); // restore parent nesting level
    }

    function _bodyCur() internal view returns (uint256[] storage) {
        return bodyStack[_bodyNesting[_bodyNesting.length - 1]];
    }

    // ==================== Expression parsing ====================

    function _expr() internal returns (uint256) { return _boolOr(); }

    function _boolOr() internal returns (uint256) {
        uint256 l = _boolAnd();
        while (_cur() == TokenType.KW_OR) {
            uint256 ln = _ln(); uint256 col = _col();
            _adv();
            l = _emit(NodeType.BOOL_OR, l, _boolAnd(), 0, 0, 0, 0, "", ln, col);
        }
        return l;
    }

    function _boolAnd() internal returns (uint256) {
        uint256 l = _notExpr();
        while (_cur() == TokenType.KW_AND) {
            uint256 ln = _ln(); uint256 col = _col();
            _adv();
            l = _emit(NodeType.BOOL_AND, l, _notExpr(), 0, 0, 0, 0, "", ln, col);
        }
        return l;
    }

    function _notExpr() internal returns (uint256) {
        if (_cur() == TokenType.KW_NOT) {
            uint256 ln = _ln(); uint256 col = _col();
            _adv();
            return _emit(NodeType.BOOL_NOT, _notExpr(), 0, 0, 0, 0, 0, "", ln, col);
        }
        return _cmp();
    }

    function _cmp() internal returns (uint256) {
        uint256 l = _add();
        if (_isCmp(_cur())) {
            uint256 ln = _ln(); uint256 col = _col();
            CompOpType op = _cmpOp(_cur());
            _adv();
            return _emit(NodeType.COMPARISON, l, _add(), 0, 0, 0, uint256(op), "", ln, col);
        }
        return l;
    }

    function _isCmp(TokenType t) internal pure returns (bool) {
        return t == TokenType.OP_EQ || t == TokenType.OP_NEQ || t == TokenType.OP_LT ||
               t == TokenType.OP_GT || t == TokenType.OP_LTE || t == TokenType.OP_GTE;
    }

    function _cmpOp(TokenType t) internal pure returns (CompOpType) {
        if (t == TokenType.OP_EQ) return CompOpType.EQ;
        if (t == TokenType.OP_NEQ) return CompOpType.NEQ;
        if (t == TokenType.OP_LT) return CompOpType.LT;
        if (t == TokenType.OP_GT) return CompOpType.GT;
        if (t == TokenType.OP_LTE) return CompOpType.LTE;
        return CompOpType.GTE;
    }

    function _add() internal returns (uint256) {
        uint256 l = _mul();
        while (_cur() == TokenType.OP_PLUS || _cur() == TokenType.OP_MINUS) {
            uint256 ln = _ln(); uint256 col = _col();
            BinaryOpType op = _cur() == TokenType.OP_PLUS ? BinaryOpType.ADD : BinaryOpType.SUB;
            _adv();
            l = _emit(NodeType.BINARY_OP, l, _mul(), 0, 0, 0, uint256(op), "", ln, col);
        }
        return l;
    }

    function _mul() internal returns (uint256) {
        uint256 l = _pow();
        while (_cur() == TokenType.OP_STAR || _cur() == TokenType.OP_SLASH ||
               _cur() == TokenType.OP_DSLASH || _cur() == TokenType.OP_PERCENT) {
            uint256 ln = _ln(); uint256 col = _col();
            BinaryOpType op;
            if (_cur() == TokenType.OP_STAR) op = BinaryOpType.MUL;
            else if (_cur() == TokenType.OP_SLASH) op = BinaryOpType.DIV;
            else if (_cur() == TokenType.OP_DSLASH) op = BinaryOpType.FDIV;
            else op = BinaryOpType.MOD;
            _adv();
            l = _emit(NodeType.BINARY_OP, l, _pow(), 0, 0, 0, uint256(op), "", ln, col);
        }
        return l;
    }

    function _pow() internal returns (uint256) {
        uint256 l = _unary();
        if (_cur() == TokenType.OP_DSTAR) {
            uint256 ln = _ln(); uint256 col = _col();
            _adv();
            l = _emit(NodeType.BINARY_OP, l, _pow(), 0, 0, 0, uint256(BinaryOpType.POW), "", ln, col);
        }
        return l;
    }

    function _unary() internal returns (uint256) {
        if (_cur() == TokenType.OP_MINUS) {
            uint256 ln = _ln(); uint256 col = _col();
            _adv();
            return _emit(NodeType.UNARY_OP, _unary(), 0, 0, 0, 0, uint256(UnaryOpType.NEG), "", ln, col);
        }
        return _atom();
    }

    function _atom() internal returns (uint256) {
        uint256 ln = _ln(); uint256 col = _col();
        TokenType t = _cur();

        if (t == TokenType.INTEGER) { uint256 v = _iv(); _adv(); return _emit(NodeType.INT_LITERAL, 0, 0, 0, 0, 0, v, "", ln, col); }
        if (t == TokenType.FLOAT) { uint256 v = _iv(); _adv(); return _emit(NodeType.FLOAT_LITERAL, 0, 0, 0, 0, 0, v, "", ln, col); }
        if (t == TokenType.STRING) {
            string memory raw = _lex();
            _adv();
            // Strip surrounding quotes from the lexeme
            bytes memory rawBytes = bytes(raw);
            string memory v = "";
            if (rawBytes.length >= 2) {
                bytes memory stripped = new bytes(rawBytes.length - 2);
                for (uint256 i = 1; i < rawBytes.length - 1; i++) {
                    stripped[i - 1] = rawBytes[i];
                }
                v = string(stripped);
            }
            return _emit(NodeType.STRING_LITERAL, 0, 0, 0, 0, 0, 0, v, ln, col);
        }
        if (t == TokenType.BOOL_TRUE) { _adv(); return _emit(NodeType.BOOL_LITERAL, 0, 0, 0, 0, 0, 1, "", ln, col); }
        if (t == TokenType.BOOL_FALSE) { _adv(); return _emit(NodeType.BOOL_LITERAL, 0, 0, 0, 0, 0, 0, "", ln, col); }
        if (t == TokenType.NONE_VAL) { _adv(); return _emit(NodeType.NONE_LITERAL, 0, 0, 0, 0, 0, 0, "", ln, col); }
        if (t == TokenType.LPAREN) { _adv(); uint256 e = _expr(); _exp(TokenType.RPAREN); return e; }
        if (t == TokenType.LBRACKET) { return _listLit(); }
        if (t == TokenType.LBRACE) { return _dictOrSetLit(); }

        if (t == TokenType.IDENTIFIER || (t >= TokenType.KW_DEF && t <= TokenType.KW_PRINT)) {
            string memory name = _lex();
            _adv();
            if (_cur() == TokenType.LPAREN) return _funcCall(name, ln, col);
            if (_cur() == TokenType.LBRACKET) return _idxAccess(_emit(NodeType.IDENTIFIER_REF, 0, 0, 0, 0, 0, 0, name, ln, col));
            if (_cur() == TokenType.DOT) {
                uint256 objNode = _emit(NodeType.IDENTIFIER_REF, 0, 0, 0, 0, 0, 0, name, ln, col);
                return _dotAccess(objNode);
            }
            return _emit(NodeType.IDENTIFIER_REF, 0, 0, 0, 0, 0, 0, name, ln, col);
        }

        _adv();
        return _emit(NodeType.NONE_LITERAL, 0, 0, 0, 0, 0, 0, "", ln, col);
    }

    function _funcCall(string memory name, uint256 ln, uint256 col) internal returns (uint256) {
        _exp(TokenType.LPAREN);
        uint256 argCnt = 0;
        while (_cur() != TokenType.RPAREN && !_end()) {
            exprAux.push(_expr());
            argCnt++;
            if (_cur() == TokenType.COMMA) _adv();
        }
        _exp(TokenType.RPAREN);
        // Compute start after all pushes to handle nested calls correctly
        uint256 argStart = exprAux.length - argCnt;
        uint256 node = _emit(NodeType.FUNC_CALL, 0, 0, 0, argStart, argCnt, 0, name, ln, col);
        if (_cur() == TokenType.LBRACKET) return _idxAccess(node);
        return node;
    }

    function _methodCall(string memory objName, uint256 ln, uint256 col) internal returns (uint256) {
        // obj is already parsed as IDENTIFIER_REF — create it and push as first arg
        uint256 objNode = _emit(NodeType.IDENTIFIER_REF, 0, 0, 0, 0, 0, 0, objName, ln, col);
        exprAux.push(objNode);
        uint256 argCnt = 1; // object is first argument

        _exp(TokenType.DOT); // consume the dot
        uint256 methodLn = _ln(); uint256 methodCol = _col();
        string memory methodName = _lex();
        _adv();

        _exp(TokenType.LPAREN);
        while (_cur() != TokenType.RPAREN && !_end()) {
            exprAux.push(_expr());
            argCnt++;
            if (_cur() == TokenType.COMMA) _adv();
        }
        _exp(TokenType.RPAREN);
        uint256 argStart = exprAux.length - argCnt;
        uint256 node = _emit(NodeType.FUNC_CALL, 0, 0, 0, argStart, argCnt, 0, methodName, methodLn, methodCol);
        if (_cur() == TokenType.LBRACKET) return _idxAccess(node);
        return node;
    }

    function _dotAccess(uint256 objNode) internal returns (uint256) {
        // obj is already parsed — handle .attr or .method(args)
        _exp(TokenType.DOT); // consume the dot
        uint256 attrLn = _ln(); uint256 attrCol = _col();
        string memory attrName = _lex();
        _adv();

        uint256 result;
        if (_cur() == TokenType.LPAREN) {
            // Method call: obj.method(args)
            _exp(TokenType.LPAREN);
            uint256 argCnt = 0;
            while (_cur() != TokenType.RPAREN && !_end()) {
                exprAux.push(_expr());
                argCnt++;
                if (_cur() == TokenType.COMMA) _adv();
            }
            _exp(TokenType.RPAREN);
            uint256 argStart = exprAux.length - argCnt;
            result = _emit(NodeType.METHOD_CALL, objNode, 0, 0, argStart, argCnt, 0, attrName, attrLn, attrCol);
        } else {
            // Attribute access: obj.attr
            result = _emit(NodeType.ATTR_ACCESS, objNode, 0, 0, 0, 0, 0, attrName, attrLn, attrCol);
        }

        // Handle chaining: obj.attr.nested or obj.method().attr
        if (_cur() == TokenType.DOT) {
            return _dotAccess(result);
        }
        if (_cur() == TokenType.LBRACKET) {
            return _idxAccess(result);
        }
        return result;
    }

    function _listLit() internal returns (uint256) {
        uint256 ln = _ln(); uint256 col = _col();
        _exp(TokenType.LBRACKET);
        uint256 ec = 0;
        while (_cur() != TokenType.RBRACKET && !_end()) {
            exprAux.push(_expr());
            ec++;
            if (_cur() == TokenType.COMMA) _adv();
        }
        _exp(TokenType.RBRACKET);
        uint256 es = exprAux.length - ec;
        return _emit(NodeType.LIST_LITERAL, 0, 0, 0, es, ec, 0, "", ln, col);
    }

    function _idxAccess(uint256 target) internal returns (uint256) {
        uint256 ln = _ln(); uint256 col = _col();
        while (_cur() == TokenType.LBRACKET) {
            _adv();
            // Check for slice syntax: a[i:j] or a[:j] or a[i:] or a[:]
            if (_cur() == TokenType.COLON) {
                // a[:...] — start is default (0)
                _adv(); // consume colon
                if (_cur() == TokenType.RBRACKET) {
                    // a[:] — both default
                    target = _emit(NodeType.SLICE_ACCESS, target, 0, 0, 0, 0, 0, "", ln, col);
                } else {
                    // a[:j]
                    uint256 end = _expr();
                    target = _emit(NodeType.SLICE_ACCESS, target, 0, end, 0, 0, 0, "", ln, col);
                }
                _exp(TokenType.RBRACKET);
            } else {
                uint256 idx = _expr();
                if (_cur() == TokenType.COLON) {
                    // a[i:j] or a[i:]
                    _adv(); // consume colon
                    if (_cur() == TokenType.RBRACKET) {
                        // a[i:] — end is default (0)
                        target = _emit(NodeType.SLICE_ACCESS, target, idx, 0, 0, 0, 0, "", ln, col);
                    } else {
                        // a[i:j]
                        uint256 end = _expr();
                        target = _emit(NodeType.SLICE_ACCESS, target, idx, end, 0, 0, 0, "", ln, col);
                    }
                    _exp(TokenType.RBRACKET);
                } else {
                    // Normal index access: a[i]
                    _exp(TokenType.RBRACKET);
                    target = _emit(NodeType.INDEX_ACCESS, target, idx, 0, 0, 0, 0, "", ln, col);
                }
            }
        }
        return target;
    }

    function _dictOrSetLit() internal returns (uint256) {
        uint256 ln = _ln(); uint256 col = _col();
        _exp(TokenType.LBRACE);

        // Empty dict: {}
        if (_cur() == TokenType.RBRACE) {
            _adv();
            return _emit(NodeType.DICT_LITERAL, 0, 0, 0, 0, 0, 0, "", ln, col);
        }

        // Parse first expression
        uint256 first = _expr();

        // Disambiguate: if next is COLON → dict, otherwise → set
        if (_cur() == TokenType.COLON) {
            // Dict literal
            _adv(); // skip colon
            uint256 firstVal = _expr();
            exprAux.push(first);
            exprAux.push(firstVal);
            uint256 pairCount = 1;

            while (_cur() == TokenType.COMMA) {
                _adv();
                if (_cur() == TokenType.RBRACE) break; // trailing comma
                uint256 k = _expr();
                _exp(TokenType.COLON);
                uint256 v = _expr();
                exprAux.push(k);
                exprAux.push(v);
                pairCount++;
            }
            _exp(TokenType.RBRACE);
            uint256 es = exprAux.length - (pairCount * 2);
            return _emit(NodeType.DICT_LITERAL, 0, 0, 0, es, pairCount, 0, "", ln, col);
        } else {
            // Set literal
            exprAux.push(first);
            uint256 elemCount = 1;

            while (_cur() == TokenType.COMMA) {
                _adv();
                if (_cur() == TokenType.RBRACE) break; // trailing comma
                exprAux.push(_expr());
                elemCount++;
            }
            _exp(TokenType.RBRACE);
            uint256 es = exprAux.length - elemCount;
            return _emit(NodeType.SET_LITERAL, 0, 0, 0, es, elemCount, 0, "", ln, col);
        }
    }

    // ==================== Helpers ====================

    function _cur() internal view returns (TokenType) {
        return p < tokenCount ? lexer.getTokenType(p) : TokenType.EOF;
    }

    function _lex() internal view returns (string memory) {
        return p < tokenCount ? lexer.getTokenLexeme(p) : "";
    }

    function _iv() internal view returns (uint256) {
        return p < tokenCount ? lexer.getTokenIntValue(p) : 0;
    }

    function _ln() internal view returns (uint256) {
        return p < tokenCount ? lexer.getTokenLine(p) : 0;
    }

    function _col() internal view returns (uint256) {
        return p < tokenCount ? lexer.getTokenColumn(p) : 0;
    }

    function _adv() internal { if (p < tokenCount) p++; }
    function _end() internal view returns (bool) { return p >= tokenCount || lexer.getTokenType(p) == TokenType.EOF; }

    function _exp(TokenType t) internal {
        if (_cur() == t) _adv();
    }

    function _skipNL() internal { while (_cur() == TokenType.NEWLINE) _adv(); }
    function _expectNL() internal { if (_cur() == TokenType.NEWLINE) _adv(); }

    function _emit(NodeType nt, uint256 a, uint256 b, uint256 c, uint256 ai, uint256 ac, uint256 iv, string memory sv, uint256 ln, uint256 co) internal returns (uint256) {
        uint256 idx = nts.length;
        nts.push(nt);
        c1s.push(a);
        c2s.push(b);
        c3s.push(c);
        ais.push(ai);
        acs.push(ac);
        ivs.push(iv);
        svs.push(sv);
        nls.push(ln);
        ncs.push(co);
        return idx;
    }

    function _build() internal view returns (ASTNode[] memory) {
        uint256 len = nts.length;
        ASTNode[] memory r = new ASTNode[](len);
        for (uint256 i = 0; i < len; i++) {
            r[i] = ASTNode({
                nodeType: nts[i], child1: c1s[i], child2: c2s[i], child3: c3s[i],
                auxIndex: ais[i], auxCount: acs[i], intValue: ivs[i],
                strValue: svs[i], line: nls[i], column: ncs[i]
            });
        }
        return r;
    }

    function getAuxData(uint256 index) public view returns (uint256) { return aux[index]; }
    function getAuxDataLength() public view returns (uint256) { return aux.length; }
    function getExprAuxData(uint256 index) public view returns (uint256) { return exprAux[index]; }
    function getExprAuxDataLength() public view returns (uint256) { return exprAux.length; }

    function getNodeCount() public view returns (uint256) { return nts.length; }

    function getNodeType(uint256 index) public view returns (NodeType) { return nts[index]; }
    function getChild1(uint256 index) public view returns (uint256) { return c1s[index]; }
    function getChild2(uint256 index) public view returns (uint256) { return c2s[index]; }
    function getChild3(uint256 index) public view returns (uint256) { return c3s[index]; }
    function getAuxIndex(uint256 index) public view returns (uint256) { return ais[index]; }
    function getAuxCount(uint256 index) public view returns (uint256) { return acs[index]; }
    function getIntValue(uint256 index) public view returns (uint256) { return ivs[index]; }
    function getStrValue(uint256 index) public view returns (string memory) { return svs[index]; }
    function getLine(uint256 index) public view returns (uint256) { return nls[index]; }
    function getColumn(uint256 index) public view returns (uint256) { return ncs[index]; }

    // Mutators for optimizer
    function setNodeType(uint256 index, NodeType nt) public { nts[index] = nt; }
    function setIntValue(uint256 index, uint256 v) public { ivs[index] = v; }
    function setAuxCount(uint256 index, uint256 v) public { acs[index] = v; }
    function setChild1(uint256 index, uint256 v) public { c1s[index] = v; }
    function setChild2(uint256 index, uint256 v) public { c2s[index] = v; }
    function setChild3(uint256 index, uint256 v) public { c3s[index] = v; }
}
