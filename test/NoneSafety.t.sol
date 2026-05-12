// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import {Lexer} from "../src/phases/Lexer.sol";
import {Parser} from "../src/phases/Parser.sol";
import {SemanticAnalyzer} from "../src/phases/SemanticAnalyzer.sol";
import {CodeGenerator} from "../src/phases/CodeGenerator.sol";
import {VM} from "../src/phases/VM.sol";

contract NoneSafetyTest is Test {
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

    // ==================== None Literal Tests ====================

    function testNoneIsNone() public {
        string memory src = "x = None\nprint(1 if x is None else 0)\n";
        bytes memory bytecode = _compile(src);
        VM pyVm = new VM();

        vm.recordLogs();
        pyVm.execute(bytecode);

        assertEq(_getLastPrint(), 1, "None is None should be true");
    }

    function testNoneEquality() public {
        string memory src = "x = None\nprint(1 if x == None else 0)\n";
        bytes memory bytecode = _compile(src);
        VM pyVm = new VM();

        vm.recordLogs();
        pyVm.execute(bytecode);

        assertEq(_getLastPrint(), 1, "None == None should be true");
    }

    function testNoneNotEqualInt() public {
        string memory src = "x = None\nprint(1 if x != 42 else 0)\n";
        bytes memory bytecode = _compile(src);
        VM pyVm = new VM();

        vm.recordLogs();
        pyVm.execute(bytecode);

        assertEq(_getLastPrint(), 1, "None != 42 should be true");
    }

    // ==================== None Arithmetic Safety ====================

    function testNoneAddInt() public {
        // None + 1 should produce a VMError, not silently wrap
        string memory src = "x = None\ny = x + 1\nprint(y)\n";
        bytes memory bytecode = _compile(src);
        VM pyVm = new VM();

        vm.recordLogs();
        pyVm.execute(bytecode);

        assertTrue(_hasVMError(), "None + 1 should produce VMError");
    }

    function testNoneSubInt() public {
        string memory src = "x = None\ny = x - 1\nprint(y)\n";
        bytes memory bytecode = _compile(src);
        VM pyVm = new VM();

        vm.recordLogs();
        pyVm.execute(bytecode);

        assertTrue(_hasVMError(), "None - 1 should produce VMError");
    }

    function testNoneMulInt() public {
        string memory src = "x = None\ny = x * 2\nprint(y)\n";
        bytes memory bytecode = _compile(src);
        VM pyVm = new VM();

        vm.recordLogs();
        pyVm.execute(bytecode);

        assertTrue(_hasVMError(), "None * 2 should produce VMError");
    }

    function testNoneDivInt() public {
        string memory src = "x = None\ny = x / 1\nprint(y)\n";
        bytes memory bytecode = _compile(src);
        VM pyVm = new VM();

        vm.recordLogs();
        pyVm.execute(bytecode);

        assertTrue(_hasVMError(), "None / 1 should produce VMError");
    }

    function testIntAddNone() public {
        string memory src = "x = None\ny = 1 + x\nprint(y)\n";
        bytes memory bytecode = _compile(src);
        VM pyVm = new VM();

        vm.recordLogs();
        pyVm.execute(bytecode);

        assertTrue(_hasVMError(), "1 + None should produce VMError");
    }

    function testNoneComparison() public {
        string memory src = "x = None\ny = x < 5\nprint(y)\n";
        bytes memory bytecode = _compile(src);
        VM pyVm = new VM();

        vm.recordLogs();
        pyVm.execute(bytecode);

        assertTrue(_hasVMError(), "None < 5 should produce VMError");
    }

    function testNoneInFunctionReturn() public {
        // Function that implicitly returns None
        string memory src = "def f():\n    pass\nx = f()\nprint(x + 1)\n";
        bytes memory bytecode = _compile(src);
        VM pyVm = new VM();

        vm.recordLogs();
        pyVm.execute(bytecode);

        assertTrue(_hasVMError(), "None (implicit return) + 1 should produce VMError");
    }
}
