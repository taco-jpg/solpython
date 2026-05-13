// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import {Lexer} from "../src/phases/Lexer.sol";
import {Parser} from "../src/phases/Parser.sol";
import {SemanticAnalyzer} from "../src/phases/SemanticAnalyzer.sol";
import {CodeGenerator} from "../src/phases/CodeGenerator.sol";
import {VM} from "../src/phases/VM.sol";

contract GlobalNonlocalTest is Test {
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

    // ==================== global ====================

    function testGlobalRead() public {
        string memory src = string.concat(
            "x = 10\n",
            "def f():\n",
            "    global x\n",
            "    return x\n",
            "print(f())\n"
        );
        bytes memory bytecode = _compile(src);
        VM pyVm = new VM();
        vm.recordLogs();
        pyVm.execute(bytecode);
        uint256[] memory p = _getPrints();
        assertEq(p[0], 10, "global read");
    }

    function testGlobalWrite() public {
        string memory src = string.concat(
            "x = 10\n",
            "def f():\n",
            "    global x\n",
            "    x = 20\n",
            "f()\n",
            "print(x)\n"
        );
        bytes memory bytecode = _compile(src);
        VM pyVm = new VM();
        vm.recordLogs();
        pyVm.execute(bytecode);
        uint256[] memory p = _getPrints();
        assertEq(p[0], 20, "global write");
    }

    function testGlobalMultiple() public {
        string memory src = string.concat(
            "x = 1\n",
            "y = 2\n",
            "def f():\n",
            "    global x, y\n",
            "    x = 10\n",
            "    y = 20\n",
            "f()\n",
            "print(x)\n",
            "print(y)\n"
        );
        bytes memory bytecode = _compile(src);
        VM pyVm = new VM();
        vm.recordLogs();
        pyVm.execute(bytecode);
        uint256[] memory p = _getPrints();
        assertEq(p[0], 10, "global x");
        assertEq(p[1], 20, "global y");
    }
}
