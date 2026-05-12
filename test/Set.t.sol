// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import {Lexer} from "../src/phases/Lexer.sol";
import {Parser} from "../src/phases/Parser.sol";
import {CodeGenerator} from "../src/phases/CodeGenerator.sol";
import {VM} from "../src/phases/VM.sol";
import {PythonCompiler} from "../src/PythonCompiler.sol";
import {NodeType} from "../src/types/ASTNode.sol";

contract SetTest is Test {
    PythonCompiler compiler;

    function setUp() public {
        compiler = new PythonCompiler();
    }

    function _parse(string memory src) internal returns (Parser) {
        Lexer lexer = new Lexer();
        lexer.tokenize(src);
        Parser parser = new Parser();
        parser.parse(lexer);
        return parser;
    }

    function _run(string memory src) internal returns (VM) {
        bytes memory bc = compiler.compile(src);
        VM vm = new VM();
        vm.execute(bc);
        return vm;
    }

    // Test 1: {1, 2, 3} creates set of size 3
    function testSetLiteral() public {
        Parser parser = _parse("s = {1, 2, 3}\n");
        bool found = false;
        uint256 count = parser.getNodeCount();
        for (uint256 i = 0; i < count; i++) {
            if (parser.getNodeType(i) == NodeType.SET_LITERAL) {
                found = true;
                assertEq(parser.getAuxCount(i), 3);
            }
        }
        assertTrue(found);
    }

    // Test 2: Set executes without error
    function testSetExecutes() public {
        _run("s = {1, 2, 3}\n");
    }

    // Test 3: Empty set
    function testEmptySet() public {
        // {} is parsed as DICT_LITERAL (Python convention)
        // {1} with one element is SET_LITERAL
        Parser parser = _parse("s = {1}\n");
        bool found = false;
        uint256 count = parser.getNodeCount();
        for (uint256 i = 0; i < count; i++) {
            if (parser.getNodeType(i) == NodeType.SET_LITERAL) {
                found = true;
                assertEq(parser.getAuxCount(i), 1);
            }
        }
        assertTrue(found);
    }

    // Test 4: Set with duplicates
    function testSetDuplicates() public {
        Parser parser = _parse("s = {1, 1, 2}\n");
        bool found = false;
        uint256 count = parser.getNodeCount();
        for (uint256 i = 0; i < count; i++) {
            if (parser.getNodeType(i) == NodeType.SET_LITERAL) {
                found = true;
                // Parser stores 3 elements (dedup happens at VM level)
                assertEq(parser.getAuxCount(i), 3);
            }
        }
        assertTrue(found);
    }

    // Test 5: Set bytecode is valid
    function testSetBytecode() public {
        bytes memory bc = compiler.compile("s = {1, 2, 3}\n");
        assertTrue(bc.length > 7);
    }

    // Test 6: Set with 5 elements
    function testSetFiveElements() public {
        Parser parser = _parse("s = {1, 2, 3, 4, 5}\n");
        bool found = false;
        uint256 count = parser.getNodeCount();
        for (uint256 i = 0; i < count; i++) {
            if (parser.getNodeType(i) == NodeType.SET_LITERAL) {
                found = true;
                assertEq(parser.getAuxCount(i), 5);
            }
        }
        assertTrue(found);
    }

    // Test 7: Set and dict disambiguation
    function testSetVsDict() public {
        // {1: 2} should be DICT_LITERAL
        Parser parser1 = _parse("d = {1: 2}\n");
        bool hasDict = false;
        uint256 count1 = parser1.getNodeCount();
        for (uint256 i = 0; i < count1; i++) {
            if (parser1.getNodeType(i) == NodeType.DICT_LITERAL) hasDict = true;
        }
        assertTrue(hasDict, "{1: 2} should be DICT_LITERAL");

        // {1, 2} should be SET_LITERAL
        Parser parser2 = _parse("s = {1, 2}\n");
        bool hasSet = false;
        uint256 count2 = parser2.getNodeCount();
        for (uint256 i = 0; i < count2; i++) {
            if (parser2.getNodeType(i) == NodeType.SET_LITERAL) hasSet = true;
        }
        assertTrue(hasSet, "{1, 2} should be SET_LITERAL");
    }

    // Test 8: Set in function
    function testSetInFunction() public {
        bytes memory bc = compiler.compile("def f():\n    s = {1, 2, 3}\n    return 0\nf()\n");
        assertTrue(bc.length > 7);
    }
}
