// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import {PythonCompiler} from "../src/PythonCompiler.sol";
import {VM} from "../src/phases/VM.sol";

contract TempSlotTest is Test {
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

    // ==================== FIX-8: Temp variable slot reuse ====================

    function testListAssignInLoop() public {
        // List assignment inside a loop should not exhaust temp slots
        assertEq(_compileAndRun(
            "lst = [0, 0, 0, 0, 0]\nfor i in range(5):\n    lst[i] = i * 2\nprint(lst[4])\n"
        ), 8, "lst[4] = 4 * 2 = 8");
    }

    function testAugAssignInLoop() public {
        // Augmented assignment to list in loop
        assertEq(_compileAndRun(
            "lst = [0, 0, 0]\nfor i in range(3):\n    lst[i] += i + 1\nprint(lst[2])\n"
        ), 3, "lst[2] += 3");
    }

    function testMultipleListAssignsInLoop() public {
        // Multiple list assignments in same loop body
        assertEq(_compileAndRun(
            "a = [0, 0, 0]\nb = [0, 0, 0]\nfor i in range(3):\n    a[i] = i\n    b[i] = i + 10\nprint(a[2] + b[2])\n"
        ), 14, "a[2] + b[2] = 2 + 12 = 14");
    }
}
