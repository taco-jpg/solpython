// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import {Lexer} from "../src/phases/Lexer.sol";
import {Parser} from "../src/phases/Parser.sol";
import {Token, TokenType} from "../src/types/Token.sol";
import {ASTNode, NodeType} from "../src/types/ASTNode.sol";

contract ParserTest is Test {
    Lexer lexer;
    Parser curParser;

    function setUp() public {
        lexer = new Lexer();
    }

    function _parse(string memory src) internal returns (ASTNode[] memory) {
        lexer.tokenize(src);
        curParser = new Parser();
        return curParser.parse(lexer);
    }

    function _firstStmt(ASTNode[] memory ast) internal view returns (uint256) {
        return curParser.getAuxData(ast[0].auxIndex);
    }

    function _childStmt(ASTNode memory node, uint256 n) internal view returns (uint256) {
        return curParser.getAuxData(node.auxIndex + n);
    }

    function _exprAux(ASTNode memory node, uint256 n) internal view returns (uint256) {
        return curParser.getExprAuxData(node.auxIndex + n);
    }

    // ==================== Basic Tests ====================

    function testEmptyProgram() public {
        ASTNode[] memory ast = _parse("");
        assertEq(uint256(ast[0].nodeType), uint256(NodeType.PROGRAM));
        assertEq(ast[0].auxCount, 0);
    }

    function testSingleIntLiteral() public {
        ASTNode[] memory ast = _parse("42\n");
        assertEq(ast[0].auxCount, 1);
        uint256 si = _firstStmt(ast);
        assertEq(uint256(ast[si].nodeType), uint256(NodeType.EXPR_STMT));
        uint256 expr = ast[si].child1;
        assertEq(uint256(ast[expr].nodeType), uint256(NodeType.INT_LITERAL));
        assertEq(ast[expr].intValue, 42);
    }

    // ==================== Assignment Tests ====================

    function testSimpleAssignment() public {
        ASTNode[] memory ast = _parse("x = 10\n");
        uint256 si = _firstStmt(ast);
        assertEq(uint256(ast[si].nodeType), uint256(NodeType.ASSIGN));
        assertEq(ast[ast[si].child1].strValue, "x");
        assertEq(ast[ast[si].child2].intValue, 10);
    }

    function testAugmentedAssignment() public {
        ASTNode[] memory ast = _parse("x += 5\n");
        uint256 si = _firstStmt(ast);
        assertEq(uint256(ast[si].nodeType), uint256(NodeType.AUG_ASSIGN));
    }

    // ==================== Expression Tests ====================

    function testBinaryAddition() public {
        ASTNode[] memory ast = _parse("1 + 2\n");
        uint256 expr = ast[_firstStmt(ast)].child1;
        assertEq(uint256(ast[expr].nodeType), uint256(NodeType.BINARY_OP));
        assertEq(ast[expr].intValue, 0); // ADD
        assertEq(ast[ast[expr].child1].intValue, 1);
        assertEq(ast[ast[expr].child2].intValue, 2);
    }

    function testBinarySubtraction() public {
        ASTNode[] memory ast = _parse("5 - 3\n");
        uint256 expr = ast[_firstStmt(ast)].child1;
        assertEq(ast[expr].intValue, 1); // SUB
    }

    function testBinaryMultiplication() public {
        ASTNode[] memory ast = _parse("3 * 4\n");
        uint256 expr = ast[_firstStmt(ast)].child1;
        assertEq(ast[expr].intValue, 2); // MUL
    }

    function testOperatorPrecedence() public {
        ASTNode[] memory ast = _parse("1 + 2 * 3\n");
        uint256 expr = ast[_firstStmt(ast)].child1;
        assertEq(ast[expr].intValue, 0); // ADD at top
        assertEq(ast[ast[expr].child2].intValue, 2); // MUL on right
    }

    function testParenthesizedExpression() public {
        ASTNode[] memory ast = _parse("(1 + 2) * 3\n");
        uint256 expr = ast[_firstStmt(ast)].child1;
        assertEq(ast[expr].intValue, 2); // MUL at top
        assertEq(ast[ast[expr].child1].intValue, 0); // ADD on left
    }

    function testComparison() public {
        ASTNode[] memory ast = _parse("x < 10\n");
        assertEq(uint256(ast[ast[_firstStmt(ast)].child1].nodeType), uint256(NodeType.COMPARISON));
    }

    function testBooleanAnd() public {
        ASTNode[] memory ast = _parse("True and False\n");
        assertEq(uint256(ast[ast[_firstStmt(ast)].child1].nodeType), uint256(NodeType.BOOL_AND));
    }

    function testBooleanOr() public {
        ASTNode[] memory ast = _parse("True or False\n");
        assertEq(uint256(ast[ast[_firstStmt(ast)].child1].nodeType), uint256(NodeType.BOOL_OR));
    }

    function testBooleanNot() public {
        ASTNode[] memory ast = _parse("not x\n");
        assertEq(uint256(ast[ast[_firstStmt(ast)].child1].nodeType), uint256(NodeType.BOOL_NOT));
    }

    function testUnaryNegation() public {
        ASTNode[] memory ast = _parse("-5\n");
        assertEq(uint256(ast[ast[_firstStmt(ast)].child1].nodeType), uint256(NodeType.UNARY_OP));
    }

    // ==================== Function Call Tests ====================

    function testFunctionCallNoArgs() public {
        ASTNode[] memory ast = _parse("foo()\n");
        uint256 expr = ast[_firstStmt(ast)].child1;
        assertEq(uint256(ast[expr].nodeType), uint256(NodeType.FUNC_CALL));
        assertEq(ast[expr].strValue, "foo");
        assertEq(ast[expr].auxCount, 0);
    }

    function testFunctionCallWithArgs() public {
        ASTNode[] memory ast = _parse("foo(1, 2, 3)\n");
        uint256 expr = ast[_firstStmt(ast)].child1;
        assertEq(uint256(ast[expr].nodeType), uint256(NodeType.FUNC_CALL));
        assertEq(ast[expr].auxCount, 3);
    }

    function testPrintCall() public {
        ASTNode[] memory ast = _parse("print(42)\n");
        uint256 expr = ast[_firstStmt(ast)].child1;
        assertEq(uint256(ast[expr].nodeType), uint256(NodeType.FUNC_CALL));
        assertEq(ast[expr].strValue, "print");
        assertEq(ast[expr].auxCount, 1);
    }

    // ==================== Control Flow Tests ====================

    function testIfStatement() public {
        ASTNode[] memory ast = _parse("if x > 0:\n    pass\n");
        assertEq(uint256(ast[_firstStmt(ast)].nodeType), uint256(NodeType.IF_STATEMENT));
    }

    function testIfElse() public {
        ASTNode[] memory ast = _parse("if x > 0:\n    pass\nelse:\n    pass\n");
        uint256 si = _firstStmt(ast);
        assertEq(uint256(ast[si].nodeType), uint256(NodeType.IF_STATEMENT));
        assertTrue(ast[si].child3 != 0);
    }

    function testIfElifElse() public {
        ASTNode[] memory ast = _parse("if x > 0:\n    pass\nelif x == 0:\n    pass\nelse:\n    pass\n");
        uint256 si = _firstStmt(ast);
        assertEq(ast[si].auxCount, 1);
    }

    function testWhileLoop() public {
        ASTNode[] memory ast = _parse("while x > 0:\n    pass\n");
        assertEq(uint256(ast[_firstStmt(ast)].nodeType), uint256(NodeType.WHILE_LOOP));
    }

    function testForLoop() public {
        ASTNode[] memory ast = _parse("for i in items:\n    pass\n");
        assertEq(uint256(ast[_firstStmt(ast)].nodeType), uint256(NodeType.FOR_LOOP));
    }

    // ==================== Function Definition Tests ====================

    function testFunctionDef() public {
        ASTNode[] memory ast = _parse("def foo():\n    pass\n");
        uint256 si = _firstStmt(ast);
        assertEq(uint256(ast[si].nodeType), uint256(NodeType.FUNCTION_DEF));
        assertEq(ast[si].strValue, "foo");
        assertEq(ast[si].auxCount, 0);
    }

    function testFunctionDefWithParams() public {
        ASTNode[] memory ast = _parse("def add(a, b):\n    return a + b\n");
        uint256 si = _firstStmt(ast);
        assertEq(uint256(ast[si].nodeType), uint256(NodeType.FUNCTION_DEF));
        assertEq(ast[si].strValue, "add");
        assertEq(ast[si].auxCount, 2);
    }

    function testFunctionDefWithReturn() public {
        ASTNode[] memory ast = _parse("def foo():\n    return 42\n");
        uint256 funcIdx = _firstStmt(ast);
        uint256 bodyIdx = ast[funcIdx].child2;
        assertEq(uint256(ast[bodyIdx].nodeType), uint256(NodeType.PROGRAM));
        uint256 retIdx = _childStmt(ast[bodyIdx], 0);
        assertEq(uint256(ast[retIdx].nodeType), uint256(NodeType.RETURN_STMT));
    }

    // ==================== List Tests ====================

    function testListLiteral() public {
        ASTNode[] memory ast = _parse("[1, 2, 3]\n");
        uint256 expr = ast[_firstStmt(ast)].child1;
        assertEq(uint256(ast[expr].nodeType), uint256(NodeType.LIST_LITERAL));
        assertEq(ast[expr].auxCount, 3);
    }

    function testEmptyList() public {
        ASTNode[] memory ast = _parse("[]\n");
        uint256 expr = ast[_firstStmt(ast)].child1;
        assertEq(ast[expr].auxCount, 0);
    }

    function testIndexAccess() public {
        ASTNode[] memory ast = _parse("a[0]\n");
        assertEq(uint256(ast[ast[_firstStmt(ast)].child1].nodeType), uint256(NodeType.INDEX_ACCESS));
    }

    // ==================== Class Tests ====================

    function testClassDef() public {
        ASTNode[] memory ast = _parse("class Foo:\n    pass\n");
        uint256 si = _firstStmt(ast);
        assertEq(uint256(ast[si].nodeType), uint256(NodeType.CLASS_DEF));
        assertEq(ast[si].strValue, "Foo");
    }

    // ==================== Multi-statement Tests ====================

    function testMultipleStatements() public {
        ASTNode[] memory ast = _parse("x = 1\ny = 2\nz = x + y\n");
        assertEq(ast[0].auxCount, 3);
    }

    function testReturnWithoutValue() public {
        ASTNode[] memory ast = _parse("def foo():\n    return\n");
        uint256 bodyIdx = ast[_firstStmt(ast)].child2;
        uint256 retIdx = _childStmt(ast[bodyIdx], 0);
        assertEq(uint256(ast[retIdx].nodeType), uint256(NodeType.RETURN_STMT));
        assertEq(ast[retIdx].child1, 0);
    }

    // ==================== Complex Tests ====================

    function testExponentiation() public {
        ASTNode[] memory ast = _parse("2 ** 3\n");
        uint256 expr = ast[_firstStmt(ast)].child1;
        assertEq(ast[expr].intValue, 6); // POW
    }

    function testNestedFunctionCall() public {
        ASTNode[] memory ast = _parse("foo(bar(1))\n");
        uint256 outer = ast[_firstStmt(ast)].child1;
        assertEq(ast[outer].strValue, "foo");
        uint256 inner = _exprAux(ast[outer], 0);
        assertEq(ast[inner].strValue, "bar");
    }

    // ==================== FIX-15: Nested function param storage ====================

    function testNestedFuncDefParams() public {
        // Inner function should have 2 params, outer should have 1
        string memory src = "def outer(a):\n    def inner(b, c):\n        return b + c\n    return inner(a, a)\n";
        ASTNode[] memory ast = _parse(src);
        uint256 outerIdx = _firstStmt(ast);
        assertEq(uint256(ast[outerIdx].nodeType), uint256(NodeType.FUNCTION_DEF));
        assertEq(ast[outerIdx].strValue, "outer");
        // outer has 1 param
        assertEq(ast[outerIdx].auxCount, 1);
        // Find inner function def inside outer's body
        uint256 outerBody = ast[outerIdx].child2;
        // inner is the first statement in outer's body
        uint256 innerIdx = _childStmt(ast[outerBody], 0);
        assertEq(uint256(ast[innerIdx].nodeType), uint256(NodeType.FUNCTION_DEF));
        assertEq(ast[innerIdx].strValue, "inner");
        // inner has 2 params
        assertEq(ast[innerIdx].auxCount, 2);
    }

    // ==================== FIX-16: _callArgs reset between Parser uses ====================

    function testParserReuse() public {
        // Reusing the same Parser for two parses should not contaminate the second
        lexer.tokenize("x = 1\n");
        curParser = new Parser();
        ASTNode[] memory ast1 = curParser.parse(lexer);
        assertEq(ast1[0].auxCount, 1, "first parse: 1 statement");

        // Second parse with the same Parser
        lexer.tokenize("y = 2\n");
        ASTNode[] memory ast2 = curParser.parse(lexer);
        assertEq(ast2[0].auxCount, 1, "second parse: 1 statement");
    }

    function testParserReuseWithFunctionCall() public {
        // Function call args use _callArgs — reusing Parser should not leak old args
        lexer.tokenize("foo(1, 2)\n");
        curParser = new Parser();
        curParser.parse(lexer);

        lexer.tokenize("bar(3)\n");
        ASTNode[] memory ast2 = curParser.parse(lexer);
        // bar(3) should have exactly 1 arg
        uint256 callIdx = ast2[_firstStmt(ast2)].child1;
        assertEq(ast2[callIdx].strValue, "bar");
        assertEq(ast2[callIdx].auxCount, 1, "bar should have 1 arg");
    }
}
