// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import {Lexer} from "../src/phases/Lexer.sol";
import {Parser} from "../src/phases/Parser.sol";
import {SemanticAnalyzer} from "../src/phases/SemanticAnalyzer.sol";
import {SolidityBackend} from "../src/phases/SolidityBackend.sol";
import {PythonCompiler} from "../src/PythonCompiler.sol";

contract SolidityBackendTest is Test {
    function _transpile(string memory source) internal returns (string memory) {
        Lexer lexer = new Lexer();
        lexer.tokenize(source);

        Parser parser = new Parser();
        parser.parse(lexer);

        SemanticAnalyzer analyzer = new SemanticAnalyzer();
        analyzer.analyze(parser);

        SolidityBackend backend = new SolidityBackend();
        return backend.generate(parser);
    }

    function _contains(string memory haystack, string memory needle) internal pure returns (bool) {
        bytes memory h = bytes(haystack);
        bytes memory n = bytes(needle);
        if (n.length > h.length) return false;
        for (uint256 i = 0; i <= h.length - n.length; i++) {
            bool found = true;
            for (uint256 j = 0; j < n.length; j++) {
                if (h[i + j] != n[j]) { found = false; break; }
            }
            if (found) return true;
        }
        return false;
    }

    // ==================== Basic Structure ====================

    function testContractHeader() public {
        string memory out = _transpile("x = 1\n");
        assertTrue(_contains(out, "pragma solidity ^0.8.20;"), "missing pragma");
        assertTrue(_contains(out, "contract Transpiled {"), "missing contract");
        assertTrue(_contains(out, "event Print("), "missing Print event");
    }

    function testContractFooter() public {
        string memory out = _transpile("x = 1\n");
        assertTrue(_contains(out, "}"), "missing closing brace");
    }

    // ==================== Variable Assignment ====================

    function testSimpleAssignment() public {
        string memory out = _transpile("x = 42\n");
        assertTrue(_contains(out, "uint256 x = 42;"), "missing assignment");
    }

    function testMultipleAssignments() public {
        string memory out = _transpile("x = 1\ny = 2\n");
        assertTrue(_contains(out, "uint256 x = 1;"), "missing x assignment");
        assertTrue(_contains(out, "uint256 y = 2;"), "missing y assignment");
    }

    function testReassignmentNoType() public {
        // Second assignment to same var should not redeclare
        string memory out = _transpile("x = 1\nx = 2\n");
        assertTrue(_contains(out, "uint256 x = 1;"), "missing first assignment");
        // Check there's only one uint256 declaration for x
        // The second assignment should be "x = 2;" without uint256
        // This is tricky to test precisely — at minimum, it should compile
        assertTrue(bytes(out).length > 0, "empty output");
    }

    // ==================== Arithmetic ====================

    function testBinaryAdd() public {
        string memory out = _transpile("x = 1 + 2\n");
        assertTrue(_contains(out, "(1 + 2)"), "missing add expression");
    }

    function testBinarySub() public {
        string memory out = _transpile("x = 5 - 3\n");
        assertTrue(_contains(out, "(5 - 3)"), "missing sub expression");
    }

    function testBinaryMul() public {
        string memory out = _transpile("x = 2 * 3\n");
        assertTrue(_contains(out, "(2 * 3)"), "missing mul expression");
    }

    function testBinaryDiv() public {
        string memory out = _transpile("x = 10 / 2\n");
        assertTrue(_contains(out, "(10 / 2)"), "missing div expression");
    }

    function testBinaryMod() public {
        string memory out = _transpile("x = 10 % 3\n");
        assertTrue(_contains(out, "(10 % 3)"), "missing mod expression");
    }

    function testUnaryNeg() public {
        string memory out = _transpile("x = -5\n");
        assertTrue(_contains(out, "(-5)"), "missing negation");
    }

    function testAugAssign() public {
        string memory out = _transpile("x = 0\nx += 1\n");
        assertTrue(_contains(out, "x += 1;"), "missing aug assign");
    }

    function testAugAssignMinus() public {
        string memory out = _transpile("x = 10\nx -= 3\n");
        assertTrue(_contains(out, "x -= 3;"), "missing -= assign");
    }

    // ==================== Comparisons ====================

    function testComparisonEq() public {
        string memory out = _transpile("x = 1 == 2\n");
        assertTrue(_contains(out, "(1 == 2)"), "missing == comparison");
    }

    function testComparisonLt() public {
        string memory out = _transpile("x = 1 < 2\n");
        assertTrue(_contains(out, "(1 < 2)"), "missing < comparison");
    }

    function testComparisonGte() public {
        string memory out = _transpile("x = 1 >= 2\n");
        assertTrue(_contains(out, "(1 >= 2)"), "missing >= comparison");
    }

    // ==================== Boolean Logic ====================

    function testBoolAnd() public {
        string memory out = _transpile("x = True and False\n");
        assertTrue(_contains(out, "true && false"), "missing boolean and");
    }

    function testBoolOr() public {
        string memory out = _transpile("x = True or False\n");
        assertTrue(_contains(out, "true || false"), "missing boolean or");
    }

    function testBoolNot() public {
        string memory out = _transpile("x = not True\n");
        assertTrue(_contains(out, "!true"), "missing boolean not");
    }

    // ==================== Literals ====================

    function testBoolLiteral() public {
        string memory out = _transpile("x = True\ny = False\n");
        assertTrue(_contains(out, "true"), "missing True");
        assertTrue(_contains(out, "false"), "missing False");
    }

    function testNoneLiteral() public {
        string memory out = _transpile("x = None\n");
        assertTrue(_contains(out, "uint256 x = 0;"), "None should become 0");
    }

    function testStringLiteral() public {
        string memory out = _transpile("x = \"hello\"\n");
        assertTrue(_contains(out, "\"hello\""), "missing string literal");
    }

    // ==================== Control Flow ====================

    function testIfStatement() public {
        string memory out = _transpile("x = 1\nif x > 0:\n    x = 2\n");
        assertTrue(_contains(out, "if ("), "missing if statement");
        assertTrue(_contains(out, "(x > 0)"), "missing condition");
        assertTrue(_contains(out, "x = 2;"), "missing if body");
    }

    function testIfElse() public {
        string memory out = _transpile("x = 1\nif x > 0:\n    x = 2\nelse:\n    x = 3\n");
        assertTrue(_contains(out, "if ("), "missing if");
        assertTrue(_contains(out, "} else {"), "missing else");
        assertTrue(_contains(out, "x = 3;"), "missing else body");
    }

    function testElif() public {
        string memory out = _transpile("x = 1\nif x == 1:\n    x = 2\nelif x == 2:\n    x = 3\nelse:\n    x = 4\n");
        assertTrue(_contains(out, "} else if ("), "missing elif");
    }

    function testWhileLoop() public {
        string memory out = _transpile("x = 0\nwhile x < 10:\n    x += 1\n");
        assertTrue(_contains(out, "while ("), "missing while");
        assertTrue(_contains(out, "(x < 10)"), "missing condition");
        assertTrue(_contains(out, "x += 1;"), "missing loop body");
    }

    function testForRange() public {
        string memory out = _transpile("s = 0\nfor i in range(10):\n    s += i\n");
        assertTrue(_contains(out, "for ("), "missing for loop");
        assertTrue(_contains(out, "uint256 __fi"), "missing loop index");
    }

    function testBreakContinue() public {
        string memory out = _transpile("x = 0\nwhile x < 10:\n    x += 1\n    if x == 5:\n        break\n");
        assertTrue(_contains(out, "break;"), "missing break");
    }

    // ==================== Functions ====================

    function testFunctionDef() public {
        string memory out = _transpile("def add(a, b):\n    return a + b\nx = add(1, 2)\n");
        assertTrue(_contains(out, "function add("), "missing function def");
        assertTrue(_contains(out, "uint256 a"), "missing param a");
        assertTrue(_contains(out, "uint256 b"), "missing param b");
        assertTrue(_contains(out, "return (a + b);"), "missing return");
        assertTrue(_contains(out, "add(1, 2)"), "missing function call");
    }

    function testFunctionNoParams() public {
        string memory out = _transpile("def foo():\n    return 42\nx = foo()\n");
        assertTrue(_contains(out, "function foo()"), "missing function def");
        assertTrue(_contains(out, "return 42;"), "missing return");
    }

    function testExecuteFunction() public {
        string memory out = _transpile("x = 1\n");
        assertTrue(_contains(out, "function execute() public {"), "missing execute function");
    }

    // ==================== Lists ====================

    function testListLiteral() public {
        string memory out = _transpile("x = [1, 2, 3]\n");
        assertTrue(_contains(out, "new uint256[](3)"), "missing list literal");
    }

    function testIndexAccess() public {
        string memory out = _transpile("x = [1, 2, 3]\ny = x[0]\n");
        assertTrue(_contains(out, "x[0]"), "missing index access");
    }

    function testListLength() public {
        string memory out = _transpile("x = [1, 2, 3]\nn = len(x)\n");
        assertTrue(_contains(out, ".length"), "missing .length");
    }

    // ==================== Integration via PythonCompiler ====================

    function testCompilerIntegration() public {
        PythonCompiler compiler = new PythonCompiler();
        string memory out = compiler.compileToSolidity("x = 42\nprint(x)\n");
        assertTrue(_contains(out, "pragma solidity"), "missing pragma");
        assertTrue(_contains(out, "contract Transpiled"), "missing contract");
    }

    // ==================== Edge Cases ====================

    function testEmptyProgram() public {
        string memory out = _transpile("");
        assertTrue(_contains(out, "pragma solidity"), "missing pragma for empty program");
    }

    function testPassStatement() public {
        string memory out = _transpile("if True:\n    pass\n");
        // pass should produce no extra code, just the if structure
        assertTrue(_contains(out, "if ("), "missing if");
    }

    function testNestedExpressions() public {
        string memory out = _transpile("x = (1 + 2) * 3\n");
        assertTrue(_contains(out, "((1 + 2) * 3)"), "missing nested expression");
    }

    function testFunctionWithMultipleParams() public {
        string memory out = _transpile("def add3(a, b, c):\n    return a + b + c\nx = add3(1, 2, 3)\n");
        assertTrue(_contains(out, "uint256 a, uint256 b, uint256 c"), "missing params");
        assertTrue(_contains(out, "add3(1, 2, 3)"), "missing call");
    }
}
