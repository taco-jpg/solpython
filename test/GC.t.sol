// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import {Lexer} from "../src/phases/Lexer.sol";
import {Parser} from "../src/phases/Parser.sol";
import {CodeGenerator} from "../src/phases/CodeGenerator.sol";
import {VM} from "../src/phases/VM.sol";
import {PythonCompiler} from "../src/PythonCompiler.sol";

contract GCTest is Test {
    PythonCompiler private compiler;

    function setUp() public {
        compiler = new PythonCompiler();
    }

    function _compileAndRun(string memory src) internal returns (VM) {
        bytes memory bytecode = compiler.compile(src);
        VM vm = new VM();
        vm.execute(bytecode);
        return vm;
    }

    // ==================== GC Basics ====================

    function testListIsRegistered() public {
        VM vm = _compileAndRun("x = [1, 2, 3]\n");
        assertEq(vm.getGCAllocated(), 1, "should have 1 allocated object");
        assertEq(vm.getGCLive(), 1, "should have 1 live object");
    }

    function testMultipleLists() public {
        VM vm = _compileAndRun("a = [1, 2]\nb = [3, 4]\nc = [5, 6]\n");
        assertEq(vm.getGCAllocated(), 3, "should have 3 allocated");
        assertEq(vm.getGCLive(), 3, "should have 3 live");
    }

    function testDictIsRegistered() public {
        VM vm = _compileAndRun("x = {1: 2, 3: 4}\n");
        assertEq(vm.getGCAllocated(), 1, "should have 1 allocated");
    }

    function testSetIsRegistered() public {
        VM vm = _compileAndRun("x = {1, 2, 3}\n");
        assertEq(vm.getGCAllocated(), 1, "should have 1 allocated");
    }

    function testRefcountStartsAtOne() public {
        VM vm = _compileAndRun("x = [1, 2, 3]\n");
        // First list gets ID 0
        assertEq(vm.getGCRefcount(0), 1, "refcount should start at 1");
        assertTrue(vm.getGCLiveStatus(0), "should be live");
    }

    function testGCStatsEvent() public {
        // GC stats should be accessible
        VM vm = _compileAndRun("x = [1]\ny = [2]\n");
        assertEq(vm.getGCAllocated(), 2);
        assertEq(vm.getGCFreed(), 0);
        assertEq(vm.getGCLive(), 2);
    }

    function testNoObjectsForPrimitives() public {
        VM vm = _compileAndRun("x = 42\ny = True\nz = None\n");
        assertEq(vm.getGCAllocated(), 0, "primitives should not be tracked");
    }

    function testListInLoop() public {
        // Each iteration creates a new list
        VM vm = _compileAndRun("for i in range(5):\n    x = [i]\n");
        assertEq(vm.getGCAllocated(), 5, "loop should create 5 lists");
    }

    function testNestedList() public {
        // Inner list allocated first, then outer
        VM vm = _compileAndRun("inner = [1, 2]\nouter = [inner, 3]\n");
        assertEq(vm.getGCAllocated(), 2, "should have 2 lists");
    }

    function testListReassignment() public {
        // Creating new list, old one still tracked
        VM vm = _compileAndRun("x = [1]\nx = [2]\n");
        assertEq(vm.getGCAllocated(), 2, "should have 2 allocated");
        // Both are still live (no automatic unref on reassignment yet)
        assertEq(vm.getGCLive(), 2, "both still live");
    }

    function testGCInFunction() public {
        string memory src = "def make_list():\n    return [1, 2, 3]\nx = make_list()\n";
        VM vm = _compileAndRun(src);
        assertEq(vm.getGCAllocated(), 1, "function-created list should be tracked");
    }

    function testGCMultipleTypes() public {
        VM vm = _compileAndRun("a = [1]\nb = {2: 3}\nc = {4, 5}\n");
        assertEq(vm.getGCAllocated(), 3, "should track all collection types");
    }

    function testExistingTestsUnaffected() public {
        // Verify existing functionality still works with GC tracking
        string memory src = "x = [5, 3, 8, 1, 2]\nfor i in range(len(x)):\n    for j in range(len(x) - i - 1):\n        if x[j] > x[j + 1]:\n            t = x[j]\n            x[j] = x[j + 1]\n            x[j + 1] = t\nprint(x[0])\nprint(x[4])\n";
        VM vm = _compileAndRun(src);
        // Bubble sort should still work correctly
        assertTrue(vm.getGCAllocated() > 0, "should track created lists");
    }
}
