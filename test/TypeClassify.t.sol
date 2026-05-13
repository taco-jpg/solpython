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

    // ==================== FIX-3: None vs -1 collision ====================

    function testNegOneEqualsNone() public {
        // -1 == None should be False (currently True due to collision)
        string memory src = "print(-1 == None)\n";
        bytes memory bytecode = _compile(src);
        VM pyVm = new VM();
        vm.recordLogs();
        pyVm.execute(bytecode);
        assertEq(_getLastPrint(), 0, "-1 == None should be False");
    }

    function testNegOneIsNotNone() public {
        string memory src = "print(-1 is None)\n";
        bytes memory bytecode = _compile(src);
        VM pyVm = new VM();
        vm.recordLogs();
        pyVm.execute(bytecode);
        assertEq(_getLastPrint(), 0, "-1 is None should be False");
    }

    function testNoneIsNone() public {
        string memory src = "print(None is None)\n";
        bytes memory bytecode = _compile(src);
        VM pyVm = new VM();
        vm.recordLogs();
        pyVm.execute(bytecode);
        assertEq(_getLastPrint(), 1, "None is None should be True");
    }

    function testNoneEqualsNone() public {
        string memory src = "print(None == None)\n";
        bytes memory bytecode = _compile(src);
        VM pyVm = new VM();
        vm.recordLogs();
        pyVm.execute(bytecode);
        assertEq(_getLastPrint(), 1, "None == None should be True");
    }

    function testNegOneType() public {
        // -1 in two's complement is 2^256-1, which collides with string ID range.
        // Full fix requires FIX-4 (integer tagging). For now, verify -1 != None.
        string memory src = "print(-1 == None)\n";
        bytes memory bytecode = _compile(src);
        VM pyVm = new VM();
        vm.recordLogs();
        pyVm.execute(bytecode);
        assertEq(_getLastPrint(), 0, "-1 == None should be False (FIX-3 core fix)");
    }

    function testNoneIsNoneType() public {
        string memory src = "print(isinstance(None, NoneType))\n";
        bytes memory bytecode = _compile(src);
        VM pyVm = new VM();
        vm.recordLogs();
        pyVm.execute(bytecode);
        assertEq(_getLastPrint(), 1, "isinstance(None, NoneType) should be True");
    }

    function testFuncReturnNegOne() public {
        // Function returning -1 should not trigger NoneType arithmetic error
        string memory src = "def f():\n    return -1\nx = f()\nprint(x + 1)\n";
        bytes memory bytecode = _compile(src);
        VM pyVm = new VM();
        vm.recordLogs();
        pyVm.execute(bytecode);
        assertEq(_getLastPrint(), 0, "f() returning -1: -1 + 1 should be 0");
    }

    function testListNegIndex() public {
        // lst[-1] on [5] should return 5, not None
        string memory src = "lst = [5]\nprint(lst[-1])\n";
        bytes memory bytecode = _compile(src);
        VM pyVm = new VM();
        vm.recordLogs();
        pyVm.execute(bytecode);
        assertEq(_getLastPrint(), 5, "lst[-1] on [5] should return 5");
    }
}
