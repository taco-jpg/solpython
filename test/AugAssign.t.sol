// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import {Lexer} from "../src/phases/Lexer.sol";
import {Parser} from "../src/phases/Parser.sol";
import {CodeGenerator} from "../src/phases/CodeGenerator.sol";
import {VM} from "../src/phases/VM.sol";
import {PythonCompiler} from "../src/PythonCompiler.sol";

contract AugAssignTest is Test {
    event Print(uint256[] values);

    PythonCompiler private compiler;

    function setUp() public {
        compiler = new PythonCompiler();
    }

    function _compileAndRun(string memory src) internal returns (uint256) {
        bytes memory bytecode = compiler.compile(src);
        VM pyVm = new VM();
        vm.recordLogs();
        pyVm.execute(bytecode);
        return _getLastPrint();
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

    // ==================== FIX-7: Augmented assignment to non-simple targets ====================

    function testListIndexAugAdd() public {
        // lst[0] += 5 should modify the list element
        assertEq(_compileAndRun(
            "lst = [10, 20, 30]\nlst[0] += 5\nprint(lst[0])\n"
        ), 15, "lst[0] += 5 should be 15");
    }

    function testListIndexAugSub() public {
        assertEq(_compileAndRun(
            "lst = [10, 20, 30]\nlst[1] -= 5\nprint(lst[1])\n"
        ), 15, "lst[1] -= 5 should be 15");
    }

    function testListIndexAugMul() public {
        assertEq(_compileAndRun(
            "lst = [10, 20, 30]\nlst[2] *= 3\nprint(lst[2])\n"
        ), 90, "lst[2] *= 3 should be 90");
    }

    function testListIndexAugAddWithVarIndex() public {
        // lst[i] += 1 where i is a variable
        assertEq(_compileAndRun(
            "lst = [0, 0, 0]\ni = 1\nlst[i] += 10\nprint(lst[i])\n"
        ), 10, "lst[i] += 10 should be 10");
    }

    function testAugAssignSimpleStillWorks() public {
        // Verify simple variable augassign still works (regression check)
        assertEq(_compileAndRun(
            "x = 10\nx += 5\nprint(x)\n"
        ), 15, "simple x += 5 should be 15");
    }
}
