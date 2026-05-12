// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import {Lexer} from "../src/phases/Lexer.sol";
import {Parser} from "../src/phases/Parser.sol";
import {SemanticAnalyzer} from "../src/phases/SemanticAnalyzer.sol";
import {CodeGenerator} from "../src/phases/CodeGenerator.sol";
import {VM} from "../src/phases/VM.sol";

contract NegativeIndexTest is Test {
    event Print(uint256[] values);
    event PrintString(string value);
    event VMError(string message, uint256 pc);

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

    function _getLastPrint() internal returns (uint256) {
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bytes32 printTopic = keccak256("Print(uint256[])");
        for (uint256 i = logs.length; i > 0; i--) {
            if (logs[i - 1].topics[0] == printTopic) {
                uint256[] memory vals = abi.decode(logs[i - 1].data, (uint256[]));
                return vals[0];
            }
        }
        return type(uint256).max;
    }

    function _getLastPrintString() internal returns (string memory) {
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bytes32 topic = keccak256("PrintString(string)");
        for (uint256 i = logs.length; i > 0; i--) {
            if (logs[i - 1].topics[0] == topic) {
                return abi.decode(logs[i - 1].data, (string));
            }
        }
        return "";
    }

    function _hasVMError() internal returns (bool) {
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bytes32 errorTopic = keccak256("VMError(string,uint256)");
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == errorTopic) return true;
        }
        return false;
    }

    // ==================== Tests ====================

    function testNegativeIndexLast() public {
        string memory src = "lst = [10, 20, 30]\nprint(lst[-1])\n";
        bytes memory bytecode = _compile(src);
        VM pyVm = new VM();
        vm.recordLogs();
        pyVm.execute(bytecode);
        assertEq(_getLastPrint(), 30, "lst[-1] should return last element");
    }

    function testNegativeIndexSecondToLast() public {
        string memory src = "lst = [10, 20, 30]\nprint(lst[-2])\n";
        bytes memory bytecode = _compile(src);
        VM pyVm = new VM();
        vm.recordLogs();
        pyVm.execute(bytecode);
        assertEq(_getLastPrint(), 20, "lst[-2] should return second-to-last");
    }

    function testNegativeIndexFirst() public {
        string memory src = "lst = [10, 20, 30]\nprint(lst[-3])\n";
        bytes memory bytecode = _compile(src);
        VM pyVm = new VM();
        vm.recordLogs();
        pyVm.execute(bytecode);
        assertEq(_getLastPrint(), 10, "lst[-len] should return first element");
    }

    function testNegativeIndexSingleElement() public {
        string memory src = "lst = [42]\nprint(lst[-1])\n";
        bytes memory bytecode = _compile(src);
        VM pyVm = new VM();
        vm.recordLogs();
        pyVm.execute(bytecode);
        assertEq(_getLastPrint(), 42, "lst[-1] on single element");
    }

    function testNegativeIndexOutOfRange() public {
        string memory src = "lst = [10, 20]\nprint(lst[-3])\n";
        bytes memory bytecode = _compile(src);
        VM pyVm = new VM();
        vm.recordLogs();
        pyVm.execute(bytecode);
        assertTrue(_hasVMError(), "lst[-3] on 2-element list should error");
    }

    function testStringNegativeIndex() public {
        string memory src = "s = \"hello\"\nprint(s[-1])\n";
        bytes memory bytecode = _compile(src);
        VM pyVm = new VM();
        vm.recordLogs();
        pyVm.execute(bytecode);
        assertEq(_getLastPrintString(), "o", "hello[-1] should be 'o'");
    }

    function testNegativeIndexAssignment() public {
        string memory src = "lst = [1, 2, 3]\nlst[-1] = 99\nprint(lst[-1])\n";
        bytes memory bytecode = _compile(src);
        VM pyVm = new VM();
        vm.recordLogs();
        pyVm.execute(bytecode);
        assertEq(_getLastPrint(), 99, "lst[-1] = 99 should work");
    }

    function testNegativeIndexInLoop() public {
        // Iterate backwards using negative index
        string memory src = "lst = [10, 20, 30]\ntotal = 0\nfor i in range(1, 4):\n    total = total + lst[-i]\nprint(total)\n";
        bytes memory bytecode = _compile(src);
        VM pyVm = new VM();
        vm.recordLogs();
        pyVm.execute(bytecode);
        assertEq(_getLastPrint(), 60, "sum of lst[-1]+lst[-2]+lst[-3] = 60");
    }
}
