// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import {Lexer} from "../src/phases/Lexer.sol";
import {Parser} from "../src/phases/Parser.sol";
import {SemanticAnalyzer} from "../src/phases/SemanticAnalyzer.sol";
import {CodeGenerator} from "../src/phases/CodeGenerator.sol";
import {VM} from "../src/phases/VM.sol";

contract SortedReversedTest is Test {
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

    // ==================== sorted ====================

    function testSortedBasic() public {
        string memory src = string.concat(
            "lst = [3, 1, 4, 1, 5, 9, 2, 6]\n",
            "s = sorted(lst)\n",
            "print(s[0])\n",
            "print(s[1])\n",
            "print(s[2])\n",
            "print(s[3])\n",
            "print(s[4])\n",
            "print(s[5])\n",
            "print(s[6])\n",
            "print(s[7])\n"
        );
        bytes memory bytecode = _compile(src);
        VM pyVm = new VM();
        vm.recordLogs();
        pyVm.execute(bytecode);
        uint256[] memory p = _getPrints();
        assertEq(p[0], 1, "sorted[0]=1");
        assertEq(p[1], 1, "sorted[1]=1");
        assertEq(p[2], 2, "sorted[2]=2");
        assertEq(p[3], 3, "sorted[3]=3");
        assertEq(p[4], 4, "sorted[4]=4");
        assertEq(p[5], 5, "sorted[5]=5");
        assertEq(p[6], 6, "sorted[6]=6");
        assertEq(p[7], 9, "sorted[7]=9");
    }

    function testSortedEmpty() public {
        string memory src = string.concat(
            "s = sorted([])\n",
            "print(len(s))\n"
        );
        bytes memory bytecode = _compile(src);
        VM pyVm = new VM();
        vm.recordLogs();
        pyVm.execute(bytecode);
        uint256[] memory p = _getPrints();
        assertEq(p[0], 0, "sorted empty = empty");
    }

    function testSortedSingle() public {
        string memory src = string.concat(
            "s = sorted([42])\n",
            "print(s[0])\n"
        );
        bytes memory bytecode = _compile(src);
        VM pyVm = new VM();
        vm.recordLogs();
        pyVm.execute(bytecode);
        uint256[] memory p = _getPrints();
        assertEq(p[0], 42, "sorted single = same");
    }

    function testSortedPreservesOriginal() public {
        string memory src = string.concat(
            "lst = [3, 1, 2]\n",
            "s = sorted(lst)\n",
            "print(lst[0])\n",
            "print(s[0])\n"
        );
        bytes memory bytecode = _compile(src);
        VM pyVm = new VM();
        vm.recordLogs();
        pyVm.execute(bytecode);
        uint256[] memory p = _getPrints();
        assertEq(p[0], 3, "original unchanged");
        assertEq(p[1], 1, "sorted is new list");
    }

    // ==================== reversed ====================

    function testReversedBasic() public {
        string memory src = string.concat(
            "lst = [1, 2, 3, 4, 5]\n",
            "r = reversed(lst)\n",
            "print(r[0])\n",
            "print(r[1])\n",
            "print(r[2])\n",
            "print(r[3])\n",
            "print(r[4])\n"
        );
        bytes memory bytecode = _compile(src);
        VM pyVm = new VM();
        vm.recordLogs();
        pyVm.execute(bytecode);
        uint256[] memory p = _getPrints();
        assertEq(p[0], 5, "reversed[0]=5");
        assertEq(p[1], 4, "reversed[1]=4");
        assertEq(p[2], 3, "reversed[2]=3");
        assertEq(p[3], 2, "reversed[3]=2");
        assertEq(p[4], 1, "reversed[4]=1");
    }

    function testReversedEmpty() public {
        string memory src = string.concat(
            "r = reversed([])\n",
            "print(len(r))\n"
        );
        bytes memory bytecode = _compile(src);
        VM pyVm = new VM();
        vm.recordLogs();
        pyVm.execute(bytecode);
        uint256[] memory p = _getPrints();
        assertEq(p[0], 0, "reversed empty = empty");
    }

    function testReversedSingle() public {
        string memory src = string.concat(
            "r = reversed([42])\n",
            "print(r[0])\n"
        );
        bytes memory bytecode = _compile(src);
        VM pyVm = new VM();
        vm.recordLogs();
        pyVm.execute(bytecode);
        uint256[] memory p = _getPrints();
        assertEq(p[0], 42, "reversed single = same");
    }
}
