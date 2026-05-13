// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import {Lexer} from "../src/phases/Lexer.sol";
import {Parser} from "../src/phases/Parser.sol";
import {SemanticAnalyzer} from "../src/phases/SemanticAnalyzer.sol";
import {CodeGenerator} from "../src/phases/CodeGenerator.sol";
import {VM} from "../src/phases/VM.sol";

contract MapFilterTest is Test {
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

    function _getPrints() internal returns (uint256[] memory) {
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bytes32 printTopic = keccak256("Print(uint256[])");
        uint256 count = 0;
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == printTopic) count++;
        }
        uint256[] memory result = new uint256[](count);
        uint256 idx = 0;
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == printTopic) {
                uint256[] memory vals = abi.decode(logs[i].data, (uint256[]));
                result[idx] = vals[0];
                idx++;
            }
        }
        return result;
    }

    // ==================== map ====================

    function testMapDouble() public {
        string memory src = string.concat(
            "def double(x):\n",
            "    return x * 2\n",
            "result = map(double, [1, 2, 3])\n",
            "print(len(result))\n",
            "print(result[0])\n",
            "print(result[1])\n",
            "print(result[2])\n"
        );
        bytes memory bytecode = _compile(src);
        VM pyVm = new VM();
        vm.recordLogs();
        pyVm.execute(bytecode);
        uint256[] memory p = _getPrints();
        assertEq(p.length, 4, "4 prints");
        assertEq(p[0], 3, "len(result) = 3");
        assertEq(p[1], 2, "result[0] = 2");
        assertEq(p[2], 4, "result[1] = 4");
        assertEq(p[3], 6, "result[2] = 6");
    }

    function testMapSquare() public {
        string memory src = string.concat(
            "def square(x):\n",
            "    return x * x\n",
            "result = map(square, [4, 5, 6])\n",
            "print(result[0])\n",
            "print(result[1])\n",
            "print(result[2])\n"
        );
        bytes memory bytecode = _compile(src);
        VM pyVm = new VM();
        vm.recordLogs();
        pyVm.execute(bytecode);
        uint256[] memory p = _getPrints();
        assertEq(p[0], 16, "4*4=16");
        assertEq(p[1], 25, "5*5=25");
        assertEq(p[2], 36, "6*6=36");
    }

    function testMapEmpty() public {
        string memory src = string.concat(
            "def double(x):\n",
            "    return x * 2\n",
            "result = map(double, [])\n",
            "print(len(result))\n"
        );
        bytes memory bytecode = _compile(src);
        VM pyVm = new VM();
        vm.recordLogs();
        pyVm.execute(bytecode);
        uint256[] memory p = _getPrints();
        assertEq(p[0], 0, "map on empty list = empty");
    }

    function testMapSingle() public {
        string memory src = string.concat(
            "def inc(x):\n",
            "    return x + 1\n",
            "result = map(inc, [10])\n",
            "print(result[0])\n"
        );
        bytes memory bytecode = _compile(src);
        VM pyVm = new VM();
        vm.recordLogs();
        pyVm.execute(bytecode);
        uint256[] memory p = _getPrints();
        assertEq(p[0], 11, "10+1=11");
    }

    // ==================== filter ====================

    function testFilterPositive() public {
        string memory src = string.concat(
            "def is_positive(x):\n",
            "    return x > 0\n",
            "result = filter(is_positive, [0, 2, 0, 4])\n",
            "print(len(result))\n",
            "print(result[0])\n",
            "print(result[1])\n"
        );
        bytes memory bytecode = _compile(src);
        VM pyVm = new VM();
        vm.recordLogs();
        pyVm.execute(bytecode);
        uint256[] memory p = _getPrints();
        assertEq(p[0], 2, "2 positive numbers");
        assertEq(p[1], 2, "result[0] = 2");
        assertEq(p[2], 4, "result[1] = 4");
    }

    function testFilterEven() public {
        string memory src = string.concat(
            "def is_even(x):\n",
            "    return x - x // 2 * 2 == 0\n",
            "result = filter(is_even, [1, 2, 3, 4, 5, 6])\n",
            "print(len(result))\n",
            "print(result[0])\n",
            "print(result[1])\n",
            "print(result[2])\n"
        );
        bytes memory bytecode = _compile(src);
        VM pyVm = new VM();
        vm.recordLogs();
        pyVm.execute(bytecode);
        uint256[] memory p = _getPrints();
        assertEq(p[0], 3, "3 even numbers");
        assertEq(p[1], 2, "result[0] = 2");
        assertEq(p[2], 4, "result[1] = 4");
        assertEq(p[3], 6, "result[2] = 6");
    }

    function testFilterEmpty() public {
        string memory src = string.concat(
            "def always_false(x):\n",
            "    return 0\n",
            "result = filter(always_false, [1, 2, 3])\n",
            "print(len(result))\n"
        );
        bytes memory bytecode = _compile(src);
        VM pyVm = new VM();
        vm.recordLogs();
        pyVm.execute(bytecode);
        uint256[] memory p = _getPrints();
        assertEq(p[0], 0, "filter all = empty");
    }

    function testFilterAll() public {
        string memory src = string.concat(
            "def always_true(x):\n",
            "    return 1\n",
            "result = filter(always_true, [1, 2, 3])\n",
            "print(len(result))\n"
        );
        bytes memory bytecode = _compile(src);
        VM pyVm = new VM();
        vm.recordLogs();
        pyVm.execute(bytecode);
        uint256[] memory p = _getPrints();
        assertEq(p[0], 3, "filter none = all");
    }
}
