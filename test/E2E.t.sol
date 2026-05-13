// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import {Venv} from "../src/venv/Venv.sol";
import {VFS} from "../src/vfs/VFS.sol";
import {PythonCompiler} from "../src/PythonCompiler.sol";
import {VM} from "../src/phases/VM.sol";

contract E2ETest is Test {
    event Print(uint256[] values);

    function _getPrints() internal returns (uint256[] memory) {
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bytes32 printTopic = keccak256("Print(uint256[])");
        uint256 count = 0;
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == printTopic) count++;
        }
        uint256[] memory result = new uint256[](count);
        uint256 idx = 0;
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == printTopic) {
                uint256[] memory vals = abi.decode(logs[i].data, (uint256[]));
                result[idx] = vals[0];
                idx++;
            }
        }
        return result;
    }

    function testBubbleSortViaVenvImport() public {
        // 1. Create venv and write the "sorting" package module
        Venv venv = new Venv("test-env");

        string memory bubbleSrc = string.concat(
            "def bubble_sort(lst):\n",
            "    n = len(lst)\n",
            "    i = 0\n",
            "    while i < n:\n",
            "        j = 0\n",
            "        while j < n - i - 1:\n",
            "            if lst[j] > lst[j + 1]:\n",
            "                temp = lst[j]\n",
            "                lst[j] = lst[j + 1]\n",
            "                lst[j + 1] = temp\n",
            "            j += 1\n",
            "        i += 1\n",
            "    return lst\n"
        );

        venv.writeFile("bubble.py", bubbleSrc);

        // 2. Write the main program that imports bubble_sort
        string memory mainSrc = string.concat(
            "from bubble import bubble_sort\n",
            "lst = [64, 34, 25, 12, 22, 11, 90]\n",
            "result = bubble_sort(lst)\n",
            "print(result[0])\n",
            "print(result[-1])\n",
            "print(len(result))\n"
        );

        // 3. Compile using VFS from the venv
        PythonCompiler compiler = new PythonCompiler();
        bytes memory bytecode = compiler.compileWithVFS(mainSrc, venv.getVFS());

        // 4. Execute and assert
        VM pyVm = new VM();
        vm.recordLogs();
        pyVm.execute(bytecode);

        uint256[] memory p = _getPrints();
        assertEq(p.length, 3, "should have 3 prints");
        assertEq(p[0], 11, "result[0] == 11 (smallest)");
        assertEq(p[1], 90, "result[-1] == 90 (largest)");
        assertEq(p[2], 7, "len(result) == 7");
    }
}
