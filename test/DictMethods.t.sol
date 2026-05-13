// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import {Lexer} from "../src/phases/Lexer.sol";
import {Parser} from "../src/phases/Parser.sol";
import {SemanticAnalyzer} from "../src/phases/SemanticAnalyzer.sol";
import {CodeGenerator} from "../src/phases/CodeGenerator.sol";
import {VM} from "../src/phases/VM.sol";

contract DictMethodsTest is Test {
    event Print(uint256[] values);
    event PrintString(string value);

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

    // ==================== dict.keys() ====================

    function testDictKeys() public {
        string memory src = string.concat(
            "d = {1: 10, 2: 20, 3: 30}\n",
            "k = d.keys()\n",
            "print(len(k))\n"
        );
        bytes memory bytecode = _compile(src);
        VM pyVm = new VM();
        vm.recordLogs();
        pyVm.execute(bytecode);
        uint256[] memory p = _getPrints();
        assertEq(p[0], 3, "3 keys");
    }

    // ==================== dict.values() ====================

    function testDictValues() public {
        string memory src = string.concat(
            "d = {1: 10, 2: 20, 3: 30}\n",
            "v = d.values()\n",
            "print(len(v))\n"
        );
        bytes memory bytecode = _compile(src);
        VM pyVm = new VM();
        vm.recordLogs();
        pyVm.execute(bytecode);
        uint256[] memory p = _getPrints();
        assertEq(p[0], 3, "3 values");
    }

    // ==================== dict.items() ====================

    function testDictItems() public {
        string memory src = string.concat(
            "d = {1: 10, 2: 20}\n",
            "it = d.items()\n",
            "print(len(it))\n"
        );
        bytes memory bytecode = _compile(src);
        VM pyVm = new VM();
        vm.recordLogs();
        pyVm.execute(bytecode);
        uint256[] memory p = _getPrints();
        assertEq(p[0], 2, "2 items");
    }

    // ==================== dict.get() ====================

    function testDictGetExisting() public {
        string memory src = string.concat(
            "d = {1: 10, 2: 20}\n",
            "print(d.get(1, 0))\n"
        );
        bytes memory bytecode = _compile(src);
        VM pyVm = new VM();
        vm.recordLogs();
        pyVm.execute(bytecode);
        uint256[] memory p = _getPrints();
        assertEq(p[0], 10, "get existing key");
    }

    function testDictGetDefault() public {
        string memory src = string.concat(
            "d = {1: 10, 2: 20}\n",
            "print(d.get(5, 99))\n"
        );
        bytes memory bytecode = _compile(src);
        VM pyVm = new VM();
        vm.recordLogs();
        pyVm.execute(bytecode);
        uint256[] memory p = _getPrints();
        assertEq(p[0], 99, "get with default");
    }

    // ==================== dict.update() ====================

    function testDictUpdate() public {
        string memory src = string.concat(
            "d = {1: 10, 2: 20}\n",
            "d.update({3: 30})\n",
            "print(len(d))\n"
        );
        bytes memory bytecode = _compile(src);
        VM pyVm = new VM();
        vm.recordLogs();
        pyVm.execute(bytecode);
        uint256[] memory p = _getPrints();
        assertEq(p[0], 3, "update adds new key");
    }

    function testDictUpdateOverwrite() public {
        string memory src = string.concat(
            "d = {1: 10, 2: 20}\n",
            "d.update({2: 99})\n",
            "print(d[2])\n"
        );
        bytes memory bytecode = _compile(src);
        VM pyVm = new VM();
        vm.recordLogs();
        pyVm.execute(bytecode);
        uint256[] memory p = _getPrints();
        assertEq(p[0], 99, "update overwrites existing");
    }
}
