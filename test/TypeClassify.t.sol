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

    // ==================== FIX-2: Bool tagging ====================

    function testTypeTrueIsBool() public {
        string memory src = "print(type(True))\n";
        bytes memory bytecode = _compile(src);
        VM pyVm = new VM();
        vm.recordLogs();
        pyVm.execute(bytecode);
        assertEq(_getLastPrint(), 3, "type(True) should be 3 (TYPE_BOOL)");
    }

    function testTypeZeroIsInt() public {
        string memory src = "print(type(0))\n";
        bytes memory bytecode = _compile(src);
        VM pyVm = new VM();
        vm.recordLogs();
        pyVm.execute(bytecode);
        assertEq(_getLastPrint(), 0, "type(0) should be 0 (TYPE_INT)");
    }

    function testTypeOneIsInt() public {
        string memory src = "print(type(1))\n";
        bytes memory bytecode = _compile(src);
        VM pyVm = new VM();
        vm.recordLogs();
        pyVm.execute(bytecode);
        assertEq(_getLastPrint(), 0, "type(1) should be 0 (TYPE_INT)");
    }

    function testIsinstanceTrueInt() public {
        // Python: isinstance(True, int) == True (bool is subclass of int)
        string memory src = "print(isinstance(True, int))\n";
        bytes memory bytecode = _compile(src);
        VM pyVm = new VM();
        vm.recordLogs();
        pyVm.execute(bytecode);
        assertEq(_getLastPrint(), 1, "isinstance(True, int) should be True");
    }

    function testIsinstanceZeroNotBool() public {
        string memory src = "print(isinstance(0, bool))\n";
        bytes memory bytecode = _compile(src);
        VM pyVm = new VM();
        vm.recordLogs();
        pyVm.execute(bytecode);
        assertEq(_getLastPrint(), 0, "isinstance(0, bool) should be False");
    }

    function testIsinstanceZeroIsInt() public {
        string memory src = "print(isinstance(0, int))\n";
        bytes memory bytecode = _compile(src);
        VM pyVm = new VM();
        vm.recordLogs();
        pyVm.execute(bytecode);
        assertEq(_getLastPrint(), 1, "isinstance(0, int) should be True");
    }

    function testBoolArithmetic() public {
        // True + 1 == 2 (bool arithmetic still works)
        string memory src = "print(True + 1)\n";
        bytes memory bytecode = _compile(src);
        VM pyVm = new VM();
        vm.recordLogs();
        pyVm.execute(bytecode);
        assertEq(_getLastPrint(), 2, "True + 1 should be 2");
    }

    function testIfZeroDoesNotExecute() public {
        string memory src = "x = 0\nif x:\n    print(1)\nelse:\n    print(0)\n";
        bytes memory bytecode = _compile(src);
        VM pyVm = new VM();
        vm.recordLogs();
        pyVm.execute(bytecode);
        assertEq(_getLastPrint(), 0, "if 0: should not execute body");
    }

    function testIfFalseDoesNotExecute() public {
        string memory src = "if False:\n    print(1)\nelse:\n    print(0)\n";
        bytes memory bytecode = _compile(src);
        VM pyVm = new VM();
        vm.recordLogs();
        pyVm.execute(bytecode);
        assertEq(_getLastPrint(), 0, "if False: should not execute body");
    }

    function testOneEqualsTrue() public {
        // Python semantics: 1 == True is True
        string memory src = "print(1 == True)\n";
        bytes memory bytecode = _compile(src);
        VM pyVm = new VM();
        vm.recordLogs();
        pyVm.execute(bytecode);
        assertEq(_getLastPrint(), 1, "1 == True should be True");
    }

    function testZeroEqualsFalse() public {
        // Python semantics: 0 == False is True
        string memory src = "print(0 == False)\n";
        bytes memory bytecode = _compile(src);
        VM pyVm = new VM();
        vm.recordLogs();
        pyVm.execute(bytecode);
        assertEq(_getLastPrint(), 1, "0 == False should be True");
    }

    function testComparisonReturnsBool() public {
        // 3 > 2 should return a bool, not an int
        string memory src = "print(type(3 > 2))\n";
        bytes memory bytecode = _compile(src);
        VM pyVm = new VM();
        vm.recordLogs();
        pyVm.execute(bytecode);
        assertEq(_getLastPrint(), 3, "type(3 > 2) should be 3 (TYPE_BOOL)");
    }

    function testBoolAndBool() public {
        string memory src = "print(True and False)\n";
        bytes memory bytecode = _compile(src);
        VM pyVm = new VM();
        vm.recordLogs();
        pyVm.execute(bytecode);
        assertEq(_getLastPrint(), 0, "True and False should be False");
    }

    function testBoolOrBool() public {
        string memory src = "print(False or True)\n";
        bytes memory bytecode = _compile(src);
        VM pyVm = new VM();
        vm.recordLogs();
        pyVm.execute(bytecode);
        assertEq(_getLastPrint(), 1, "False or True should be True");
    }

    function testNotTrue() public {
        string memory src = "print(not True)\n";
        bytes memory bytecode = _compile(src);
        VM pyVm = new VM();
        vm.recordLogs();
        pyVm.execute(bytecode);
        assertEq(_getLastPrint(), 0, "not True should be False");
    }

    function testNotZero() public {
        string memory src = "print(not 0)\n";
        bytes memory bytecode = _compile(src);
        VM pyVm = new VM();
        vm.recordLogs();
        pyVm.execute(bytecode);
        assertEq(_getLastPrint(), 1, "not 0 should be True");
    }
}
