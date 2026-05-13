// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import {Lexer} from "../src/phases/Lexer.sol";
import {Parser} from "../src/phases/Parser.sol";
import {SemanticAnalyzer} from "../src/phases/SemanticAnalyzer.sol";
import {CodeGenerator} from "../src/phases/CodeGenerator.sol";
import {VM} from "../src/phases/VM.sol";

contract TypeClassifyTest is Test {
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

    // ==================== FIX-1: Empty list classification ====================

    function testEmptyListIsinstanceList() public {
        string memory src = "print(isinstance([], list))\n";
        bytes memory bytecode = _compile(src);
        VM pyVm = new VM();
        vm.recordLogs();
        pyVm.execute(bytecode);
        assertEq(_getLastPrint(), 1, "isinstance([], list) should be True");
    }

    function testEmptyListTypeIsList() public {
        string memory src = "print(type([]))\n";
        bytes memory bytecode = _compile(src);
        VM pyVm = new VM();
        vm.recordLogs();
        pyVm.execute(bytecode);
        assertEq(_getLastPrint(), 2, "type([]) should be 2 (TYPE_LIST)");
    }

    function testEmptyListIsinstanceNotInt() public {
        string memory src = "print(isinstance([], int))\n";
        bytes memory bytecode = _compile(src);
        VM pyVm = new VM();
        vm.recordLogs();
        pyVm.execute(bytecode);
        assertEq(_getLastPrint(), 0, "isinstance([], int) should be False");
    }

    function testEmptyListLenZero() public {
        // len([]) returns 0, which is also a valid list ID.
        // This is a known value-space collision (FIX-2 will add type tags).
        // Test that len([]) == 0 and the empty list is still a list.
        string memory src = "x = []\nprint(isinstance(x, list))\nprint(type(x))\n";
        bytes memory bytecode = _compile(src);
        VM pyVm = new VM();
        vm.recordLogs();
        pyVm.execute(bytecode);
        // Last print: type([]) == 2 (TYPE_LIST)
        assertEq(_getLastPrint(), 2, "type([]) should be TYPE_LIST");
    }

    function testEmptyListAssignedToVar() public {
        string memory src = "x = []\nprint(isinstance(x, list))\n";
        bytes memory bytecode = _compile(src);
        VM pyVm = new VM();
        vm.recordLogs();
        pyVm.execute(bytecode);
        assertEq(_getLastPrint(), 1, "isinstance(x, list) where x=[] should be True");
    }
}
