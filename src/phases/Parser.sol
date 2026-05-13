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

    // Function default parameters
    mapping(string => uint256[]) private _funcDefaults;
    mapping(string => uint256) private _funcDefaultCount;
    mapping(string => uint256) private _funcParamCount;
    mapping(string => uint256) private _funcParamStart; // start index in exprAux for param names

    // Temp storage for function call argument nodes (avoids exprAux interleaving)
    uint256[] private _callArgs;

    function _resetArrays() internal {
        while (nts.length > 0) nts.pop();
        while (c1s.length > 0) c1s.pop();
        while (c2s.length > 0) c2s.pop();
        while (c3s.length > 0) c3s.pop();
        while (ais.length > 0) ais.pop();
        while (acs.length > 0) acs.pop();
        while (ivs.length > 0) ivs.pop();
        while (svs.length > 0) svs.pop();
        while (nls.length > 0) nls.pop();
        while (ncs.length > 0) ncs.pop();
        while (aux.length > 0) aux.pop();
        while (exprAux.length > 0) exprAux.pop();
        while (bodyStackIdx.length > 0) bodyStackIdx.pop();
        while (bodyNodeIdx.length > 0) bodyNodeIdx.pop();
        while (_bodyNesting.length > 0) _bodyNesting.pop();
        while (_callArgs.length > 0) _callArgs.pop();
        while (bodyStack.length > 0) bodyStack.pop();
    }

    function parse(Lexer _lexer) public returns (ASTNode[] memory) {
        _resetArrays();
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
        if (t == TokenType.KW_GLOBAL) return _globalStmt();
        if (t == TokenType.KW_NONLOCAL) return _nonlocalStmt();
        return _assignOrExpr();
    }

    function _funcDef() internal returns (uint256) {
        uint256 ln = _ln(); uint256 col = _col();
        _adv();
        string memory name = _lex();
        _adv();
        _exp(TokenType.LPAREN);
        (uint256 funcPs, uint256 funcPc) = _parseFuncParams(name);
        _exp(TokenType.RPAREN);
        _skipNL();
        _exp(TokenType.COLON);

        uint256 lvl = _bodyPush();
        uint256 body = _suite();
        _bodyPopTo(lvl, body);
        return _emit(NodeType.FUNCTION_DEF, 0, body, 0, funcPs, funcPc, _funcDefaultCount[name], name, ln, col);
    }

    function _parseFuncParams(string memory name) internal returns (uint256 ps, uint256 pc) {
        pc = 0;
        uint256 defaultCnt = 0;
        while (_cur() != TokenType.RPAREN && !_end()) {
            string memory param = _lex();
            _exp(TokenType.IDENTIFIER);
            exprAux.push(_emit(NodeType.IDENTIFIER_REF, 0, 0, 0, 0, 0, 0, param, _ln(), _col()));
            pc++;
            if (_cur() == TokenType.OP_ASSIGN) {
                _adv();
                _funcDefaults[name].push(_emit(NodeType.DEFAULT_VALUE, _expr(), 0, 0, 0, 0, 0, "", _ln(), _col()));
                defaultCnt++;
            }
            if (_cur() == TokenType.COMMA) _adv();
        }
        ps = exprAux.length - pc;
        _funcDefaultCount[name] = defaultCnt;
        _funcParamCount[name] = pc;
        _funcParamStart[name] = ps;
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
        uint256 elseBody = _parseElseClause();
        return _emit(NodeType.WHILE_LOOP, cond, body, elseBody, 0, 0, 0, "", ln, col);
    }

    uint256 private _forElseBody;
    uint256 private _forLn;
    uint256 private _forCol;

    function _forLoop() internal returns (uint256) {
        _forLn = _ln(); _forCol = _col();
        _adv();
        uint256 varNode = _parseForTarget();
        _skipNL();
        _exp(TokenType.KW_IN);
        uint256 iter = _expr();
        _skipNL();
        _exp(TokenType.COLON);
        uint256 lvl = _bodyPush();
        uint256 body = _suite();
        _bodyPopTo(lvl, body);
        _forElseBody = _parseElseClause();
        return _emit(NodeType.FOR_LOOP, varNode, iter, body, _forElseBody, 0, 0, "", _forLn, _forCol);
    }

    function _parseForTarget() internal returns (uint256) {
        string memory name = _lex();
        _exp(TokenType.IDENTIFIER);
        if (_cur() != TokenType.COMMA) {
            return _emit(NodeType.IDENTIFIER_REF, 0, 0, 0, 0, 0, 0, name, _forLn, _forCol);
        }
        // Tuple target: a, b, c
        uint256 ec = 1;
        exprAux.push(_emit(NodeType.IDENTIFIER_REF, 0, 0, 0, 0, 0, 0, name, _forLn, _forCol));
        while (_cur() == TokenType.COMMA) {
            _adv();
            string memory nextName = _lex();
            _exp(TokenType.IDENTIFIER);
            exprAux.push(_emit(NodeType.IDENTIFIER_REF, 0, 0, 0, 0, 0, 0, nextName, _forLn, _forCol));
            ec++;
        }
        uint256 es = exprAux.length - ec;
        return _emit(NodeType.TUPLE_LITERAL, 0, 0, 0, es, ec, 0, "", _forLn, _forCol);
    }

    function _parseElseClause() internal returns (uint256) {
        _skipNL();
        if (_cur() != TokenType.KW_ELSE) return 0;
        _adv();
        _exp(TokenType.COLON);
        uint256 lvl = _bodyPush();
        uint256 body = _suite();
        _bodyPopTo(lvl, body);
        return body;
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

    function _globalStmt() internal returns (uint256) {
        uint256 ln = _ln(); uint256 col = _col();
        _adv(); // skip 'global'
        // Parse comma-separated variable names
        uint256 nameCount = 0;
        uint256 firstVar = 0;
        do {
            string memory name = _lex();
            _exp(TokenType.IDENTIFIER);
            uint256 varNode = _emit(NodeType.IDENTIFIER_REF, 0, 0, 0, 0, 0, 0, name, ln, col);
            if (nameCount == 0) firstVar = varNode;
            nameCount++;
            if (_cur() == TokenType.COMMA) _adv();
            else break;
        } while (true);
        // Store first variable in child1, count in auxCount
        return _emit(NodeType.GLOBAL_STMT, firstVar, 0, 0, 0, nameCount, 0, "", ln, col);
    }

    function _nonlocalStmt() internal returns (uint256) {
        uint256 ln = _ln(); uint256 col = _col();
        _adv(); // skip 'nonlocal'
        // Parse comma-separated variable names
        uint256 nameCount = 0;
        uint256 firstVar = 0;
        do {
            string memory name = _lex();
            _exp(TokenType.IDENTIFIER);
            uint256 varNode = _emit(NodeType.IDENTIFIER_REF, 0, 0, 0, 0, 0, 0, name, ln, col);
            if (nameCount == 0) firstVar = varNode;
            nameCount++;
            if (_cur() == TokenType.COMMA) _adv();
            else break;
        } while (true);
        return _emit(NodeType.NONLOCAL_STMT, firstVar, 0, 0, 0, nameCount, 0, "", ln, col);
    }

    function _parseFString() internal returns (uint256) {
        uint256 ln = _ln(); uint256 col = _col();
        string memory raw = _lex(); // content between quotes (without f prefix)
        _adv();

        // Strip surrounding quotes if present
        bytes memory rawBytes = bytes(raw);
        string memory content = raw;
        if (rawBytes.length >= 2 && (rawBytes[0] == 0x22 || rawBytes[0] == 0x27)) {
            bytes memory stripped = new bytes(rawBytes.length - 2);
            for (uint256 i = 1; i < rawBytes.length - 1; i++) {
                stripped[i - 1] = rawBytes[i];
            }
            content = string(stripped);
        }

        // Store raw content in strValue; code generator will parse {var} references
        return _emit(NodeType.FSTRING_EXPR, 0, 0, 0, 0, 0, 0, content, ln, col);
    }

    function _assignOrExpr() internal returns (uint256) {
        uint256 ln = _ln(); uint256 col = _col();
        uint256 lhs = _expr();

        // Check for tuple unpacking: a, b, c = expr
        if (_cur() == TokenType.COMMA) {
            uint256 ec = 1;
            exprAux.push(lhs);
            while (_cur() == TokenType.COMMA && !_end()) {
                _adv();
                if (_cur() == TokenType.OP_ASSIGN) break;
                exprAux.push(_expr());
                ec++;
            }
            uint256 es = exprAux.length - ec;
            lhs = _emit(NodeType.TUPLE_LITERAL, 0, 0, 0, es, ec, 0, "", ln, col);
        }

        TokenType t = _cur();
        if (t == TokenType.OP_ASSIGN) {
            _adv();
            uint256 rhs = _expr();
            // If LHS is tuple unpacking and RHS is not a tuple/call, parse multi-value RHS
            if (getNodeType(lhs) == NodeType.TUPLE_LITERAL) {
                uint256 lhsCount = getAuxCount(lhs);
                // Parse remaining RHS values as a tuple: a, b = 1, 2
                if (_cur() == TokenType.COMMA) {
                    uint256 rc = 1;
                    uint256 rhsLn = _ln(); uint256 rhsCol = _col();
                    exprAux.push(rhs);
                    while (_cur() == TokenType.COMMA && !_end()) {
                        _adv();
                        exprAux.push(_expr());
                        rc++;
                    }
                    uint256 rs = exprAux.length - rc;
                    rhs = _emit(NodeType.TUPLE_LITERAL, 0, 0, 0, rs, rc, 0, "", rhsLn, rhsCol);
                }
            }
            return _emit(NodeType.ASSIGN, lhs, rhs, 0, 0, 0, 0, "", ln, col);
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

    function _expr() internal returns (uint256) {
        uint256 val = _boolOr();
        if (_cur() == TokenType.KW_IF) {
            uint256 ln = _ln(); uint256 col = _col();
            _adv();
            uint256 cond = _boolOr();
            _exp(TokenType.KW_ELSE);
            uint256 falseVal = _expr();
            return _emit(NodeType.TERNARY_EXPR, val, cond, falseVal, 0, 0, 0, "", ln, col);
        }
        return val;
    }

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
        if (!_isCmp(_cur())) return l;

        uint256 ln = _ln(); uint256 col = _col();
        CompOpType op = _cmpOp(_cur());
        _adv();
        uint256 m = _add();

        // Chained comparison: a op1 b op2 c ... → (a op1 b) and (b op2 c) and ...
        if (_isCmp(_cur())) {
            return _cmpChain(l, m, op, ln, col);
        }

        return _emit(NodeType.COMPARISON, l, m, 0, 0, 0, uint256(op), "", ln, col);
    }

    function _cmpChain(uint256 l, uint256 m, CompOpType op, uint256 ln, uint256 col) internal returns (uint256) {
        uint256 result = _emit(NodeType.COMPARISON, l, m, 0, 0, 0, uint256(op), "", ln, col);
        while (_isCmp(_cur())) {
            ln = _ln(); col = _col();
            CompOpType nextOp = _cmpOp(_cur());
            _adv();
            uint256 r = _add();
            uint256 nextCmp = _emit(NodeType.COMPARISON, m, r, 0, 0, 0, uint256(nextOp), "", ln, col);
            result = _emit(NodeType.BOOL_AND, result, nextCmp, 0, 0, 0, 0, "", ln, col);
            m = r;
        }
        return result;
    }

    function _isCmp(TokenType t) internal view returns (bool) {
        if (t == TokenType.OP_EQ || t == TokenType.OP_NEQ || t == TokenType.OP_LT ||
            t == TokenType.OP_GT || t == TokenType.OP_LTE || t == TokenType.OP_GTE ||
            t == TokenType.KW_IN || t == TokenType.KW_IS) return true;
        // Check for "not in" (KW_NOT followed by KW_IN)
        if (t == TokenType.KW_NOT && _peek() == TokenType.KW_IN) return true;
        // Check for "is not" (KW_IS followed by KW_NOT)
        if (t == TokenType.KW_IS && _peek() == TokenType.KW_NOT) return true;
        return false;
    }

    function _cmpOp(TokenType t) internal returns (CompOpType) {
        if (t == TokenType.OP_EQ) return CompOpType.EQ;
        if (t == TokenType.OP_NEQ) return CompOpType.NEQ;
        if (t == TokenType.OP_LT) return CompOpType.LT;
        if (t == TokenType.OP_GT) return CompOpType.GT;
        if (t == TokenType.OP_LTE) return CompOpType.LTE;
        if (t == TokenType.OP_GTE) return CompOpType.GTE;
        if (t == TokenType.KW_IN) return CompOpType.IN;
        if (t == TokenType.KW_IS) {
            if (_peek() == TokenType.KW_NOT) {
                _adv(); // consume "is"
                return CompOpType.NEQ; // "is not" → NEQ
            }
            return CompOpType.EQ; // "is" → EQ (identity ≈ equality for our purposes)
        }
        // "not in" — consume both tokens
        _adv(); // consume "not"
        return CompOpType.NOT_IN;
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
        if (t == TokenType.FSTRING) {
            return _parseFString();
        }
        if (t == TokenType.LPAREN) {
            _adv();
            if (_cur() == TokenType.RPAREN) { _adv(); return _emit(NodeType.TUPLE_LITERAL, 0, 0, 0, 0, 0, 0, "", ln, col); }
            uint256 e = _expr();
            if (_cur() == TokenType.COMMA) {
                // Tuple literal: (a, b, c)
                uint256 ec = 1;
                exprAux.push(e);
                while (_cur() == TokenType.COMMA && !_end()) {
                    _adv();
                    if (_cur() == TokenType.RPAREN) break; // trailing comma
                    exprAux.push(_expr());
                    ec++;
                }
                _exp(TokenType.RPAREN);
                uint256 es = exprAux.length - ec;
                return _emit(NodeType.TUPLE_LITERAL, 0, 0, 0, es, ec, 0, "", ln, col);
            }
            _exp(TokenType.RPAREN);
            return e;
        }
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
        uint256 myStart = _callArgs.length;
        uint256 argCnt = 0;
        while (_cur() != TokenType.RPAREN && !_end()) {
            uint256 argExpr = _expr();
            // Check for keyword argument: name = expr
            if (_cur() == TokenType.OP_ASSIGN && nts[argExpr] == NodeType.IDENTIFIER_REF) {
                _adv(); // consume =
                string memory kwName = svs[argExpr];
                uint256 kwVal = _expr();
                _callArgs.push(_emit(NodeType.KEYWORD_ARG, kwVal, 0, 0, 0, 0, 0, kwName, _ln(), _col()));
            } else {
                _callArgs.push(argExpr);
            }
            argCnt++;
            if (_cur() == TokenType.COMMA) _adv();
        }
        _exp(TokenType.RPAREN);
        // Push arg nodes contiguously to exprAux
        uint256 argStart = exprAux.length;
        for (uint256 i = 0; i < argCnt; i++) {
            exprAux.push(_callArgs[myStart + i]);
        }
        // Remove my args from _callArgs
        while (_callArgs.length > myStart) _callArgs.pop();
        uint256 node = _emit(NodeType.FUNC_CALL, 0, 0, 0, argStart, argCnt, 0, name, ln, col);
        if (_cur() == TokenType.LBRACKET) return _idxAccess(node);
        return node;
    }

    function _methodCall(string memory objName, uint256 ln, uint256 col) internal returns (uint256) {
        // obj is already parsed as IDENTIFIER_REF — create it and push as first arg
        uint256 objNode = _emit(NodeType.IDENTIFIER_REF, 0, 0, 0, 0, 0, 0, objName, ln, col);
        uint256 myStart = _callArgs.length;
        _callArgs.push(objNode);
        uint256 argCnt = 1; // object is first argument

        _exp(TokenType.DOT); // consume the dot
        uint256 methodLn = _ln(); uint256 methodCol = _col();
        string memory methodName = _lex();
        _adv();

        _exp(TokenType.LPAREN);
        while (_cur() != TokenType.RPAREN && !_end()) {
            _callArgs.push(_expr());
            argCnt++;
            if (_cur() == TokenType.COMMA) _adv();
        }
        _exp(TokenType.RPAREN);
        // Push arg nodes contiguously to exprAux
        uint256 argStart = exprAux.length;
        for (uint256 i = 0; i < argCnt; i++) {
            exprAux.push(_callArgs[myStart + i]);
        }
        // Remove my args from _callArgs
        while (_callArgs.length > myStart) _callArgs.pop();
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

    function _peek() internal view returns (TokenType) {
        return (p + 1) < tokenCount ? lexer.getTokenType(p + 1) : TokenType.EOF;
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

    function getFuncDefaultCount(string memory funcName) public view returns (uint256) { return _funcDefaultCount[funcName]; }
    function getFuncParamCount(string memory funcName) public view returns (uint256) { return _funcParamCount[funcName]; }
    function getFuncDefaultNode(string memory funcName, uint256 index) public view returns (uint256) { return _funcDefaults[funcName][index]; }
    function getFuncParamStart(string memory funcName) public view returns (uint256) { return _funcParamStart[funcName]; }

    // Mutators for optimizer
    function setNodeType(uint256 index, NodeType nt) public { nts[index] = nt; }
    function setIntValue(uint256 index, uint256 v) public { ivs[index] = v; }
    function setAuxCount(uint256 index, uint256 v) public { acs[index] = v; }
    function setChild1(uint256 index, uint256 v) public { c1s[index] = v; }
    function setChild2(uint256 index, uint256 v) public { c2s[index] = v; }
    function setChild3(uint256 index, uint256 v) public { c3s[index] = v; }
}
