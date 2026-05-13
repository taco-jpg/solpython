// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import {Lexer} from "../src/phases/Lexer.sol";
import {Parser} from "../src/phases/Parser.sol";
import {CodeGenerator} from "../src/phases/CodeGenerator.sol";
import {VM} from "../src/phases/VM.sol";
import {PythonCompiler} from "../src/PythonCompiler.sol";

contract ExceptionTest is Test {
    event Print(uint256[] values);

    PythonCompiler private compiler;

    function setUp() public {
        compiler = new PythonCompiler();
    }

    function _compileAndRun(string memory src) internal returns (VM) {
        bytes memory bytecode = compiler.compile(src);
        VM vm = new VM();
        vm.execute(bytecode);
        return vm;
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

    // ==================== Parser Tests ====================

    function testTryExceptParsed() public {
        Lexer lexer = new Lexer();
        lexer.tokenize("try:\n    x = 1\nexcept:\n    x = 2\n");
        Parser parser = new Parser();
        parser.parse(lexer);
        // Should parse without error
        assertTrue(parser.getNodeCount() > 0, "should produce AST nodes");
    }

    function testTryExceptFinallyParsed() public {
        Lexer lexer = new Lexer();
        lexer.tokenize("try:\n    x = 1\nexcept:\n    x = 2\nfinally:\n    x = 3\n");
        Parser parser = new Parser();
        parser.parse(lexer);
        assertTrue(parser.getNodeCount() > 0, "should produce AST nodes");
    }

    function testRaiseParsed() public {
        Lexer lexer = new Lexer();
        lexer.tokenize("raise 42\n");
        Parser parser = new Parser();
        parser.parse(lexer);
        assertTrue(parser.getNodeCount() > 0, "should produce AST nodes");
    }

    function testRaiseWithValueParsed() public {
        Lexer lexer = new Lexer();
        lexer.tokenize("try:\n    x = 1\nexcept:\n    raise 99\n");
        Parser parser = new Parser();
        parser.parse(lexer);
        assertTrue(parser.getNodeCount() > 0, "should produce AST nodes");
    }

    // ==================== VM Tests ====================

    function testTryExceptBasic() public {
        string memory src = "x = 0\ntry:\n    x = 1\nexcept:\n    x = 2\nprint(x)\n";
        _compileAndRun(src);
        // x should be 1 (no exception raised)
    }

    function testRaiseInTry() public {
        string memory src = "x = 0\ntry:\n    x = 1\n    raise 99\n    x = 2\nexcept:\n    x = 3\nprint(x)\n";
        _compileAndRun(src);
        // x should be 3 (exception caught)
    }

    function testFinallyExecutes() public {
        string memory src = "x = 0\ntry:\n    x = 1\nexcept:\n    x = 2\nfinally:\n    x = x + 10\nprint(x)\n";
        _compileAndRun(src);
        // x should be 11 (1 + 10)
    }

    function testRaiseWithFinally() public {
        string memory src = "x = 0\ntry:\n    raise 99\n    x = 1\nexcept:\n    x = 2\nfinally:\n    x = x + 10\nprint(x)\n";
        _compileAndRun(src);
        // x should be 12 (2 + 10)
    }

    function testExceptionValue() public {
        string memory src = "x = 0\ntry:\n    raise 42\nexcept:\n    x = 1\nprint(x)\n";
        _compileAndRun(src);
        // x should be 1
    }

    function testTryWithoutExcept() public {
        // try without except should still work (finally only)
        string memory src = "x = 0\ntry:\n    x = 1\nfinally:\n    x = x + 10\nprint(x)\n";
        _compileAndRun(src);
        // x should be 11
    }

    // ==================== Compiler Integration ====================

    function testExceptionCompileAndExecute() public {
        string memory src = "x = 0\ntry:\n    x = 1\nexcept:\n    x = 2\nprint(x)\n";
        bytes memory bytecode = compiler.compile(src);
        assertTrue(bytecode.length > 0, "should compile");
        VM vm = new VM();
        vm.execute(bytecode);
    }

    // ==================== Lexer Keywords ====================

    function testTryKeyword() public {
        Lexer lexer = new Lexer();
        lexer.tokenize("try:\n");
        // try should be tokenized as KW_TRY
        assertTrue(lexer.getTokenCount() > 0, "should produce tokens");
    }

    function testExceptKeyword() public {
        Lexer lexer = new Lexer();
        lexer.tokenize("except:\n");
        assertTrue(lexer.getTokenCount() > 0, "should produce tokens");
    }

    function testFinallyKeyword() public {
        Lexer lexer = new Lexer();
        lexer.tokenize("finally:\n");
        assertTrue(lexer.getTokenCount() > 0, "should produce tokens");
    }

    function testRaiseKeyword() public {
        Lexer lexer = new Lexer();
        lexer.tokenize("raise\n");
        assertTrue(lexer.getTokenCount() > 0, "should produce tokens");
    }

    // ==================== FIX-6: Multiple except + finally backpatch ====================

    function testTwoExceptFirstMatches() public {
        // First except matches, finally runs, control continues
        string memory src = "x = 0\ntry:\n    raise 1\nexcept:\n    x = 1\nexcept:\n    x = 2\nfinally:\n    x = x + 10\nprint(x)\n";
        bytes memory bytecode = compiler.compile(src);
        VM pyVm = new VM();
        vm.recordLogs();
        pyVm.execute(bytecode);
        assertEq(_getLastPrint(), 11, "first except matches, finally adds 10");
    }

    function testTwoExceptNoException() public {
        // No exception, finally still runs
        string memory src = "x = 0\ntry:\n    x = 1\nexcept:\n    x = 2\nexcept:\n    x = 3\nfinally:\n    x = x + 10\nprint(x)\n";
        bytes memory bytecode = compiler.compile(src);
        VM pyVm = new VM();
        vm.recordLogs();
        pyVm.execute(bytecode);
        assertEq(_getLastPrint(), 11, "no exception, x=1, finally adds 10");
    }

    function testFinallyAlwaysRuns() public {
        // Finally runs even without except
        string memory src = "x = 0\ntry:\n    x = 5\nfinally:\n    x = x + 100\nprint(x)\n";
        bytes memory bytecode = compiler.compile(src);
        VM pyVm = new VM();
        vm.recordLogs();
        pyVm.execute(bytecode);
        assertEq(_getLastPrint(), 105, "finally always runs");
    }

    function testFinallyWithRaise() public {
        // Exception caught, finally runs
        string memory src = "x = 0\ntry:\n    raise 42\nexcept:\n    x = 10\nfinally:\n    x = x + 100\nprint(x)\n";
        bytes memory bytecode = compiler.compile(src);
        VM pyVm = new VM();
        vm.recordLogs();
        pyVm.execute(bytecode);
        assertEq(_getLastPrint(), 110, "except catches, finally adds 100");
    }

    function testNestedTryExcept() public {
        // Inner raises, outer catches
        string memory src = "x = 0\ntry:\n    try:\n        raise 1\n    except:\n        x = 1\n        raise 2\nexcept:\n    x = x + 10\nprint(x)\n";
        bytes memory bytecode = compiler.compile(src);
        VM pyVm = new VM();
        vm.recordLogs();
        pyVm.execute(bytecode);
        assertEq(_getLastPrint(), 11, "inner sets x=1, re-raises, outer adds 10");
    }

    function testExceptWithFinallyControlFlow() public {
        // After except body, control jumps to finally and continues
        string memory src = "x = 0\ntry:\n    raise 1\nexcept:\n    x = 5\nfinally:\n    x = x + 1\nprint(x)\nprint(x + 1)\n";
        bytes memory bytecode = compiler.compile(src);
        VM pyVm = new VM();
        vm.recordLogs();
        pyVm.execute(bytecode);
        // Last print: x + 1 = 7 (x=5 from except, +1 from finally)
        assertEq(_getLastPrint(), 7, "control continues after try/except/finally");
    }
}
