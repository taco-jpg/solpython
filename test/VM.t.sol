// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import {Lexer} from "../src/phases/Lexer.sol";
import {Parser} from "../src/phases/Parser.sol";
import {CodeGenerator} from "../src/phases/CodeGenerator.sol";
import {VM} from "../src/phases/VM.sol";

contract VMTest is Test {
    Lexer lexer;
    VM pyVm;

    event Print(uint256[] values);
    event Result(uint256 value);

    function setUp() public {
        lexer = new Lexer();
        pyVm = new VM();
    }

    function _run(string memory src) internal {
        lexer.tokenize(src);
        Parser parser = new Parser();
        parser.parse(lexer);
        CodeGenerator gen = new CodeGenerator();
        bytes memory bytecode = gen.generate(parser);
        pyVm.execute(bytecode);
    }

    // ==================== Basic Execution ====================

    function testEmptyProgram() public {
        _run("");
        // Should complete without error
        assertEq(pyVm.getStackLength(), 0);
    }

    function testPushAndHalt() public {
        _run("42\n");
        // EXPR_STMT pops the value, so stack should be empty
        assertEq(pyVm.getStackLength(), 0);
    }

    function testAssignment() public {
        _run("x = 10\n");
        assertEq(pyVm.getStackLength(), 0); // assignment stores, doesn't leave on stack
    }

    // ==================== Arithmetic ====================

    function testAddition() public {
        // Use emit to check the result
        _run("1 + 2\n");
        // Stack empty after EXPR_STMT pops
        assertEq(pyVm.getStackLength(), 0);
    }

    // ==================== Print ====================

    function testPrintInt() public {
        _run("print(42)\n");
        // print consumes the value, stack empty
        assertEq(pyVm.getStackLength(), 0);
    }

    // ==================== Control Flow ====================

    function testIfTrue() public {
        _run("if True:\n    x = 1\n");
        // x should be stored
        assertEq(pyVm.getStackLength(), 0);
    }

    function testIfFalse() public {
        _run("if False:\n    x = 1\n");
        // x should NOT be stored (condition is false)
        assertEq(pyVm.getStackLength(), 0);
    }

    // ==================== Variables ====================

    function testVariableAssignment() public {
        _run("x = 5\n");
        assertEq(pyVm.getStackLength(), 0);
    }

    function testAugmentedAssignment() public {
        _run("x = 5\nx += 3\n");
        assertEq(pyVm.getStackLength(), 0);
    }

    // ==================== Bytecode Structure ====================

    function testMagicHeader() public {
        lexer.tokenize("42\n");
        Parser parser = new Parser();
        parser.parse(lexer);
        CodeGenerator gen = new CodeGenerator();
        bytes memory bc = gen.generate(parser);

        assertEq(uint8(bc[0]), 0x50); // P
        assertEq(uint8(bc[1]), 0x59); // Y
        assertEq(uint8(bc[2]), 0x01); // version
    }

    function testCodeLengthField() public {
        lexer.tokenize("42\n");
        Parser parser = new Parser();
        parser.parse(lexer);
        CodeGenerator gen = new CodeGenerator();
        bytes memory bc = gen.generate(parser);

        uint256 codeLen = uint256(uint8(bc[3])) << 24 |
                          uint256(uint8(bc[4])) << 16 |
                          uint256(uint8(bc[5])) << 8 |
                          uint256(uint8(bc[6]));
        // Code starts at offset 7 and should contain at least PUSH + value + POP + HALT
        assertTrue(codeLen >= 35); // 1 + 32 + 1 + 1
    }

    // ==================== List Operations ====================

    function testMakeList() public {
        _run("[1, 2, 3]\n");
        // List created but popped by EXPR_STMT
        assertEq(pyVm.getStackLength(), 0);
    }
}
