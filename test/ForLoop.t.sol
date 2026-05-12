// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import {Lexer} from "../src/phases/Lexer.sol";
import {Parser} from "../src/phases/Parser.sol";
import {SemanticAnalyzer} from "../src/phases/SemanticAnalyzer.sol";
import {CodeGenerator} from "../src/phases/CodeGenerator.sol";
import {VM} from "../src/phases/VM.sol";

contract ForLoopTest is Test {
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

    // ==================== range(n) ====================

    function testRangeSum() public {
        // sum 0..9 = 45
        _runExpectPrint("s = 0\nfor i in range(10):\n    s += i\nprint(s)\n", 45);
    }

    function testRangeEmpty() public {
        // range(0) → loop body never executes
        _runExpectPrint("s = 0\nfor i in range(0):\n    s += 1\nprint(s)\n", 0);
    }

    function testRangeOne() public {
        // range(1) → loop runs once with i=0
        _runExpectPrint("s = 0\nfor i in range(1):\n    s += i\nprint(s)\n", 0);
    }

    // ==================== range(start, stop) ====================

    function testRangeStartStop() public {
        // sum 5..9 = 35
        _runExpectPrint("s = 0\nfor i in range(5, 10):\n    s += i\nprint(s)\n", 35);
    }

    function testRangeStartStopEmpty() public {
        // range(10, 5) → empty
        _runExpectPrint("s = 0\nfor i in range(10, 5):\n    s += 1\nprint(s)\n", 0);
    }

    // ==================== range(start, stop, step) ====================

    function testRangeStep() public {
        // sum 0,2,4,6,8 = 20
        _runExpectPrint("s = 0\nfor i in range(0, 10, 2):\n    s += i\nprint(s)\n", 20);
    }

    function testRangeNegativeStep() public {
        // sum 10,8,6,4,2 = 30
        _runExpectPrint("s = 0\nfor i in range(10, 0, -2):\n    s += i\nprint(s)\n", 30);
    }

    // ==================== List iteration ====================

    function testForListLiteral() public {
        // sum [10, 20, 30] = 60
        _runExpectPrint("s = 0\nfor x in [10, 20, 30]:\n    s += x\nprint(s)\n", 60);
    }

    function testForListVariable() public {
        _runExpectPrint("lst = [5, 10, 15]\ns = 0\nfor x in lst:\n    s += x\nprint(s)\n", 30);
    }

    // ==================== Nested loops ====================

    function testNestedForLoop() public {
        // 3x3 grid sum = sum of (i+j) for i in 0..2, j in 0..2 = 0+1+2+1+2+3+2+3+4 = 18
        _runExpectPrint("s = 0\nfor i in range(3):\n    for j in range(3):\n        s += i + j\nprint(s)\n", 18);
    }

    // ==================== Break / Continue ====================

    function testBreak() public {
        // sum 0..4 but break at 3 → sum 0+1+2 = 3
        _runExpectPrint("s = 0\nfor i in range(10):\n    if i == 3:\n        break\n    s += i\nprint(s)\n", 3);
    }

    function testContinue() public {
        // sum 0..9 but skip 5 → 45 - 5 = 40
        _runExpectPrint("s = 0\nfor i in range(10):\n    if i == 5:\n        continue\n    s += i\nprint(s)\n", 40);
    }

    // ==================== For loop with function ====================

    function testForLoopWithFunction() public {
        string memory src = "def double(x):\n    return x * 2\ns = 0\nfor i in range(5):\n    s += double(i)\nprint(s)\n";
        // double(0)+double(1)+...+double(4) = 0+2+4+6+8 = 20
        _runExpectPrint(src, 20);
    }
}
