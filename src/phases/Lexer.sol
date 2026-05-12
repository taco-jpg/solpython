// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Token, TokenType} from "../types/Token.sol";
import {StringLib} from "../libraries/StringLib.sol";

contract Lexer {
    using StringLib for *;

    bytes private source;
    uint256 private pos;
    uint256 private line;
    uint256 private column;
    bool private atLineStart;

    // Indent stack for tracking indent levels
    uint256[] private indentStack;

    // Token storage (separate arrays to avoid memory->storage copy issues with strings)
    TokenType[] private tokenTypes;
    string[] private tokenLexemes;
    uint256[] private tokenIntValues;
    uint256[] private tokenLines;
    uint256[] private tokenColumns;

    event Error(string message, uint256 lineNum, uint256 col);

    constructor() {
        indentStack.push(0);
        atLineStart = true;
    }

    function tokenize(string memory input) public returns (Token[] memory) {
        source = StringLib.toBytes(input);
        pos = 0;
        line = 1;
        column = 1;
        atLineStart = true;

        while (pos < source.length) {
            if (atLineStart) {
                _handleIndentation();
            }

            if (pos >= source.length) break;

            bytes1 c = StringLib.charAt(source, pos);

            // Skip whitespace (but not newlines)
            if (StringLib.isWhitespace(c)) {
                pos++;
                column++;
                continue;
            }

            // Skip comments
            if (c == 0x23) { // '#'
                _skipComment();
                continue;
            }

            // Newline
            if (StringLib.isNewline(c)) {
                _handleNewline();
                continue;
            }

            // Numbers
            if (StringLib.isDigit(c)) {
                _readNumber();
                continue;
            }

            // Identifiers and keywords
            if (StringLib.isAlpha(c)) {
                _readIdentifier();
                continue;
            }

            // String literals
            if (c == 0x22 || c == 0x27) { // '"' or "'"
                _readString();
                continue;
            }

            // Operators and delimiters
            _readOperator();
        }

        // Emit trailing NEWLINE if there are tokens and last isn't NEWLINE
        // (needed for multi-line inputs that end without trailing newline)
        uint256 len = tokenTypes.length;
        if (len > 0 && tokenTypes[len - 1] != TokenType.NEWLINE) {
            _emitToken(TokenType.NEWLINE, "", 0);
        }

        // Emit remaining DEDENTs
        while (indentStack.length > 1) {
            indentStack.pop();
            _emitToken(TokenType.DEDENT, "", 0);
        }

        _emitToken(TokenType.EOF, "", 0);

        return _buildTokenArray();
    }

    function _handleIndentation() internal {
        uint256 spaces = 0;
        while (pos < source.length) {
            bytes1 c = StringLib.charAt(source, pos);
            if (c == 0x20) { // space
                spaces++;
                pos++;
                column++;
            } else if (c == 0x09) { // tab
                spaces += 4;
                pos += 4;
                column += 4;
            } else {
                break;
            }
        }

        // Skip blank lines
        if (pos < source.length && StringLib.isNewline(StringLib.charAt(source, pos))) {
            return;
        }

        // Skip comment-only lines
        if (pos < source.length && StringLib.charAt(source, pos) == 0x23) {
            return;
        }

        uint256 currentIndent = indentStack[indentStack.length - 1];

        if (spaces > currentIndent) {
            indentStack.push(spaces);
            _emitToken(TokenType.INDENT, "", 0);
        } else if (spaces < currentIndent) {
            while (indentStack.length > 1 && indentStack[indentStack.length - 1] > spaces) {
                indentStack.pop();
                _emitToken(TokenType.DEDENT, "", 0);
            }
            if (indentStack[indentStack.length - 1] != spaces) {
                emit Error("Indentation error", line, column);
                _emitToken(TokenType.ERROR, "indentation error", 0);
            }
        }

        atLineStart = false;
    }

    function _handleNewline() internal {
        bytes1 c = StringLib.charAt(source, pos);
        pos++;
        if (c == 0x0D && pos < source.length && StringLib.charAt(source, pos) == 0x0A) {
            pos++; // skip \r\n
        }
        // Emit NEWLINE with current line (before incrementing)
        _emitToken(TokenType.NEWLINE, "", 0);
        line++;
        column = 1;
        atLineStart = true;
    }

    function _skipComment() internal {
        while (pos < source.length && !StringLib.isNewline(StringLib.charAt(source, pos))) {
            pos++;
            column++;
        }
    }

    function _readNumber() internal {
        uint256 start = pos;
        bool isFloat = false;

        while (pos < source.length && StringLib.isDigit(StringLib.charAt(source, pos))) {
            pos++;
            column++;
        }

        if (pos < source.length && StringLib.charAt(source, pos) == 0x2E) { // '.'
            isFloat = true;
            pos++;
            column++;
            while (pos < source.length && StringLib.isDigit(StringLib.charAt(source, pos))) {
                pos++;
                column++;
            }
        }

        bytes memory lexeme = StringLib.slice(source, start, pos);
        uint256 value = StringLib.bytesToUint(lexeme);

        if (isFloat) {
            _emitToken(TokenType.FLOAT, StringLib.fromBytes(lexeme), value);
        } else {
            _emitToken(TokenType.INTEGER, StringLib.fromBytes(lexeme), value);
        }
    }

    function _readIdentifier() internal {
        uint256 start = pos;

        while (pos < source.length && StringLib.isAlphaNumeric(StringLib.charAt(source, pos))) {
            pos++;
            column++;
        }

        bytes memory lexeme = StringLib.slice(source, start, pos);
        string memory lexStr = StringLib.fromBytes(lexeme);

        TokenType tt = _keywordType(lexStr);
        _emitToken(tt, lexStr, 0);
    }

    function _keywordType(string memory word) internal pure returns (TokenType) {
        bytes32 hash = keccak256(bytes(word));
        if (hash == keccak256("def")) return TokenType.KW_DEF;
        if (hash == keccak256("return")) return TokenType.KW_RETURN;
        if (hash == keccak256("if")) return TokenType.KW_IF;
        if (hash == keccak256("else")) return TokenType.KW_ELSE;
        if (hash == keccak256("elif")) return TokenType.KW_ELIF;
        if (hash == keccak256("while")) return TokenType.KW_WHILE;
        if (hash == keccak256("for")) return TokenType.KW_FOR;
        if (hash == keccak256("in")) return TokenType.KW_IN;
        if (hash == keccak256("pass")) return TokenType.KW_PASS;
        if (hash == keccak256("break")) return TokenType.KW_BREAK;
        if (hash == keccak256("continue")) return TokenType.KW_CONTINUE;
        if (hash == keccak256("import")) return TokenType.KW_IMPORT;
        if (hash == keccak256("from")) return TokenType.KW_FROM;
        if (hash == keccak256("class")) return TokenType.KW_CLASS;
        if (hash == keccak256("True")) return TokenType.BOOL_TRUE;
        if (hash == keccak256("False")) return TokenType.BOOL_FALSE;
        if (hash == keccak256("None")) return TokenType.NONE_VAL;
        if (hash == keccak256("and")) return TokenType.KW_AND;
        if (hash == keccak256("or")) return TokenType.KW_OR;
        if (hash == keccak256("not")) return TokenType.KW_NOT;
        if (hash == keccak256("is")) return TokenType.KW_IS;
        if (hash == keccak256("lambda")) return TokenType.KW_LAMBDA;
        if (hash == keccak256("print")) return TokenType.KW_PRINT;
        if (hash == keccak256("try")) return TokenType.KW_TRY;
        if (hash == keccak256("except")) return TokenType.KW_EXCEPT;
        if (hash == keccak256("finally")) return TokenType.KW_FINALLY;
        if (hash == keccak256("raise")) return TokenType.KW_RAISE;
        return TokenType.IDENTIFIER;
    }

    function _readString() internal {
        bytes1 quote = StringLib.charAt(source, pos);
        uint256 start = pos;
        uint256 startCol = column;
        pos++;
        column++;

        // Handle triple quotes
        bool tripleQuote = false;
        if (pos + 1 < source.length &&
            StringLib.charAt(source, pos) == quote &&
            StringLib.charAt(source, pos + 1) == quote) {
            tripleQuote = true;
            pos += 2;
            column += 2;
        }

        while (pos < source.length) {
            bytes1 c = StringLib.charAt(source, pos);
            if (tripleQuote) {
                if (c == quote &&
                    pos + 2 < source.length &&
                    StringLib.charAt(source, pos + 1) == quote &&
                    StringLib.charAt(source, pos + 2) == quote) {
                    pos += 3;
                    column += 3;
                    break;
                }
            } else {
                if (c == quote) {
                    pos++;
                    column++;
                    break;
                }
                if (c == 0x5C) { // backslash
                    pos++;
                    column++;
                    if (pos < source.length) {
                        pos++;
                        column++;
                    }
                    continue;
                }
                if (StringLib.isNewline(c)) {
                    emit Error("Unterminated string", line, startCol);
                    _emitToken(TokenType.ERROR, "unterminated string", 0);
                    return;
                }
            }
            pos++;
            column++;
        }

        bytes memory lexeme = StringLib.slice(source, start, pos);
        _emitToken(TokenType.STRING, StringLib.fromBytes(lexeme), 0);
    }

    function _readOperator() internal {
        bytes1 c = StringLib.charAt(source, pos);

        if (c == 0x2B) { // +
            pos++; column++;
            if (pos < source.length && StringLib.charAt(source, pos) == 0x3D) { // =
                pos++; column++;
                _emitToken(TokenType.OP_PLUS_ASSIGN, "+=", 0);
            } else {
                _emitToken(TokenType.OP_PLUS, "+", 0);
            }
        } else if (c == 0x2D) { // -
            pos++; column++;
            if (pos < source.length && StringLib.charAt(source, pos) == 0x3D) {
                pos++; column++;
                _emitToken(TokenType.OP_MINUS_ASSIGN, "-=", 0);
            } else {
                _emitToken(TokenType.OP_MINUS, "-", 0);
            }
        } else if (c == 0x2A) { // *
            pos++; column++;
            if (pos < source.length && StringLib.charAt(source, pos) == 0x2A) { // **
                pos++; column++;
                _emitToken(TokenType.OP_DSTAR, "**", 0);
            } else if (pos < source.length && StringLib.charAt(source, pos) == 0x3D) { // =
                pos++; column++;
                _emitToken(TokenType.OP_STAR_ASSIGN, "*=", 0);
            } else {
                _emitToken(TokenType.OP_STAR, "*", 0);
            }
        } else if (c == 0x2F) { // /
            pos++; column++;
            if (pos < source.length && StringLib.charAt(source, pos) == 0x2F) { // //
                pos++; column++;
                _emitToken(TokenType.OP_DSLASH, "//", 0);
            } else if (pos < source.length && StringLib.charAt(source, pos) == 0x3D) { // =
                pos++; column++;
                _emitToken(TokenType.OP_SLASH_ASSIGN, "/=", 0);
            } else {
                _emitToken(TokenType.OP_SLASH, "/", 0);
            }
        } else if (c == 0x25) { // %
            pos++; column++;
            _emitToken(TokenType.OP_PERCENT, "%", 0);
        } else if (c == 0x3D) { // =
            pos++; column++;
            if (pos < source.length && StringLib.charAt(source, pos) == 0x3D) {
                pos++; column++;
                _emitToken(TokenType.OP_EQ, "==", 0);
            } else {
                _emitToken(TokenType.OP_ASSIGN, "=", 0);
            }
        } else if (c == 0x21) { // !
            pos++; column++;
            if (pos < source.length && StringLib.charAt(source, pos) == 0x3D) {
                pos++; column++;
                _emitToken(TokenType.OP_NEQ, "!=", 0);
            } else {
                emit Error("Unexpected character '!'", line, column);
                _emitToken(TokenType.ERROR, "!", 0);
            }
        } else if (c == 0x3C) { // <
            pos++; column++;
            if (pos < source.length && StringLib.charAt(source, pos) == 0x3D) {
                pos++; column++;
                _emitToken(TokenType.OP_LTE, "<=", 0);
            } else {
                _emitToken(TokenType.OP_LT, "<", 0);
            }
        } else if (c == 0x3E) { // >
            pos++; column++;
            if (pos < source.length && StringLib.charAt(source, pos) == 0x3D) {
                pos++; column++;
                _emitToken(TokenType.OP_GTE, ">=", 0);
            } else {
                _emitToken(TokenType.OP_GT, ">", 0);
            }
        } else if (c == 0x28) { // (
            pos++; column++;
            _emitToken(TokenType.LPAREN, "(", 0);
        } else if (c == 0x29) { // )
            pos++; column++;
            _emitToken(TokenType.RPAREN, ")", 0);
        } else if (c == 0x5B) { // [
            pos++; column++;
            _emitToken(TokenType.LBRACKET, "[", 0);
        } else if (c == 0x5D) { // ]
            pos++; column++;
            _emitToken(TokenType.RBRACKET, "]", 0);
        } else if (c == 0x7B) { // {
            pos++; column++;
            _emitToken(TokenType.LBRACE, "{", 0);
        } else if (c == 0x7D) { // }
            pos++; column++;
            _emitToken(TokenType.RBRACE, "}", 0);
        } else if (c == 0x2C) { // ,
            pos++; column++;
            _emitToken(TokenType.COMMA, ",", 0);
        } else if (c == 0x3A) { // :
            pos++; column++;
            _emitToken(TokenType.COLON, ":", 0);
        } else if (c == 0x2E) { // .
            pos++; column++;
            _emitToken(TokenType.DOT, ".", 0);
        } else if (c == 0x3B) { // ;
            pos++; column++;
            _emitToken(TokenType.SEMICOLON, ";", 0);
        } else {
            emit Error(StringLib.concat("Unexpected character: ", StringLib.fromBytes(StringLib.slice(source, pos, pos + 1))), line, column);
            pos++; column++;
            _emitToken(TokenType.ERROR, "?", 0);
        }
    }

    function _emitToken(TokenType tt, string memory lexeme, uint256 value) internal {
        tokenTypes.push(tt);
        tokenLexemes.push(lexeme);
        tokenIntValues.push(value);
        tokenLines.push(line);
        tokenColumns.push(column);
    }

    function _buildTokenArray() internal view returns (Token[] memory) {
        uint256 len = tokenTypes.length;
        Token[] memory result = new Token[](len);
        for (uint256 i = 0; i < len; i++) {
            result[i] = Token({
                tokenType: tokenTypes[i],
                lexeme: tokenLexemes[i],
                intValue: tokenIntValues[i],
                line: tokenLines[i],
                column: tokenColumns[i]
            });
        }
        return result;
    }

    function getTokenCount() public view returns (uint256) {
        return tokenTypes.length;
    }

    function getToken(uint256 index) public view returns (Token memory) {
        require(index < tokenTypes.length, "Lexer: index out of bounds");
        return Token({
            tokenType: tokenTypes[index],
            lexeme: tokenLexemes[index],
            intValue: tokenIntValues[index],
            line: tokenLines[index],
            column: tokenColumns[index]
        });
    }

    function getTokenType(uint256 index) public view returns (TokenType) {
        return tokenTypes[index];
    }

    function getTokenLexeme(uint256 index) public view returns (string memory) {
        return tokenLexemes[index];
    }

    function getTokenIntValue(uint256 index) public view returns (uint256) {
        return tokenIntValues[index];
    }

    function getTokenLine(uint256 index) public view returns (uint256) {
        return tokenLines[index];
    }

    function getTokenColumn(uint256 index) public view returns (uint256) {
        return tokenColumns[index];
    }
}
