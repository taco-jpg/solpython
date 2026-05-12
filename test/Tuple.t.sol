// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import {Lexer} from "../src/phases/Lexer.sol";
import {Parser} from "../src/phases/Parser.sol";
import {SemanticAnalyzer} from "../src/phases/SemanticAnalyzer.sol";
import {CodeGenerator} from "../src/phases/CodeGenerator.sol";
import {VM} from "../src/phases/VM.sol";

contract TupleTest is Test {
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

    function _hasVMError() internal returns (bool) {
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bytes32 errorTopic = keccak256("VMError(string,uint256)");
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == errorTopic) return true;
        }
        return false;
    }

    // ==================== Tests ====================

    function testTupleLiteralIndex() public {
        string memory src = "t = (10, 20, 30)\nprint(t[0])\nprint(t[1])\nprint(t[2])\n";
        bytes memory bytecode = _compile(src);
        VM pyVm = new VM();
        vm.recordLogs();
        pyVm.execute(bytecode);
        // Last print is t[2] = 30
        assertEq(_getLastPrint(), 30, "t[2] should be 30");
    }

    function testTupleNegativeIndex() public {
        string memory src = "t = (10, 20, 30)\nprint(t[-1])\n";
        bytes memory bytecode = _compile(src);
        VM pyVm = new VM();
        vm.recordLogs();
        pyVm.execute(bytecode);
        assertEq(_getLastPrint(), 30, "t[-1] should be 30");
    }

    function testTupleUnpacking() public {
        string memory src = "a, b, c = (1, 2, 3)\nprint(a)\nprint(b)\nprint(c)\n";
        bytes memory bytecode = _compile(src);
        VM pyVm = new VM();
        vm.recordLogs();
        pyVm.execute(bytecode);
        // Last print is c = 3
        assertEq(_getLastPrint(), 3, "c should be 3");
    }

    function testTupleUnpackingImplicit() public {
        // a, b = 1, 2 (without parens on RHS)
        string memory src = "a, b = 1, 2\nprint(a)\nprint(b)\n";
        bytes memory bytecode = _compile(src);
        VM pyVm = new VM();
        vm.recordLogs();
        pyVm.execute(bytecode);
        assertEq(_getLastPrint(), 2, "b should be 2");
    }

    function testTupleSwap() public {
        // Classic swap pattern
        string memory src = "a = 5\nb = 10\na, b = b, a\nprint(a)\nprint(b)\n";
        bytes memory bytecode = _compile(src);
        VM pyVm = new VM();
        vm.recordLogs();
        pyVm.execute(bytecode);
        // Last print is b = 5
        assertEq(_getLastPrint(), 5, "b should be 5 after swap");
    }

    function testTupleEmpty() public {
        string memory src = "t = ()\nprint(1)\n";
        bytes memory bytecode = _compile(src);
        VM pyVm = new VM();
        vm.recordLogs();
        pyVm.execute(bytecode);
        assertEq(_getLastPrint(), 1, "empty tuple should compile");
        assertFalse(_hasVMError(), "empty tuple should not error");
    }

    function testTupleSingleElement() public {
        string memory src = "t = (42,)\nprint(t[0])\n";
        bytes memory bytecode = _compile(src);
        VM pyVm = new VM();
        vm.recordLogs();
        pyVm.execute(bytecode);
        assertEq(_getLastPrint(), 42, "single-element tuple t[0] = 42");
    }

    function testTupleWithExpressions() public {
        string memory src = "t = (1 + 2, 3 * 4)\nprint(t[0])\nprint(t[1])\n";
        bytes memory bytecode = _compile(src);
        VM pyVm = new VM();
        vm.recordLogs();
        pyVm.execute(bytecode);
        assertEq(_getLastPrint(), 12, "t[1] should be 12");
    }
}
