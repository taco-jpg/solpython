// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import {Lexer} from "../src/phases/Lexer.sol";
import {Parser} from "../src/phases/Parser.sol";
import {SemanticAnalyzer} from "../src/phases/SemanticAnalyzer.sol";
import {CodeGenerator} from "../src/phases/CodeGenerator.sol";
import {VM} from "../src/phases/VM.sol";

contract EnumerateZipTest is Test {
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

    // ==================== Enumerate ====================

    function testEnumerateBasic() public {
        string memory src = "total = 0\nfor i, x in enumerate([10, 20, 30]):\n    total = total + i + x\nprint(total)\n";
        bytes memory bytecode = _compile(src);
        VM pyVm = new VM();
        vm.recordLogs();
        pyVm.execute(bytecode);
        // i=0,x=10 + i=1,x=20 + i=2,x=30 = 10 + 21 + 32 = 63
        assertEq(_getLastPrint(), 63, "enumerate sum: 0+10 + 1+20 + 2+30 = 63");
    }

    function testEnumerateIndex() public {
        string memory src = "s = 0\nfor i, x in enumerate([5, 10, 15]):\n    s = s + i * 100 + x\nprint(s)\n";
        bytes memory bytecode = _compile(src);
        VM pyVm = new VM();
        vm.recordLogs();
        pyVm.execute(bytecode);
        // 0*100+5 + 1*100+10 + 2*100+15 = 5 + 110 + 215 = 330
        assertEq(_getLastPrint(), 330, "0*100+5 + 1*100+10 + 2*100+15 = 330");
    }

    function testEnumerateWithVariable() public {
        string memory src = "lst = [100, 200]\ntotal = 0\nfor i, v in enumerate(lst):\n    total = total + i + v\nprint(total)\n";
        bytes memory bytecode = _compile(src);
        VM pyVm = new VM();
        vm.recordLogs();
        pyVm.execute(bytecode);
        // 0+100 + 1+200 = 301
        assertEq(_getLastPrint(), 301, "0+100 + 1+200 = 301");
    }

    // ==================== Zip ====================

    function testZipBasic() public {
        string memory src = "total = 0\nfor a, b in zip([1, 2, 3], [10, 20, 30]):\n    total = total + a + b\nprint(total)\n";
        bytes memory bytecode = _compile(src);
        VM pyVm = new VM();
        vm.recordLogs();
        pyVm.execute(bytecode);
        // 1+10 + 2+20 + 3+30 = 66
        assertEq(_getLastPrint(), 66, "zip sum: 1+10 + 2+20 + 3+30 = 66");
    }

    function testZipWithVariables() public {
        string memory src = "a = [1, 2, 3]\nb = [4, 5, 6]\ns = 0\nfor x, y in zip(a, b):\n    s = s + x * y\nprint(s)\n";
        bytes memory bytecode = _compile(src);
        VM pyVm = new VM();
        vm.recordLogs();
        pyVm.execute(bytecode);
        // 1*4 + 2*5 + 3*6 = 4 + 10 + 18 = 32
        assertEq(_getLastPrint(), 32, "1*4 + 2*5 + 3*6 = 32");
    }

    function testZipDifferentLengths() public {
        string memory src = "total = 0\nfor a, b in zip([1, 2, 3, 4], [10, 20]):\n    total = total + a + b\nprint(total)\n";
        bytes memory bytecode = _compile(src);
        VM pyVm = new VM();
        vm.recordLogs();
        pyVm.execute(bytecode);
        // zip stops at shorter list: 1+10 + 2+20 = 33
        assertEq(_getLastPrint(), 33, "zip stops at shorter: 1+10 + 2+20 = 33");
    }

    function testForLoopTupleStillWorks() public {
        string memory src = "s = 0\nfor i in range(3):\n    s = s + i\nprint(s)\n";
        bytes memory bytecode = _compile(src);
        VM pyVm = new VM();
        vm.recordLogs();
        pyVm.execute(bytecode);
        assertEq(_getLastPrint(), 3, "basic for loop still works");
    }
}
