// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
import "forge-std/Test.sol";
import {Lexer} from "../src/phases/Lexer.sol";
import {Parser} from "../src/phases/Parser.sol";
import {SemanticAnalyzer} from "../src/phases/SemanticAnalyzer.sol";
import {CodeGenerator} from "../src/phases/CodeGenerator.sol";
import {VM} from "../src/phases/VM.sol";

contract VarRangeTest is Test {
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

    function testVarRange1Arg() public {
        // range(n) where n is a variable
        string memory src = "n = 5\ntotal = 0\nfor i in range(n):\n    total = total + i\nprint(total)\n";
        bytes memory bytecode = _compile(src);
        VM pyVm = new VM();
        vm.recordLogs();
        pyVm.execute(bytecode);
        assertEq(_getLastPrint(), 10, "sum 0..4 should be 10");
    }

    function testVarRange2Arg() public {
        // range(start, stop) where both are variables
        string memory src = "a = 3\nb = 7\ntotal = 0\nfor i in range(a, b):\n    total = total + i\nprint(total)\n";
        bytes memory bytecode = _compile(src);
        VM pyVm = new VM();
        vm.recordLogs();
        pyVm.execute(bytecode);
        assertEq(_getLastPrint(), 18, "sum 3..6 should be 18");
    }

    function testVarRange3Arg() public {
        // range(start, stop, step) where all are variables
        string memory src = "a = 0\nb = 10\ns = 2\ntotal = 0\nfor i in range(a, b, s):\n    total = total + i\nprint(total)\n";
        bytes memory bytecode = _compile(src);
        VM pyVm = new VM();
        vm.recordLogs();
        pyVm.execute(bytecode);
        assertEq(_getLastPrint(), 20, "sum 0,2,4,6,8 should be 20");
    }

    function testVarRangeExpr() public {
        // range with expression arguments
        string memory src = "n = 3\ntotal = 0\nfor i in range(n * 2):\n    total = total + i\nprint(total)\n";
        bytes memory bytecode = _compile(src);
        VM pyVm = new VM();
        vm.recordLogs();
        pyVm.execute(bytecode);
        assertEq(_getLastPrint(), 15, "sum 0..5 should be 15");
    }

    function testVarRangeNested() public {
        // Nested for loops with variable ranges
        string memory src = "n = 3\ntotal = 0\nfor i in range(n):\n    for j in range(n):\n        total = total + 1\nprint(total)\n";
        bytes memory bytecode = _compile(src);
        VM pyVm = new VM();
        vm.recordLogs();
        pyVm.execute(bytecode);
        assertEq(_getLastPrint(), 9, "3x3 nested loop should be 9");
    }
}
