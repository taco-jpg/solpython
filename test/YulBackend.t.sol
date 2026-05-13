// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import {Lexer} from "../src/phases/Lexer.sol";
import {Parser} from "../src/phases/Parser.sol";
import {SemanticAnalyzer} from "../src/phases/SemanticAnalyzer.sol";
import {YulBackend} from "../src/phases/YulBackend.sol";
import {PythonCompiler} from "../src/PythonCompiler.sol";

contract YulBackendTest is Test {
    function _toYul(string memory source) internal returns (string memory) {
        Lexer lexer = new Lexer();
        lexer.tokenize(source);
        Parser parser = new Parser();
        parser.parse(lexer);
        SemanticAnalyzer analyzer = new SemanticAnalyzer();
        analyzer.analyze(parser);
        YulBackend backend = new YulBackend();
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

    // ==================== Structure ====================

    function testObjectHeader() public {
        string memory out = _toYul("x = 1\n");
        assertTrue(_contains(out, "object \"Transpiled\""), "missing object header");
        assertTrue(_contains(out, "code {"), "missing code block");
        assertTrue(_contains(out, "stop()"), "missing stop");
    }

    // ==================== Variables ====================

    function testSimpleAssignment() public {
        string memory out = _toYul("x = 42\n");
        assertTrue(_contains(out, "let x := 42"), "missing let assignment");
    }

    function testReassignment() public {
        string memory out = _toYul("x = 1\nx = 2\n");
        assertTrue(_contains(out, "let x := 1"), "missing first assignment");
        assertTrue(_contains(out, "x := 2"), "missing reassignment");
    }

    // ==================== Arithmetic ====================

    function testAdd() public {
        string memory out = _toYul("x = 1 + 2\n");
        assertTrue(_contains(out, "add(1, 2)"), "missing add");
    }

    function testSub() public {
        string memory out = _toYul("x = 5 - 3\n");
        assertTrue(_contains(out, "sub(5, 3)"), "missing sub");
    }

    function testMul() public {
        string memory out = _toYul("x = 2 * 3\n");
        assertTrue(_contains(out, "mul(2, 3)"), "missing mul");
    }

    function testDiv() public {
        string memory out = _toYul("x = 10 / 2\n");
        assertTrue(_contains(out, "div(10, 2)"), "missing div");
    }

    function testMod() public {
        string memory out = _toYul("x = 10 % 3\n");
        assertTrue(_contains(out, "mod(10, 3)"), "missing mod");
    }

    function testExp() public {
        string memory out = _toYul("x = 2 ** 3\n");
        assertTrue(_contains(out, "exp(2, 3)"), "missing exp");
    }

    function testUnaryNeg() public {
        string memory out = _toYul("x = -5\n");
        assertTrue(_contains(out, "sub(0, 5)"), "missing neg");
    }

    function testAugAssign() public {
        string memory out = _toYul("x = 0\nx += 1\n");
        assertTrue(_contains(out, "x := add(x, 1)"), "missing aug assign");
    }

    // ==================== Comparisons ====================

    function testEq() public {
        string memory out = _toYul("x = 1 == 2\n");
        assertTrue(_contains(out, "eq(1, 2)"), "missing eq");
    }

    function testLt() public {
        string memory out = _toYul("x = 1 < 2\n");
        assertTrue(_contains(out, "lt(1, 2)"), "missing lt");
    }

    function testGt() public {
        string memory out = _toYul("x = 1 > 2\n");
        assertTrue(_contains(out, "gt(1, 2)"), "missing gt");
    }

    function testNeq() public {
        string memory out = _toYul("x = 1 != 2\n");
        assertTrue(_contains(out, "iszero(eq(1, 2))"), "missing neq");
    }

    function testLte() public {
        string memory out = _toYul("x = 1 <= 2\n");
        assertTrue(_contains(out, "iszero(gt(1, 2))"), "missing lte");
    }

    function testGte() public {
        string memory out = _toYul("x = 1 >= 2\n");
        assertTrue(_contains(out, "iszero(lt(1, 2))"), "missing gte");
    }

    // ==================== Boolean Logic ====================

    function testBoolAnd() public {
        string memory out = _toYul("x = True and False\n");
        assertTrue(_contains(out, "and(1, 0)"), "missing and");
    }

    function testBoolOr() public {
        string memory out = _toYul("x = True or False\n");
        assertTrue(_contains(out, "or(1, 0)"), "missing or");
    }

    function testBoolNot() public {
        string memory out = _toYul("x = not True\n");
        assertTrue(_contains(out, "iszero(1)"), "missing not");
    }

    // ==================== Control Flow ====================

    function testIfStatement() public {
        string memory out = _toYul("x = 1\nif x > 0:\n    x = 2\n");
        assertTrue(_contains(out, "if gt(x, 0)"), "missing if");
        assertTrue(_contains(out, "x := 2"), "missing if body");
    }

    function testIfElse() public {
        string memory out = _toYul("x = 1\nif x > 0:\n    x = 2\nelse:\n    x = 3\n");
        assertTrue(_contains(out, "} {"), "missing else");
    }

    function testWhileLoop() public {
        string memory out = _toYul("x = 0\nwhile x < 10:\n    x += 1\n");
        assertTrue(_contains(out, "for { } lt(x, 10)"), "missing while");
    }

    function testForRange() public {
        string memory out = _toYul("s = 0\nfor i in range(10):\n    s += i\n");
        assertTrue(_contains(out, "for {"), "missing for");
    }

    // ==================== Functions ====================

    function testFunctionDef() public {
        string memory out = _toYul("def add(a, b):\n    return a + b\nx = add(1, 2)\n");
        assertTrue(_contains(out, "function add(a, b) -> result"), "missing function");
        assertTrue(_contains(out, "result := add(a, b)"), "missing return");
    }

    function testFunctionCall() public {
        string memory out = _toYul("def double(x):\n    return x * 2\ny = double(5)\n");
        assertTrue(_contains(out, "double(5)"), "missing function call");
    }

    // ==================== Lists ====================

    function testListLiteral() public {
        string memory out = _toYul("x = [1, 2, 3]\n");
        assertTrue(_contains(out, "mstore("), "missing mstore for list");
    }

    function testIndexAccess() public {
        string memory out = _toYul("x = [1, 2, 3]\ny = x[0]\n");
        assertTrue(_contains(out, "mload(add(x"), "missing index access");
    }

    // ==================== Literals ====================

    function testBoolLiteral() public {
        string memory out = _toYul("x = True\ny = False\n");
        assertTrue(_contains(out, "let x := 1"), "missing True");
        assertTrue(_contains(out, "let y := 0"), "missing False");
    }

    function testNoneLiteral() public {
        string memory out = _toYul("x = None\n");
        assertTrue(_contains(out, "let x := 0"), "None should be 0");
    }

    // ==================== Integration ====================

    function testCompilerIntegration() public {
        PythonCompiler compiler = new PythonCompiler();
        string memory out = compiler.compileToYul("x = 42\nprint(x)\n");
        assertTrue(_contains(out, "object \"Transpiled\""), "missing object");
        assertTrue(_contains(out, "let x := 42"), "missing assignment");
    }

    function testEmptyProgram() public {
        string memory out = _toYul("");
        assertTrue(_contains(out, "object \"Transpiled\""), "missing object for empty");
    }

    function testPassStatement() public {
        string memory out = _toYul("if True:\n    pass\n");
        assertTrue(_contains(out, "if 1"), "missing if");
    }

    // ==================== FIX-12b: Structural Validation ====================

    function _balancedBraces(string memory s) internal pure returns (bool) {
        uint256 depth = 0;
        bytes memory b = bytes(s);
        for (uint256 i = 0; i < b.length; i++) {
            if (b[i] == "{") depth++;
            if (b[i] == "}") {
                if (depth == 0) return false;
                depth--;
            }
        }
        return depth == 0;
    }

    function testBracesBalanced() public {
        string memory src = "x = 1\nif x > 0:\n    x = 2\nelse:\n    x = 3\n";
        string memory out = _toYul(src);
        assertTrue(_balancedBraces(out), "braces should be balanced");
    }

    function testBracesBalancedWithLoop() public {
        string memory src = "s = 0\nfor i in range(10):\n    s = s + i\nprint(s)\n";
        string memory out = _toYul(src);
        assertTrue(_balancedBraces(out), "braces should be balanced with loop");
    }

    function testBracesBalancedWithFunction() public {
        string memory src = "def fib(n):\n    if n <= 1:\n        return n\n    return fib(n - 1) + fib(n - 2)\nx = fib(10)\n";
        string memory out = _toYul(src);
        assertTrue(_balancedBraces(out), "braces should be balanced with function");
    }

    function testOutputNotEmpty() public {
        string[] memory programs = new string[](5);
        programs[0] = "x = 42\n";
        programs[1] = "x = 1\ny = 2\nz = x + y\n";
        programs[2] = "for i in range(5):\n    print(i)\n";
        programs[3] = "def add(a, b):\n    return a + b\nx = add(1, 2)\n";
        programs[4] = "x = 1\nif x > 0:\n    x = 2\nelif x == 0:\n    x = 3\nelse:\n    x = 4\n";
        for (uint256 i = 0; i < programs.length; i++) {
            string memory out = _toYul(programs[i]);
            assertTrue(bytes(out).length > 50, "output should be non-trivial");
            assertTrue(_balancedBraces(out), "braces should be balanced");
            assertTrue(_contains(out, "object \"Transpiled\""), "should have object header");
            assertTrue(_contains(out, "code {"), "should have code block");
        }
    }

    function testFunctionInsideCodeBlock() public {
        string memory out = _toYul("def add(a, b):\n    return a + b\nx = add(1, 2)\n");
        // Function definition should appear inside the code block, not outside the object
        assertTrue(_contains(out, "function add(a, b) -> result"), "missing function def");
        assertTrue(_contains(out, "code {"), "missing code block");
        assertTrue(_balancedBraces(out), "braces should be balanced");
    }
}
