// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import {Lexer} from "../src/phases/Lexer.sol";
import {Parser} from "../src/phases/Parser.sol";
import {SemanticAnalyzer} from "../src/phases/SemanticAnalyzer.sol";
import {CodeGenerator} from "../src/phases/CodeGenerator.sol";
import {VM} from "../src/phases/VM.sol";

contract TernaryTest is Test {
    event Print(uint256[] values);
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

    // ==================== Tests ====================

    function testTernaryTrue() public {
        string memory src = "x = 1 if 1 else 0\nprint(x)\n";
        bytes memory bytecode = _compile(src);
        VM pyVm = new VM();
        vm.recordLogs();
        pyVm.execute(bytecode);
        assertEq(_getLastPrint(), 1, "1 if 1 else 0 = 1");
    }

    function testTernaryFalse() public {
        string memory src = "x = 1 if 0 else 0\nprint(x)\n";
        bytes memory bytecode = _compile(src);
        VM pyVm = new VM();
        vm.recordLogs();
        pyVm.execute(bytecode);
        assertEq(_getLastPrint(), 0, "1 if 0 else 0 = 0");
    }

    function testTernaryWithComparison() public {
        string memory src = "x = 5\ny = 100 if x > 3 else 200\nprint(y)\n";
        bytes memory bytecode = _compile(src);
        VM pyVm = new VM();
        vm.recordLogs();
        pyVm.execute(bytecode);
        assertEq(_getLastPrint(), 100, "100 if 5 > 3 else 200 = 100");
    }

    function testTernaryFalseBranch() public {
        string memory src = "x = 2\ny = 100 if x > 3 else 200\nprint(y)\n";
        bytes memory bytecode = _compile(src);
        VM pyVm = new VM();
        vm.recordLogs();
        pyVm.execute(bytecode);
        assertEq(_getLastPrint(), 200, "100 if 2 > 3 else 200 = 200");
    }

    function testTernaryInExpression() public {
        string memory src = "x = 10\ny = (1 if x > 5 else 0) + 100\nprint(y)\n";
        bytes memory bytecode = _compile(src);
        VM pyVm = new VM();
        vm.recordLogs();
        pyVm.execute(bytecode);
        assertEq(_getLastPrint(), 101, "(1 if 10 > 5 else 0) + 100 = 101");
    }

    function testNestedTernary() public {
        string memory src = "x = 5\ny = 1 if x > 10 else 2 if x > 3 else 3\nprint(y)\n";
        bytes memory bytecode = _compile(src);
        VM pyVm = new VM();
        vm.recordLogs();
        pyVm.execute(bytecode);
        assertEq(_getLastPrint(), 2, "1 if 5 > 10 else 2 if 5 > 3 else 3 = 2");
    }

    function testTernaryWithFunctionCall() public {
        string memory src = "def f():\n    return 42\nx = 1\ny = f() if x else 0\nprint(y)\n";
        bytes memory bytecode = _compile(src);
        VM pyVm = new VM();
        vm.recordLogs();
        pyVm.execute(bytecode);
        assertEq(_getLastPrint(), 42, "f() if 1 else 0 = 42");
    }
}
