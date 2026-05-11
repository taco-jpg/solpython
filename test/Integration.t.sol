// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import {Lexer} from "../src/phases/Lexer.sol";
import {Parser} from "../src/phases/Parser.sol";
import {SemanticAnalyzer} from "../src/phases/SemanticAnalyzer.sol";
import {CodeGenerator} from "../src/phases/CodeGenerator.sol";
import {VM} from "../src/phases/VM.sol";

contract IntegrationTest is Test {
    event Print(uint256[] values);
    event Result(uint256 value);

    function _compile(string memory src) internal returns (bytes memory) {
        Lexer lexer = new Lexer();
        lexer.tokenize(src);
        Parser parser = new Parser();
        parser.parse(lexer);
        SemanticAnalyzer analyzer = new SemanticAnalyzer();
        analyzer.analyze(parser);
        CodeGenerator gen = new CodeGenerator();
        return gen.generate(parser);
    }

    function _run(string memory src) internal {
        bytes memory bytecode = _compile(src);
        VM pyVm = new VM();
        pyVm.execute(bytecode);
    }

    // ==================== Hello World ====================

    function testHelloWorld() public {
        _run("print(42)\n");
    }

    function testPrintMultiple() public {
        _run("print(1)\nprint(2)\nprint(3)\n");
    }

    // ==================== Arithmetic ====================

    function testSimpleArithmetic() public {
        _run("x = 1 + 2\n");
    }

    function testNestedArithmetic() public {
        _run("x = (1 + 2) * 3\n");
    }

    function testAugAssign() public {
        _run("x = 10\nx += 5\nx -= 3\nx *= 2\n");
    }

    // ==================== Control Flow ====================

    function testIfElse() public {
        _run("x = 10\nif x > 5:\n    y = 1\nelse:\n    y = 0\n");
    }

    function testElif() public {
        _run("x = 15\nif x < 10:\n    y = 1\nelif x < 20:\n    y = 2\nelse:\n    y = 3\n");
    }

    function testWhileLoop() public {
        _run("x = 0\nwhile x < 10:\n    x += 1\n");
    }

    // ==================== Functions ====================

    function testSimpleFunction() public {
        _run("def add(a, b):\n    return a + b\nresult = add(3, 4)\n");
    }

    function testRecursiveFactorial() public {
        string memory src = "def factorial(n):\n    if n <= 1:\n        return 1\n    return n * factorial(n - 1)\nresult = factorial(5)\n";
        _run(src);
    }

    function testRecursiveFibonacci() public {
        string memory src = "def fib(n):\n    if n <= 1:\n        return n\n    return fib(n - 1) + fib(n - 2)\nresult = fib(7)\n";
        _run(src);
    }

    // ==================== Lists ====================

    function testListCreateAndAccess() public {
        _run("lst = [1, 2, 3]\nx = lst[0]\n");
    }

    function testListLength() public {
        _run("lst = [1, 2, 3]\nn = len(lst)\n");
    }

    // ==================== Bytecode Verification ====================

    function testCompileProducesValidBytecode() public {
        bytes memory bc = _compile("x = 1\n");
        assertTrue(bc.length > 7);
        assertEq(uint8(bc[0]), 0x50); // P
        assertEq(uint8(bc[1]), 0x59); // Y
        assertEq(uint8(bc[2]), 0x01); // version
    }

    function testEndToEndFibonacci() public {
        string memory src = "def fib(n):\n    if n <= 1:\n        return n\n    return fib(n - 1) + fib(n - 2)\nresult = fib(10)\n";
        bytes memory bytecode = _compile(src);
        VM pyVm = new VM();
        pyVm.execute(bytecode);
        // fib(10) = 55 — verify it completed without error
        assertEq(pyVm.getStackLength(), 0);
    }
}
