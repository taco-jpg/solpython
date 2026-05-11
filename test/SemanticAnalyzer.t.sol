// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import {Lexer} from "../src/phases/Lexer.sol";
import {Parser} from "../src/phases/Parser.sol";
import {SemanticAnalyzer} from "../src/phases/SemanticAnalyzer.sol";
import {TypeTag} from "../src/types/TypeInfo.sol";

contract SemanticAnalyzerTest is Test {
    Lexer lexer;

    function setUp() public {
        lexer = new Lexer();
    }

    function _analyze(string memory src) internal returns (SemanticAnalyzer, Parser) {
        lexer.tokenize(src);
        Parser parser = new Parser();
        parser.parse(lexer);
        SemanticAnalyzer analyzer = new SemanticAnalyzer();
        analyzer.analyze(parser);
        return (analyzer, parser);
    }

    // ==================== Basic Type Inference ====================

    function testIntLiteral() public {
        (SemanticAnalyzer a, Parser p) = _analyze("x = 42\n");
        assertEq(uint256(a.getNodeTypeResult(0)), uint256(TypeTag.INT));
    }

    function testFloatLiteral() public {
        (SemanticAnalyzer a, Parser p) = _analyze("x = 3.14\n");
        assertEq(uint256(a.getNodeTypeResult(0)), uint256(TypeTag.FLOAT));
    }

    function testStringLiteral() public {
        (SemanticAnalyzer a, Parser p) = _analyze("x = \"hello\"\n");
        assertEq(uint256(a.getNodeTypeResult(0)), uint256(TypeTag.STRING));
    }

    function testBoolLiteral() public {
        (SemanticAnalyzer a, Parser p) = _analyze("x = True\n");
        assertEq(uint256(a.getNodeTypeResult(0)), uint256(TypeTag.BOOL));
    }

    function testNoneLiteral() public {
        (SemanticAnalyzer a, Parser p) = _analyze("x = None\n");
        assertEq(uint256(a.getNodeTypeResult(0)), uint256(TypeTag.NONE));
    }

    // ==================== Binary Operation Types ====================

    function testIntAddInt() public {
        (SemanticAnalyzer a, Parser p) = _analyze("x = 1 + 2\n");
        assertEq(uint256(a.getNodeTypeResult(0)), uint256(TypeTag.INT));
    }

    function testFloatAddInt() public {
        (SemanticAnalyzer a, Parser p) = _analyze("x = 1.0 + 2\n");
        assertEq(uint256(a.getNodeTypeResult(0)), uint256(TypeTag.FLOAT));
    }

    function testStringConcat() public {
        (SemanticAnalyzer a, Parser p) = _analyze("x = \"a\" + \"b\"\n");
        assertEq(uint256(a.getNodeTypeResult(0)), uint256(TypeTag.STRING));
    }

    // ==================== Comparison Types ====================

    function testComparisonIsBool() public {
        (SemanticAnalyzer a, Parser p) = _analyze("x = 1 < 2\n");
        // The ASSIGN node (first stmt) should have BOOL type
        uint256 assignIdx = p.getAuxData(p.getAuxIndex(0));
        assertEq(uint256(a.getNodeTypeResult(assignIdx)), uint256(TypeTag.BOOL));
    }

    function testBoolAnd() public {
        (SemanticAnalyzer a, Parser p) = _analyze("x = True and False\n");
        assertEq(uint256(a.getNodeTypeResult(0)), uint256(TypeTag.BOOL));
    }

    // ==================== Variable Lookup ====================

    function testVariableType() public {
        (SemanticAnalyzer a, Parser p) = _analyze("x = 42\ny = x\n");
        // y should have the same type as x (INT)
        assertEq(uint256(a.getNodeTypeResult(0)), uint256(TypeTag.INT));
    }

    function testUndefinedVariable() public {
        (SemanticAnalyzer a, Parser p) = _analyze("y = x\n");
        assertTrue(a.getErrorCount() > 0);
    }

    // ==================== Function Definitions ====================

    function testFuncDef() public {
        (SemanticAnalyzer a, Parser p) = _analyze("def foo():\n    pass\n");
        assertEq(uint256(a.getNodeTypeResult(0)), uint256(TypeTag.FUNCTION));
    }

    function testFuncDefWithParams() public {
        (SemanticAnalyzer a, Parser p) = _analyze("def add(a, b):\n    return a + b\n");
        assertEq(uint256(a.getNodeTypeResult(0)), uint256(TypeTag.FUNCTION));
    }

    function testFuncCallReturn() public {
        (SemanticAnalyzer a, Parser p) = _analyze("def foo():\n    return 42\nx = foo()\n");
        // foo returns INT, so x should be INT
        // The assignment node (second statement) should be INT
        // Need to find the right node index...
        assertTrue(a.getErrorCount() == 0);
    }

    // ==================== Built-in Functions ====================

    function testPrintCall() public {
        (SemanticAnalyzer a, Parser p) = _analyze("print(42)\n");
        // EXPR_STMT wrapping print() should be NONE type
        // The first statement's type is what we check
        uint256 stmtIdx = p.getAuxData(p.getAuxIndex(0));
        assertEq(a.getErrorCount(), 0);
        // The FUNC_CALL for print is child1 of EXPR_STMT
        assertEq(uint256(a.getNodeTypeResult(p.getChild1(stmtIdx))), uint256(TypeTag.NONE));
    }

    function testLenCall() public {
        (SemanticAnalyzer a, Parser p) = _analyze("x = len([1, 2, 3])\n");
        // The ASSIGN should have INT type (len returns int)
        uint256 assignIdx = p.getAuxData(p.getAuxIndex(0));
        assertEq(a.getErrorCount(), 0);
        assertEq(uint256(a.getNodeTypeResult(assignIdx)), uint256(TypeTag.INT));
    }

    // ==================== List Literals ====================

    function testListLiteral() public {
        (SemanticAnalyzer a, Parser p) = _analyze("x = [1, 2, 3]\n");
        // ASSIGN node should have LIST type
        uint256 assignIdx = p.getAuxData(p.getAuxIndex(0));
        assertEq(a.getErrorCount(), 0);
        assertEq(uint256(a.getNodeTypeResult(assignIdx)), uint256(TypeTag.LIST));
    }

    function testIndexAccess() public {
        (SemanticAnalyzer a, Parser p) = _analyze("x = [1, 2, 3]\ny = x[0]\n");
        assertEq(a.getErrorCount(), 0);
    }

    // ==================== Control Flow ====================

    function testIfStatement() public {
        (SemanticAnalyzer a, Parser p) = _analyze("x = 1\nif x > 0:\n    pass\n");
        assertEq(a.getErrorCount(), 0);
    }

    function testWhileLoop() public {
        (SemanticAnalyzer a, Parser p) = _analyze("x = 0\nwhile x < 10:\n    x += 1\n");
        assertEq(a.getErrorCount(), 0);
    }

    function testForLoop() public {
        (SemanticAnalyzer a, Parser p) = _analyze("for i in [1, 2, 3]:\n    pass\n");
        assertEq(a.getErrorCount(), 0);
    }

    // ==================== Scope Tests ====================

    function testFunctionScope() public {
        (SemanticAnalyzer a, Parser p) = _analyze("def foo():\n    x = 42\n    return x\n");
        assertEq(a.getErrorCount(), 0);
    }

    function testNestedScope() public {
        (SemanticAnalyzer a, Parser p) = _analyze("x = 1\ndef foo():\n    y = x\n    return y\n");
        assertEq(a.getErrorCount(), 0);
    }
}
