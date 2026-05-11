// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import {Lexer} from "../src/phases/Lexer.sol";
import {Token, TokenType} from "../src/types/Token.sol";

contract LexerTest is Test {
    Lexer lexer;

    function setUp() public {
        lexer = new Lexer();
    }

    // ==================== Basic Token Tests ====================

    function testEmptyInput() public {
        Token[] memory tokens = lexer.tokenize("");
        assertEq(uint256(tokens[0].tokenType), uint256(TokenType.EOF));
        assertEq(tokens.length, 1);
    }

    function testSingleInteger() public {
        Token[] memory tokens = lexer.tokenize("42");
        assertEq(uint256(tokens[0].tokenType), uint256(TokenType.INTEGER));
        assertEq(tokens[0].intValue, 42);
        assertEq(tokens[0].lexeme, "42");
        assertEq(uint256(tokens[1].tokenType), uint256(TokenType.NEWLINE));
        assertEq(uint256(tokens[2].tokenType), uint256(TokenType.EOF));
    }

    function testFloatLiteral() public {
        Token[] memory tokens = lexer.tokenize("3.14");
        assertEq(uint256(tokens[0].tokenType), uint256(TokenType.FLOAT));
        assertEq(tokens[0].intValue, 3); // integer part only in v1
        assertEq(tokens[0].lexeme, "3.14");
    }

    function testStringLiteralDouble() public {
        Token[] memory tokens = lexer.tokenize('"hello world"');
        assertEq(uint256(tokens[0].tokenType), uint256(TokenType.STRING));
        assertEq(tokens[0].lexeme, '"hello world"');
    }

    function testStringLiteralSingle() public {
        Token[] memory tokens = lexer.tokenize("'hello'");
        assertEq(uint256(tokens[0].tokenType), uint256(TokenType.STRING));
        assertEq(tokens[0].lexeme, "'hello'");
    }

    function testBooleanTrue() public {
        Token[] memory tokens = lexer.tokenize("True");
        assertEq(uint256(tokens[0].tokenType), uint256(TokenType.BOOL_TRUE));
    }

    function testBooleanFalse() public {
        Token[] memory tokens = lexer.tokenize("False");
        assertEq(uint256(tokens[0].tokenType), uint256(TokenType.BOOL_FALSE));
    }

    function testNoneLiteral() public {
        Token[] memory tokens = lexer.tokenize("None");
        assertEq(uint256(tokens[0].tokenType), uint256(TokenType.NONE_VAL));
    }

    // ==================== Identifier Tests ====================

    function testIdentifier() public {
        Token[] memory tokens = lexer.tokenize("foo_bar");
        assertEq(uint256(tokens[0].tokenType), uint256(TokenType.IDENTIFIER));
        assertEq(tokens[0].lexeme, "foo_bar");
    }

    function testIdentifierWithUnderscore() public {
        Token[] memory tokens = lexer.tokenize("_private");
        assertEq(uint256(tokens[0].tokenType), uint256(TokenType.IDENTIFIER));
        assertEq(tokens[0].lexeme, "_private");
    }

    // ==================== Keyword Tests ====================

    function testDefKeyword() public {
        Token[] memory tokens = lexer.tokenize("def");
        assertEq(uint256(tokens[0].tokenType), uint256(TokenType.KW_DEF));
    }

    function testReturnKeyword() public {
        Token[] memory tokens = lexer.tokenize("return");
        assertEq(uint256(tokens[0].tokenType), uint256(TokenType.KW_RETURN));
    }

    function testIfKeyword() public {
        Token[] memory tokens = lexer.tokenize("if");
        assertEq(uint256(tokens[0].tokenType), uint256(TokenType.KW_IF));
    }

    function testWhileKeyword() public {
        Token[] memory tokens = lexer.tokenize("while");
        assertEq(uint256(tokens[0].tokenType), uint256(TokenType.KW_WHILE));
    }

    function testForKeyword() public {
        Token[] memory tokens = lexer.tokenize("for");
        assertEq(uint256(tokens[0].tokenType), uint256(TokenType.KW_FOR));
    }

    function testAndKeyword() public {
        Token[] memory tokens = lexer.tokenize("and");
        assertEq(uint256(tokens[0].tokenType), uint256(TokenType.KW_AND));
    }

    function testOrKeyword() public {
        Token[] memory tokens = lexer.tokenize("or");
        assertEq(uint256(tokens[0].tokenType), uint256(TokenType.KW_OR));
    }

    function testNotKeyword() public {
        Token[] memory tokens = lexer.tokenize("not");
        assertEq(uint256(tokens[0].tokenType), uint256(TokenType.KW_NOT));
    }

    // ==================== Operator Tests ====================

    function testPlusOperator() public {
        Token[] memory tokens = lexer.tokenize("+");
        assertEq(uint256(tokens[0].tokenType), uint256(TokenType.OP_PLUS));
    }

    function testMinusOperator() public {
        Token[] memory tokens = lexer.tokenize("-");
        assertEq(uint256(tokens[0].tokenType), uint256(TokenType.OP_MINUS));
    }

    function testStarOperator() public {
        Token[] memory tokens = lexer.tokenize("*");
        assertEq(uint256(tokens[0].tokenType), uint256(TokenType.OP_STAR));
    }

    function testSlashOperator() public {
        Token[] memory tokens = lexer.tokenize("/");
        assertEq(uint256(tokens[0].tokenType), uint256(TokenType.OP_SLASH));
    }

    function testDoubleSlashOperator() public {
        Token[] memory tokens = lexer.tokenize("//");
        assertEq(uint256(tokens[0].tokenType), uint256(TokenType.OP_DSLASH));
    }

    function testPercentOperator() public {
        Token[] memory tokens = lexer.tokenize("%");
        assertEq(uint256(tokens[0].tokenType), uint256(TokenType.OP_PERCENT));
    }

    function testDoubleStarOperator() public {
        Token[] memory tokens = lexer.tokenize("**");
        assertEq(uint256(tokens[0].tokenType), uint256(TokenType.OP_DSTAR));
    }

    function testAssignmentOperator() public {
        Token[] memory tokens = lexer.tokenize("=");
        assertEq(uint256(tokens[0].tokenType), uint256(TokenType.OP_ASSIGN));
    }

    function testPlusAssign() public {
        Token[] memory tokens = lexer.tokenize("+=");
        assertEq(uint256(tokens[0].tokenType), uint256(TokenType.OP_PLUS_ASSIGN));
    }

    function testMinusAssign() public {
        Token[] memory tokens = lexer.tokenize("-=");
        assertEq(uint256(tokens[0].tokenType), uint256(TokenType.OP_MINUS_ASSIGN));
    }

    function testStarAssign() public {
        Token[] memory tokens = lexer.tokenize("*=");
        assertEq(uint256(tokens[0].tokenType), uint256(TokenType.OP_STAR_ASSIGN));
    }

    function testSlashAssign() public {
        Token[] memory tokens = lexer.tokenize("/=");
        assertEq(uint256(tokens[0].tokenType), uint256(TokenType.OP_SLASH_ASSIGN));
    }

    function testEqOperator() public {
        Token[] memory tokens = lexer.tokenize("==");
        assertEq(uint256(tokens[0].tokenType), uint256(TokenType.OP_EQ));
    }

    function testNeqOperator() public {
        Token[] memory tokens = lexer.tokenize("!=");
        assertEq(uint256(tokens[0].tokenType), uint256(TokenType.OP_NEQ));
    }

    function testLtOperator() public {
        Token[] memory tokens = lexer.tokenize("<");
        assertEq(uint256(tokens[0].tokenType), uint256(TokenType.OP_LT));
    }

    function testGtOperator() public {
        Token[] memory tokens = lexer.tokenize(">");
        assertEq(uint256(tokens[0].tokenType), uint256(TokenType.OP_GT));
    }

    function testLteOperator() public {
        Token[] memory tokens = lexer.tokenize("<=");
        assertEq(uint256(tokens[0].tokenType), uint256(TokenType.OP_LTE));
    }

    function testGteOperator() public {
        Token[] memory tokens = lexer.tokenize(">=");
        assertEq(uint256(tokens[0].tokenType), uint256(TokenType.OP_GTE));
    }

    // ==================== Delimiter Tests ====================

    function testParentheses() public {
        Token[] memory tokens = lexer.tokenize("()");
        assertEq(uint256(tokens[0].tokenType), uint256(TokenType.LPAREN));
        assertEq(uint256(tokens[1].tokenType), uint256(TokenType.RPAREN));
    }

    function testBrackets() public {
        Token[] memory tokens = lexer.tokenize("[]");
        assertEq(uint256(tokens[0].tokenType), uint256(TokenType.LBRACKET));
        assertEq(uint256(tokens[1].tokenType), uint256(TokenType.RBRACKET));
    }

    function testBraces() public {
        Token[] memory tokens = lexer.tokenize("{}");
        assertEq(uint256(tokens[0].tokenType), uint256(TokenType.LBRACE));
        assertEq(uint256(tokens[1].tokenType), uint256(TokenType.RBRACE));
    }

    function testComma() public {
        Token[] memory tokens = lexer.tokenize(",");
        assertEq(uint256(tokens[0].tokenType), uint256(TokenType.COMMA));
    }

    function testColon() public {
        Token[] memory tokens = lexer.tokenize(":");
        assertEq(uint256(tokens[0].tokenType), uint256(TokenType.COLON));
    }

    function testDot() public {
        Token[] memory tokens = lexer.tokenize(".");
        assertEq(uint256(tokens[0].tokenType), uint256(TokenType.DOT));
    }

    // ==================== Expression Tests ====================

    function testSimpleExpression() public {
        // "1 + 2"
        Token[] memory tokens = lexer.tokenize("1 + 2");
        assertEq(uint256(tokens[0].tokenType), uint256(TokenType.INTEGER));
        assertEq(tokens[0].intValue, 1);
        assertEq(uint256(tokens[1].tokenType), uint256(TokenType.OP_PLUS));
        assertEq(uint256(tokens[2].tokenType), uint256(TokenType.INTEGER));
        assertEq(tokens[2].intValue, 2);
    }

    function testAssignment() public {
        Token[] memory tokens = lexer.tokenize("x = 10");
        assertEq(uint256(tokens[0].tokenType), uint256(TokenType.IDENTIFIER));
        assertEq(tokens[0].lexeme, "x");
        assertEq(uint256(tokens[1].tokenType), uint256(TokenType.OP_ASSIGN));
        assertEq(uint256(tokens[2].tokenType), uint256(TokenType.INTEGER));
        assertEq(tokens[2].intValue, 10);
    }

    // ==================== Indentation Tests ====================

    function testSimpleIndentDedent() public {
        string memory src = "if True:\n    pass\n";
        Token[] memory tokens = lexer.tokenize(src);

        // if True : NEWLINE INDENT pass NEWLINE DEDENT EOF
        assertEq(uint256(tokens[0].tokenType), uint256(TokenType.KW_IF));
        assertEq(uint256(tokens[1].tokenType), uint256(TokenType.BOOL_TRUE));
        assertEq(uint256(tokens[2].tokenType), uint256(TokenType.COLON));
        assertEq(uint256(tokens[3].tokenType), uint256(TokenType.NEWLINE));
        assertEq(uint256(tokens[4].tokenType), uint256(TokenType.INDENT));
        assertEq(uint256(tokens[5].tokenType), uint256(TokenType.KW_PASS));
        assertEq(uint256(tokens[6].tokenType), uint256(TokenType.NEWLINE));
        assertEq(uint256(tokens[7].tokenType), uint256(TokenType.DEDENT));
    }

    function testNestedIndent() public {
        string memory src = "if True:\n    if False:\n        pass\n";
        Token[] memory tokens = lexer.tokenize(src);

        // Find INDENT tokens
        uint256 indentCount = 0;
        uint256 dedentCount = 0;
        for (uint256 i = 0; i < tokens.length; i++) {
            if (tokens[i].tokenType == TokenType.INDENT) indentCount++;
            if (tokens[i].tokenType == TokenType.DEDENT) dedentCount++;
        }
        assertEq(indentCount, 2);
        assertEq(dedentCount, 2);
    }

    // ==================== Comment Tests ====================

    function testComment() public {
        Token[] memory tokens = lexer.tokenize("# this is a comment\n42");
        // Should skip comment, then parse 42
        bool foundInt = false;
        for (uint256 i = 0; i < tokens.length; i++) {
            if (tokens[i].tokenType == TokenType.INTEGER && tokens[i].intValue == 42) {
                foundInt = true;
            }
        }
        assertTrue(foundInt);
    }

    // ==================== Multi-line Tests ====================

    function testMultipleLines() public {
        string memory src = "x = 1\ny = 2\n";
        Token[] memory tokens = lexer.tokenize(src);

        // x = 1 NEWLINE y = 2 NEWLINE EOF
        assertEq(uint256(tokens[0].tokenType), uint256(TokenType.IDENTIFIER));
        assertEq(tokens[0].lexeme, "x");
        assertEq(uint256(tokens[1].tokenType), uint256(TokenType.OP_ASSIGN));
        assertEq(uint256(tokens[2].tokenType), uint256(TokenType.INTEGER));
        assertEq(tokens[2].intValue, 1);
        assertEq(uint256(tokens[3].tokenType), uint256(TokenType.NEWLINE));
        assertEq(uint256(tokens[4].tokenType), uint256(TokenType.IDENTIFIER));
        assertEq(tokens[4].lexeme, "y");
        assertEq(uint256(tokens[5].tokenType), uint256(TokenType.OP_ASSIGN));
        assertEq(uint256(tokens[6].tokenType), uint256(TokenType.INTEGER));
        assertEq(tokens[6].intValue, 2);
    }

    // ==================== Function Definition Test ====================

    function testFunctionDef() public {
        string memory src = "def foo():\n    return 1\n";
        Token[] memory tokens = lexer.tokenize(src);
        assertEq(uint256(tokens[0].tokenType), uint256(TokenType.KW_DEF));
        assertEq(uint256(tokens[1].tokenType), uint256(TokenType.IDENTIFIER));
        assertEq(tokens[1].lexeme, "foo");
        assertEq(uint256(tokens[2].tokenType), uint256(TokenType.LPAREN));
        assertEq(uint256(tokens[3].tokenType), uint256(TokenType.RPAREN));
        assertEq(uint256(tokens[4].tokenType), uint256(TokenType.COLON));
    }

    // ==================== Line Tracking ====================

    function testLineNumbers() public {
        string memory src = "x\ny\nz\n";
        Token[] memory tokens = lexer.tokenize(src);
        assertEq(tokens[0].line, 1); // x
        assertEq(tokens[1].line, 1); // NEWLINE after x
        // y is on line 2
        for (uint256 i = 0; i < tokens.length; i++) {
            if (tokens[i].tokenType == TokenType.IDENTIFIER && keccak256(bytes(tokens[i].lexeme)) == keccak256("y")) {
                assertEq(tokens[i].line, 2);
            }
        }
    }

    // ==================== Edge Cases ====================

    function testTwoCharOperatorDisambiguation() public {
        // Ensure == is not parsed as = =
        Token[] memory tokens = lexer.tokenize("==");
        assertEq(uint256(tokens[0].tokenType), uint256(TokenType.OP_EQ));
        assertEq(uint256(tokens[1].tokenType), uint256(TokenType.NEWLINE));
        assertEq(uint256(tokens[2].tokenType), uint256(TokenType.EOF));
    }

    function testAssignVsEquals() public {
        Token[] memory tokens = lexer.tokenize("= ==");
        assertEq(uint256(tokens[0].tokenType), uint256(TokenType.OP_ASSIGN));
        assertEq(uint256(tokens[1].tokenType), uint256(TokenType.OP_EQ));
    }

    function testStarVsDstar() public {
        Token[] memory tokens = lexer.tokenize("* **");
        assertEq(uint256(tokens[0].tokenType), uint256(TokenType.OP_STAR));
        assertEq(uint256(tokens[1].tokenType), uint256(TokenType.OP_DSTAR));
    }

    function testSlashVsDslash() public {
        Token[] memory tokens = lexer.tokenize("/ //");
        assertEq(uint256(tokens[0].tokenType), uint256(TokenType.OP_SLASH));
        assertEq(uint256(tokens[1].tokenType), uint256(TokenType.OP_DSLASH));
    }
}
