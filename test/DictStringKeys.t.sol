// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import {Lexer} from "../src/phases/Lexer.sol";
import {Parser} from "../src/phases/Parser.sol";
import {SemanticAnalyzer} from "../src/phases/SemanticAnalyzer.sol";
import {CodeGenerator} from "../src/phases/CodeGenerator.sol";
import {VM} from "../src/phases/VM.sol";

contract DictStringKeysTest is Test {
    event Print(uint256[] values);
    event VMError(string message, uint256 pc);

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

    function _run(string memory src) internal returns (VM) {
        bytes memory bytecode = _compile(src);
        VM pyVm = new VM();
        pyVm.execute(bytecode);
        return pyVm;
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

    function _hasVMError() internal returns (bool) {
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bytes32 errorTopic = keccak256("VMError(string,uint256)");
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == errorTopic) return true;
        }
        return false;
    }

    // ==================== String Key Tests ====================

    function testDictStringKeyLiteral() public {
        // Dict with string keys should compile and execute
        string memory src = "d = {\"a\": 1, \"b\": 2}\nprint(1)\n";
        bytes memory bytecode = _compile(src);
        VM pyVm = new VM();

        vm.recordLogs();
        pyVm.execute(bytecode);

        assertEq(_getLastPrint(), 1, "Should print 1");
        assertFalse(_hasVMError(), "Dict with string keys should not error");
    }

    function testDictStringKeyGet() public {
        // d["a"] should return the value
        string memory src = "d = {\"a\": 42}\nprint(d[\"a\"])\n";
        bytes memory bytecode = _compile(src);
        VM pyVm = new VM();

        vm.recordLogs();
        pyVm.execute(bytecode);

        assertEq(_getLastPrint(), 42, "d['a'] should be 42");
    }

    function testDictStringKeySet() public {
        // d["x"] = 10 should work
        string memory src = "d = {}\nd[\"x\"] = 10\nprint(d[\"x\"])\n";
        bytes memory bytecode = _compile(src);
        VM pyVm = new VM();

        vm.recordLogs();
        pyVm.execute(bytecode);

        assertEq(_getLastPrint(), 10, "d['x'] should be 10");
    }

    function testDictStringKeyUpdate() public {
        // Updating a string key should work
        string memory src = "d = {\"a\": 1}\nd[\"a\"] = 99\nprint(d[\"a\"])\n";
        bytes memory bytecode = _compile(src);
        VM pyVm = new VM();

        vm.recordLogs();
        pyVm.execute(bytecode);

        assertEq(_getLastPrint(), 99, "d['a'] should be 99 after update");
    }

    function testDictStringKeyHas() public {
        // "a" in d should work — use comparison expression instead of ternary
        string memory src = "d = {\"a\": 1}\nresult = \"a\" in d\nprint(result)\n";
        bytes memory bytecode = _compile(src);
        VM pyVm = new VM();

        vm.recordLogs();
        pyVm.execute(bytecode);

        assertEq(_getLastPrint(), 1, "'a' in d should be true");
    }

    function testDictStringKeyNotHas() public {
        // "z" not in d — use comparison expression instead of ternary
        string memory src = "d = {\"a\": 1}\nresult = \"z\" in d\nprint(result)\n";
        bytes memory bytecode = _compile(src);
        VM pyVm = new VM();

        vm.recordLogs();
        pyVm.execute(bytecode);

        assertEq(_getLastPrint(), 0, "'z' in d should be false");
    }

    function testDictMultipleStringKeys() public {
        // Multiple string keys with different values
        string memory src = "d = {\"x\": 10, \"y\": 20, \"z\": 30}\nprint(d[\"y\"])\n";
        bytes memory bytecode = _compile(src);
        VM pyVm = new VM();

        vm.recordLogs();
        pyVm.execute(bytecode);

        assertEq(_getLastPrint(), 20, "d['y'] should be 20");
    }

    function testDictStringKeyLen() public {
        // len(d) should work with string keys
        string memory src = "d = {\"a\": 1, \"b\": 2}\nprint(len(d))\n";
        bytes memory bytecode = _compile(src);
        VM pyVm = new VM();

        vm.recordLogs();
        pyVm.execute(bytecode);

        assertEq(_getLastPrint(), 2, "len(d) should be 2");
    }
}
