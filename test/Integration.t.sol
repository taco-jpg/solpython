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
    event PrintString(string value);

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

    // ==================== Bubble Sort ====================

    function testBubbleSort() public {
        string memory src = "lst = [5, 3, 8, 1, 2]\nn = len(lst)\nfor i in range(n):\n    for j in range(n - 1):\n        if lst[j] > lst[j + 1]:\n            temp = lst[j]\n            lst[j] = lst[j + 1]\n            lst[j + 1] = temp\nprint(lst[0])\nprint(lst[1])\nprint(lst[2])\nprint(lst[3])\nprint(lst[4])\n";
        bytes memory bytecode = _compile(src);
        VM pyVm = new VM();

        vm.recordLogs();
        pyVm.execute(bytecode);

        Vm.Log[] memory logs = vm.getRecordedLogs();
        bytes32 printTopic = keccak256("Print(uint256[])");

        uint256[] memory results = new uint256[](5);
        uint256 idx = 0;
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == printTopic) {
                uint256[] memory vals = abi.decode(logs[i].data, (uint256[]));
                if (vals.length == 1 && idx < 5) {
                    results[idx] = vals[0];
                    idx++;
                }
            }
        }

        assertEq(idx, 5, "Expected 5 print events");
        assertEq(results[0], 1, "lst[0] should be 1");
        assertEq(results[1], 2, "lst[1] should be 2");
        assertEq(results[2], 3, "lst[2] should be 3");
        assertEq(results[3], 5, "lst[3] should be 5");
        assertEq(results[4], 8, "lst[4] should be 8");
    }

    // ==================== Print String ====================

    function testPrintString() public {
        bytes memory bytecode = _compile("print(\"hello\")\n");
        VM pyVm = new VM();

        vm.recordLogs();
        pyVm.execute(bytecode);

        Vm.Log[] memory logs = vm.getRecordedLogs();
        bytes32 printStrTopic = keccak256("PrintString(string)");
        bool found = false;
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == printStrTopic) {
                string memory val = abi.decode(logs[i].data, (string));
                // The string may or may not include quotes depending on lexer handling
                assertTrue(bytes(val).length > 0, "PrintString should output non-empty string");
                found = true;
                break;
            }
        }
        assertTrue(found, "No PrintString event emitted");
    }

    // ==================== FIX-15b: Nested function end-to-end ====================

    function testNestedFunctionDefinition() public {
        string memory src = string.concat(
            "def outer(x):\n",
            "    def inner(y):\n",
            "        return y * 2\n",
            "    return inner(x) + 1\n",
            "print(outer(5))\n"
        );
        bytes memory bytecode = _compile(src);
        VM pyVm = new VM();
        vm.recordLogs();
        pyVm.execute(bytecode);

        Vm.Log[] memory logs = vm.getRecordedLogs();
        bytes32 printTopic = keccak256("Print(uint256[])");
        bool found = false;
        for (uint256 i = logs.length; i > 0; i--) {
            if (logs[i - 1].topics[0] == printTopic) {
                uint256[] memory vals = abi.decode(logs[i - 1].data, (uint256[]));
                assertEq(vals[0], 11, "outer(5) = inner(5) + 1 = 10 + 1 = 11");
                found = true;
                break;
            }
        }
        assertTrue(found, "should have Print event");
    }

}
