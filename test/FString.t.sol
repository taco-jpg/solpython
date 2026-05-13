// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import {Lexer} from "../src/phases/Lexer.sol";
import {Parser} from "../src/phases/Parser.sol";
import {SemanticAnalyzer} from "../src/phases/SemanticAnalyzer.sol";
import {CodeGenerator} from "../src/phases/CodeGenerator.sol";
import {VM} from "../src/phases/VM.sol";

contract FStringTest is Test {
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

    // ==================== f-string tests ====================

    function testFStringSimple() public {
        string memory src = string.concat(
            "x = 42\n",
            "print(f\"value={x}\")\n"
        );
        bytes memory bytecode = _compile(src);
        VM pyVm = new VM();
        vm.recordLogs();
        pyVm.execute(bytecode);
        assertEq(_getLastPrintString(), "value=42", "f-string with int");
    }

    function testFStringMultipleVars() public {
        string memory src = string.concat(
            "x = 10\n",
            "y = 20\n",
            "print(f\"x={x} y={y}\")\n"
        );
        bytes memory bytecode = _compile(src);
        VM pyVm = new VM();
        vm.recordLogs();
        pyVm.execute(bytecode);
        assertEq(_getLastPrintString(), "x=10 y=20", "f-string with two vars");
    }

    function testFStringTextOnly() public {
        string memory src = "print(f\"hello world\")\n";
        bytes memory bytecode = _compile(src);
        VM pyVm = new VM();
        vm.recordLogs();
        pyVm.execute(bytecode);
        assertEq(_getLastPrintString(), "hello world", "f-string text only");
    }

    function testFStringVarOnly() public {
        string memory src = string.concat(
            "x = 99\n",
            "print(f\"{x}\")\n"
        );
        bytes memory bytecode = _compile(src);
        VM pyVm = new VM();
        vm.recordLogs();
        pyVm.execute(bytecode);
        assertEq(_getLastPrintString(), "99", "f-string var only");
    }

    function testFStringWithCalculation() public {
        string memory src = string.concat(
            "x = 5\n",
            "y = 3\n",
            "z = x + y\n",
            "print(f\"sum={z}\")\n"
        );
        bytes memory bytecode = _compile(src);
        VM pyVm = new VM();
        vm.recordLogs();
        pyVm.execute(bytecode);
        assertEq(_getLastPrintString(), "sum=8", "f-string with calculated var");
    }

    // ==================== % formatting tests ====================

    function testPercentFormatString() public {
        string memory src = string.concat(
            "name = 42\n",
            "print(\"hello %s\" % name)\n"
        );
        bytes memory bytecode = _compile(src);
        VM pyVm = new VM();
        vm.recordLogs();
        pyVm.execute(bytecode);
        assertEq(_getLastPrintString(), "hello 42", "%s formatting");
    }

    function testPercentFormatInt() public {
        string memory src = string.concat(
            "x = 99\n",
            "print(\"value=%d\" % x)\n"
        );
        bytes memory bytecode = _compile(src);
        VM pyVm = new VM();
        vm.recordLogs();
        pyVm.execute(bytecode);
        assertEq(_getLastPrintString(), "value=99", "%d formatting");
    }

    function testPercentFormatTextOnly() public {
        string memory src = "print(\"hello world\" % 0)\n";
        bytes memory bytecode = _compile(src);
        VM pyVm = new VM();
        vm.recordLogs();
        pyVm.execute(bytecode);
        assertEq(_getLastPrintString(), "hello world", "% formatting no specifier");
    }
}
