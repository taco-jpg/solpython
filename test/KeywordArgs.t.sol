// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import {Lexer} from "../src/phases/Lexer.sol";
import {Parser} from "../src/phases/Parser.sol";
import {SemanticAnalyzer} from "../src/phases/SemanticAnalyzer.sol";
import {CodeGenerator} from "../src/phases/CodeGenerator.sol";
import {VM} from "../src/phases/VM.sol";

contract KeywordArgsTest is Test {
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

    function _hasVMError() internal returns (bool) {
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bytes32 errorTopic = keccak256("VMError(string,uint256)");
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == errorTopic) return true;
        }
        return false;
    }

    // ==================== Tests ====================

    function testBasicKwarg() public {
        string memory src = "def f(a, b):\n    return a + b\nprint(f(b=3, a=2))\n";
        bytes memory bytecode = _compile(src);
        VM pyVm = new VM();
        vm.recordLogs();
        pyVm.execute(bytecode);
        assertEq(_getLastPrint(), 5, "f(b=3, a=2) = 2 + 3 = 5");
    }

    function testKwargWithDefault() public {
        string memory src = "def f(a, b=10, c=20):\n    return a + b + c\nprint(f(1, c=30))\n";
        bytes memory bytecode = _compile(src);
        VM pyVm = new VM();
        vm.recordLogs();
        pyVm.execute(bytecode);
        assertEq(_getLastPrint(), 41, "f(1, c=30) = 1 + 10 + 30 = 41");
    }

    function testKwargOverrideDefault() public {
        string memory src = "def f(a, b=10, c=20):\n    return a + b + c\nprint(f(1, b=5, c=3))\n";
        bytes memory bytecode = _compile(src);
        VM pyVm = new VM();
        vm.recordLogs();
        pyVm.execute(bytecode);
        assertEq(_getLastPrint(), 9, "f(1, b=5, c=3) = 1 + 5 + 3 = 9");
    }

    function testAllKwargs() public {
        string memory src = "def f(a, b, c):\n    return a * 100 + b * 10 + c\nprint(f(c=3, b=2, a=1))\n";
        bytes memory bytecode = _compile(src);
        VM pyVm = new VM();
        vm.recordLogs();
        pyVm.execute(bytecode);
        assertEq(_getLastPrint(), 123, "f(c=3, b=2, a=1) = 123");
    }

    function testMixedPositionalAndKwargs() public {
        string memory src = "def f(a, b, c):\n    return a + b + c\nprint(f(1, c=3, b=2))\n";
        bytes memory bytecode = _compile(src);
        VM pyVm = new VM();
        vm.recordLogs();
        pyVm.execute(bytecode);
        assertEq(_getLastPrint(), 6, "f(1, c=3, b=2) = 1 + 2 + 3 = 6");
    }

    function testKwargWithExpression() public {
        string memory src = "def f(a, b):\n    return a + b\nprint(f(b=2+3, a=1))\n";
        bytes memory bytecode = _compile(src);
        VM pyVm = new VM();
        vm.recordLogs();
        pyVm.execute(bytecode);
        assertEq(_getLastPrint(), 6, "f(b=2+3, a=1) = 1 + 5 = 6");
    }

    function testNoKwargsStillWorks() public {
        string memory src = "def add(a, b):\n    return a + b\nprint(add(3, 4))\n";
        bytes memory bytecode = _compile(src);
        VM pyVm = new VM();
        vm.recordLogs();
        pyVm.execute(bytecode);
        assertEq(_getLastPrint(), 7, "add(3, 4) = 7");
    }
}
