// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import {Lexer} from "../src/phases/Lexer.sol";
import {Parser} from "../src/phases/Parser.sol";
import {SemanticAnalyzer} from "../src/phases/SemanticAnalyzer.sol";
import {CodeGenerator} from "../src/phases/CodeGenerator.sol";
import {VM} from "../src/phases/VM.sol";

contract LoopElseTest is Test {
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

    // ==================== While...Else ====================

    function testWhileElseNoBreak() public {
        string memory src = "x = 0\nwhile x < 3:\n    x = x + 1\nelse:\n    print(99)\n";
        bytes memory bytecode = _compile(src);
        VM pyVm = new VM();
        vm.recordLogs();
        pyVm.execute(bytecode);
        assertEq(_getLastPrint(), 99, "while else executes when no break");
    }

    function testWhileElseWithBreak() public {
        string memory src = "x = 0\nwhile x < 10:\n    if x == 2:\n        break\n    x = x + 1\nelse:\n    print(99)\nprint(x)\n";
        bytes memory bytecode = _compile(src);
        VM pyVm = new VM();
        vm.recordLogs();
        pyVm.execute(bytecode);
        assertEq(_getLastPrint(), 2, "x=2 when break hit, else skipped");
    }

    // ==================== For...Else ====================

    function testForElseNoBreak() public {
        string memory src = "for i in range(3):\n    pass\nelse:\n    print(77)\n";
        bytes memory bytecode = _compile(src);
        VM pyVm = new VM();
        vm.recordLogs();
        pyVm.execute(bytecode);
        assertEq(_getLastPrint(), 77, "for else executes when no break");
    }

    function testForElseWithBreak() public {
        string memory src = "found = 0\nfor i in range(10):\n    if i == 5:\n        found = 1\n        break\nelse:\n    print(99)\nprint(found)\n";
        bytes memory bytecode = _compile(src);
        VM pyVm = new VM();
        vm.recordLogs();
        pyVm.execute(bytecode);
        assertEq(_getLastPrint(), 1, "break at i=5, else skipped, found=1");
    }

    function testForElseComplete() public {
        string memory src = "for i in range(3):\n    pass\nelse:\n    print(42)\nprint(100)\n";
        bytes memory bytecode = _compile(src);
        VM pyVm = new VM();
        vm.recordLogs();
        pyVm.execute(bytecode);
        // Check both prints exist in order: 42 then 100
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bytes32 printTopic = keccak256("Print(uint256[])");
        uint256 print42Pos = type(uint256).max;
        uint256 print100Pos = type(uint256).max;
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == printTopic) {
                uint256[] memory vals = abi.decode(logs[i].data, (uint256[]));
                if (vals[0] == 42) print42Pos = i;
                if (vals[0] == 100) print100Pos = i;
            }
        }
        assertTrue(print42Pos < print100Pos, "42 prints before 100");
    }

    function testWhileLoopStillWorks() public {
        string memory src = "x = 0\nwhile x < 5:\n    x = x + 1\nprint(x)\n";
        bytes memory bytecode = _compile(src);
        VM pyVm = new VM();
        vm.recordLogs();
        pyVm.execute(bytecode);
        assertEq(_getLastPrint(), 5, "basic while still works");
    }

    function testForLoopStillWorks() public {
        string memory src = "s = 0\nfor i in range(5):\n    s = s + i\nprint(s)\n";
        bytes memory bytecode = _compile(src);
        VM pyVm = new VM();
        vm.recordLogs();
        pyVm.execute(bytecode);
        assertEq(_getLastPrint(), 10, "0+1+2+3+4 = 10");
    }
}
