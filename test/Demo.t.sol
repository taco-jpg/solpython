// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import {Lexer} from "../src/phases/Lexer.sol";
import {Parser} from "../src/phases/Parser.sol";
import {SemanticAnalyzer} from "../src/phases/SemanticAnalyzer.sol";
import {CodeGenerator} from "../src/phases/CodeGenerator.sol";
import {VM} from "../src/phases/VM.sol";

contract DemoTest is Test {
    event Print(uint256[] values);

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

    function _run(string memory src) internal returns (VM) {
        bytes memory bytecode = _compile(src);
        VM pyVm = new VM();
        pyVm.execute(bytecode);
        return pyVm;
    }

    /// @dev Helper: run Python source, expect a single Print event with value `expected`
    function _runExpectPrint(string memory src, uint256 expected) internal {
        bytes memory bytecode = _compile(src);
        VM pyVm = new VM();

        vm.recordLogs();
        pyVm.execute(bytecode);

        Vm.Log[] memory logs = vm.getRecordedLogs();
        bytes32 printTopic = keccak256("Print(uint256[])");
        bool found = false;
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == printTopic) {
                uint256[] memory vals = abi.decode(logs[i].data, (uint256[]));
                require(vals.length == 1, "Expected 1 print value");
                require(vals[0] == expected, string.concat("Expected ", _toString(expected), " got ", _toString(vals[0])));
                found = true;
                break;
            }
        }
        require(found, "No Print event emitted");
    }

    function _toString(uint256 value) internal pure returns (string memory) {
        if (value == 0) return "0";
        uint256 temp = value;
        uint256 digits;
        while (temp != 0) { digits++; temp /= 10; }
        bytes memory buffer = new bytes(digits);
        while (value != 0) {
            digits--;
            buffer[digits] = bytes1(uint8(48 + value % 10));
            value /= 10;
        }
        return string(buffer);
    }

    // ==================== Hello World ====================

    function testHelloWorld() public {
        _runExpectPrint("print(42)\n", 42);
    }

    // ==================== Arithmetic ====================

    function testArithmetic() public {
        // 3 + 4 * 2 = 11
        _runExpectPrint("x = 3 + 4 * 2\nprint(x)\n", 11);
    }

    function testAugAssign() public {
        // x=10, x+=5 → 15, x-=3 → 12, x*=2 → 24
        _runExpectPrint("x = 10\nx += 5\nx -= 3\nx *= 2\nprint(x)\n", 24);
    }

    // ==================== Control Flow ====================

    function testIfElse() public {
        _runExpectPrint("x = 10\nif x > 5:\n    print(1)\nelse:\n    print(0)\n", 1);
    }

    function testElif() public {
        _runExpectPrint("x = 15\nif x < 10:\n    print(1)\nelif x < 20:\n    print(2)\nelse:\n    print(3)\n", 2);
    }

    function testWhileSum() public {
        // sum 1..100 = 5050
        _runExpectPrint("s = 0\ni = 1\nwhile i <= 100:\n    s += i\n    i += 1\nprint(s)\n", 5050);
    }

    // ==================== Functions ====================

    function testSimpleFunction() public {
        _runExpectPrint("def add(a, b):\n    return a + b\nprint(add(3, 4))\n", 7);
    }

    function testRecursiveFactorial() public {
        _runExpectPrint("def factorial(n):\n    if n <= 1:\n        return 1\n    return n * factorial(n - 1)\nprint(factorial(5))\n", 120);
    }

    function testRecursiveFibonacci() public {
        _runExpectPrint("def fib(n):\n    if n <= 1:\n        return n\n    return fib(n - 1) + fib(n - 2)\nprint(fib(10))\n", 55);
    }

    // ==================== Lists ====================

    function testListAccess() public {
        _runExpectPrint("lst = [10, 20, 30]\nprint(lst[1])\n", 20);
    }

    function testListLen() public {
        _runExpectPrint("print(len([1, 2, 3]))\n", 3);
    }
}
