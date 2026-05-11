// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import {Lexer} from "../src/phases/Lexer.sol";
import {Parser} from "../src/phases/Parser.sol";
import {CodeGenerator} from "../src/phases/CodeGenerator.sol";

contract CodeGeneratorTest is Test {
    Lexer lexer;

    function setUp() public {
        lexer = new Lexer();
    }

    function _gen(string memory src) internal returns (bytes memory) {
        lexer.tokenize(src);
        Parser parser = new Parser();
        parser.parse(lexer);
        CodeGenerator gen = new CodeGenerator();
        return gen.generate(parser);
    }

    function _codeStart(bytes memory bc) internal pure returns (uint256) {
        // Header: 2 magic + 1 version + 4 codeLen = 7 bytes
        return 7;
    }

    // ==================== Basic Tests ====================

    function testEmptyProgram() public {
        bytes memory bc = _gen("");
        assertTrue(bc.length > 0);
        // Should have HALT at code start
        assertEq(uint8(bc[_codeStart(bc)]), 0xFF);
    }

    function testPushInt() public {
        bytes memory bc = _gen("42\n");
        uint256 cs = _codeStart(bc);
        assertEq(uint8(bc[cs]), 0x01); // PUSH
        // Last byte of 32-byte value should be 42
        assertEq(uint8(bc[cs + 32]), 42);
        // Then POP (EXPR_STMT discards), then HALT
        assertEq(uint8(bc[cs + 33]), 0x02); // POP
    }

    function testIntAssignment() public {
        bytes memory bc = _gen("x = 10\n");
        uint256 cs = _codeStart(bc);
        // Should have PUSH 10, then STORE_VAR, then HALT
        assertEq(uint8(bc[cs]), 0x01); // PUSH
        assertEq(uint8(bc[cs + 33]), 0x41); // STORE_VAR
    }

    function testPrintInt() public {
        bytes memory bc = _gen("print(42)\n");
        uint256 cs = _codeStart(bc);
        assertEq(uint8(bc[cs]), 0x01); // PUSH 42
        assertEq(uint8(bc[cs + 33]), 0x80); // PRINT
    }

    function testBinaryAdd() public {
        bytes memory bc = _gen("1 + 2\n");
        uint256 cs = _codeStart(bc);
        assertEq(uint8(bc[cs]), 0x01); // PUSH 1
        assertEq(uint8(bc[cs + 33]), 0x01); // PUSH 2
        assertEq(uint8(bc[cs + 66]), 0x10); // ADD
    }

    function testComparison() public {
        bytes memory bc = _gen("1 < 2\n");
        uint256 cs = _codeStart(bc);
        assertEq(uint8(bc[cs + 66]), 0x22); // LT
    }

    function testIfStatement() public {
        bytes memory bc = _gen("if True:\n    pass\n");
        uint256 cs = _codeStart(bc);
        // PUSH 1 (True), JUMP_IF_FALSE, ...
        assertEq(uint8(bc[cs]), 0x01); // PUSH
        assertEq(uint8(bc[cs + 33]), 0x51); // JUMP_IF_FALSE
    }

    function testWhileLoop() public {
        bytes memory bc = _gen("while True:\n    pass\n");
        uint256 cs = _codeStart(bc);
        assertEq(uint8(bc[cs]), 0x01); // PUSH (condition)
        assertEq(uint8(bc[cs + 33]), 0x51); // JUMP_IF_FALSE
    }

    function testFunctionDef() public {
        bytes memory bc = _gen("def foo():\n    return 42\n");
        uint256 cs = _codeStart(bc);
        // JUMP (over body), then function body starts
        assertEq(uint8(bc[cs]), 0x50); // JUMP
    }

    function testListLiteral() public {
        bytes memory bc = _gen("[1, 2, 3]\n");
        uint256 cs = _codeStart(bc);
        // Should have PUSH 3, PUSH 2, PUSH 1, MAKE_LIST
        // (elements pushed in reverse)
        // Last instruction before HALT should be POP (EXPR_STMT discards)
    }

    function testHasMagicHeader() public {
        bytes memory bc = _gen("42\n");
        assertEq(uint8(bc[0]), 0x50); // P
        assertEq(uint8(bc[1]), 0x59); // Y
        assertEq(uint8(bc[2]), 0x01); // version
    }

    function testStringLiteral() public {
        bytes memory bc = _gen("x = \"hello\"\n");
        uint256 cs = _codeStart(bc);
        assertEq(uint8(bc[cs]), 0x01); // PUSH (string index)
    }

    function testHaltAtEnd() public {
        bytes memory bc = _gen("x = 1\n");
        // Last byte of code section should be HALT
        uint256 codeLen = uint256(uint8(bc[3])) << 24 |
                          uint256(uint8(bc[4])) << 16 |
                          uint256(uint8(bc[5])) << 8 |
                          uint256(uint8(bc[6]));
        uint256 lastCodeByte = 7 + codeLen - 1;
        assertEq(uint8(bc[lastCodeByte]), 0xFF); // HALT
    }
}
