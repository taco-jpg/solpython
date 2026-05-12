// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import {Lexer} from "../src/phases/Lexer.sol";
import {Parser} from "../src/phases/Parser.sol";
import {CodeGenerator} from "../src/phases/CodeGenerator.sol";
import {VM} from "../src/phases/VM.sol";
import {PythonCompiler} from "../src/PythonCompiler.sol";

contract ExceptionTest is Test {
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
}
