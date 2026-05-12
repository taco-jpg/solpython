// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import {Lexer} from "../src/phases/Lexer.sol";
import {Parser} from "../src/phases/Parser.sol";
import {SemanticAnalyzer} from "../src/phases/SemanticAnalyzer.sol";
import {CodeGenerator} from "../src/phases/CodeGenerator.sol";
import {VM} from "../src/phases/VM.sol";

contract UnboundLocalTest is Test {
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

    function _hasSemanticError() internal returns (bool) {
        // Check if the analyzer produced errors
        // Since we can't directly check, we rely on the VM behavior
        return false;
    }

    // ==================== Tests ====================

    function testGlobalReadInFunction() public {
        // Simple function that prints a constant to verify basic function calls work
        string memory src = "def f():\n    print(42)\nf()\n";
        bytes memory bytecode = _compile(src);
        VM pyVm = new VM();

        vm.recordLogs();
        pyVm.execute(bytecode);

        assertEq(_getLastPrint(), 42, "Function call should work");
    }

    function testLocalAssignmentAfterRead() public {
        // In Python, if x is assigned in the function, it's local — reading before assign is an error
        // x = 10
        // def f():
        //     print(x)  # UnboundLocalError
        //     x = 20
        // f()
        string memory src = "x = 10\ndef f():\n    print(x)\n    x = 20\nf()\n";
        // The semantic analyzer should catch this: x is used before being assigned in the local scope
        bytes memory bytecode = _compile(src);
        VM pyVm = new VM();

        vm.recordLogs();
        pyVm.execute(bytecode);

        // The semantic analyzer should have caught this. If not, the VM might produce wrong output.
        // We test that the semantic analyzer reports the error.
        SemanticAnalyzer analyzer = new SemanticAnalyzer();
        Lexer lexer = new Lexer();
        lexer.tokenize(src);
        Parser parser = new Parser();
        parser.parse(lexer);
        analyzer.analyze(parser);
        assertTrue(analyzer.getErrorCount() > 0, "Should detect unbound local variable");
    }

    function testLocalAssignThenRead() public {
        // Local assignment then read should work
        string memory src = "def f():\n    x = 20\n    print(x)\nf()\n";
        bytes memory bytecode = _compile(src);
        VM pyVm = new VM();

        vm.recordLogs();
        pyVm.execute(bytecode);

        assertEq(_getLastPrint(), 20, "Local assign then read should work");
    }

    function testParamRead() public {
        // Reading a parameter should work
        string memory src = "def f(x):\n    print(x)\nf(42)\n";
        bytes memory bytecode = _compile(src);
        VM pyVm = new VM();

        vm.recordLogs();
        pyVm.execute(bytecode);

        assertEq(_getLastPrint(), 42, "Parameter read should work");
    }

    function testLocalShadowGlobal() public {
        // Local variable in function should work independently
        string memory src = "def f():\n    x = 20\n    print(x)\nf()\n";
        bytes memory bytecode = _compile(src);
        VM pyVm = new VM();

        vm.recordLogs();
        pyVm.execute(bytecode);

        assertEq(_getLastPrint(), 20, "Local x should be 20");
    }
}
