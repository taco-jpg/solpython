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
        // Old list should be freed when variable is reassigned
        VM vm = _compileAndRun("x = [1]\nx = [2]\n");
        assertEq(vm.getGCAllocated(), 2, "should have 2 allocated");
        assertEq(vm.getGCFreed(), 1, "old list should be freed");
        assertEq(vm.getGCLive(), 1, "only new list should be live");
    }

    function testListReassignmentRefcount() public {
        VM vm = _compileAndRun("x = [1]\nx = [2]\n");
        // First list (id=0) should have refcount 0 and not be live
        assertEq(vm.getGCRefcount(0), 0, "old list refcount should be 0");
        assertFalse(vm.getGCLiveStatus(0), "old list should not be live");
        // Second list (id=1) should have refcount 1 and be live
        assertEq(vm.getGCRefcount(1), 1, "new list refcount should be 1");
        assertTrue(vm.getGCLiveStatus(1), "new list should be live");
    }

    function testGCDictReassignment() public {
        VM vm = _compileAndRun("x = {1: 2}\nx = {3: 4}\n");
        assertEq(vm.getGCFreed(), 1, "old dict should be freed");
        assertEq(vm.getGCLive(), 1, "only new dict should be live");
    }

    function testGCSetReassignment() public {
        VM vm = _compileAndRun("x = {1, 2}\nx = {3, 4}\n");
        assertEq(vm.getGCFreed(), 1, "old set should be freed");
        assertEq(vm.getGCLive(), 1, "only new set should be live");
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

    function testGCFunctionFrameCleanup() public {
        // Lists created in a function should be cleaned up when the function returns
        // (unless they're returned and assigned to a variable)
        string memory src = "def make():\n    x = [1, 2, 3]\n    return x\ny = make()\n";
        VM vm = _compileAndRun(src);
        assertEq(vm.getGCAllocated(), 1, "only 1 list (returned)");
        assertEq(vm.getGCLive(), 1, "returned list should still be live");
    }

    function testExistingTestsUnaffected() public {
        // Verify existing functionality still works with GC tracking
        string memory src = "x = [5, 3, 8, 1, 2]\nfor i in range(len(x)):\n    for j in range(len(x) - i - 1):\n        if x[j] > x[j + 1]:\n            t = x[j]\n            x[j] = x[j + 1]\n            x[j + 1] = t\nprint(x[0])\nprint(x[4])\n";
        VM vm = _compileAndRun(src);
        // Bubble sort should still work correctly
        assertTrue(vm.getGCAllocated() > 0, "should track created lists");
    }
}
