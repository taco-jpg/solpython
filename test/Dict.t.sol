// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import {Lexer} from "../src/phases/Lexer.sol";
import {Parser} from "../src/phases/Parser.sol";
import {SemanticAnalyzer} from "../src/phases/SemanticAnalyzer.sol";
import {ConstantFolder} from "../src/optimizer/ConstantFolder.sol";
import {CodeGenerator} from "../src/phases/CodeGenerator.sol";
import {VM} from "../src/phases/VM.sol";
import {PythonCompiler} from "../src/PythonCompiler.sol";
import {NodeType} from "../src/types/ASTNode.sol";

contract DictTest is Test {
    PythonCompiler compiler;

    function setUp() public {
        compiler = new PythonCompiler();
    }

    // Helper: parse and fold, return parser
    function _parse(string memory src) internal returns (Parser) {
        Lexer lexer = new Lexer();
        lexer.tokenize(src);
        Parser parser = new Parser();
        parser.parse(lexer);
        return parser;
    }

    // Helper: generate bytecode from parser
    function _generate(Parser parser) internal returns (bytes memory) {
        CodeGenerator gen = new CodeGenerator();
        return gen.generate(parser);
    }

    // Helper: compile and execute
    function _run(string memory src) internal returns (VM) {
        bytes memory bc = compiler.compile(src);
        VM vm = new VM();
        vm.execute(bc);
        return vm;
    }

    // Test 1: {} creates empty dict (DICT_LITERAL node)
    function testEmptyDictNode() public {
        Parser parser = _parse("d = {}\n");
        // Find DICT_LITERAL node
        bool found = false;
        uint256 count = parser.getNodeCount();
        for (uint256 i = 0; i < count; i++) {
            if (parser.getNodeType(i) == NodeType.DICT_LITERAL) {
                found = true;
                assertEq(parser.getAuxCount(i), 0, "Empty dict should have 0 pairs");
            }
        }
        assertTrue(found, "Should have DICT_LITERAL node");
    }

    // Test 2: {1: 10, 2: 20} creates dict with 2 entries
    function testDictLiteralNode() public {
        Parser parser = _parse("d = {1: 10, 2: 20}\n");
        bool found = false;
        uint256 count = parser.getNodeCount();
        for (uint256 i = 0; i < count; i++) {
            if (parser.getNodeType(i) == NodeType.DICT_LITERAL) {
                found = true;
                assertEq(parser.getAuxCount(i), 2, "Should have 2 pairs");
            }
        }
        assertTrue(found, "Should have DICT_LITERAL node");
    }

    // Test 3: {1, 2, 3} creates set with 3 elements
    function testSetLiteralNode() public {
        Parser parser = _parse("s = {1, 2, 3}\n");
        bool found = false;
        uint256 count = parser.getNodeCount();
        for (uint256 i = 0; i < count; i++) {
            if (parser.getNodeType(i) == NodeType.SET_LITERAL) {
                found = true;
                assertEq(parser.getAuxCount(i), 3, "Should have 3 elements");
            }
        }
        assertTrue(found, "Should have SET_LITERAL node");
    }

    // Test 4: Empty dict bytecode is valid
    function testEmptyDictBytecode() public {
        bytes memory bc = compiler.compile("d = {}\n");
        assertTrue(bc.length > 7, "Should produce valid bytecode");
    }

    // Test 5: Dict literal bytecode is valid
    function testDictLiteralBytecode() public {
        bytes memory bc = compiler.compile("d = {1: 10, 2: 20}\n");
        assertTrue(bc.length > 7, "Should produce valid bytecode");
    }

    // Test 6: Set literal bytecode is valid
    function testSetLiteralBytecode() public {
        bytes memory bc = compiler.compile("s = {1, 2, 3}\n");
        assertTrue(bc.length > 7, "Should produce valid bytecode");
    }

    // Test 7: Empty dict executes without error
    function testEmptyDictExecutes() public {
        _run("d = {}\n");
    }

    // Test 8: Dict with pairs executes without error
    function testDictExecutes() public {
        _run("d = {1: 10, 2: 20}\n");
    }

    // Test 9: Set executes without error
    function testSetExecutes() public {
        _run("s = {1, 2, 3}\n");
    }

    // Test 10: Dict with string keys
    function testDictStringKeys() public {
        Parser parser = _parse("d = {\"a\": 1, \"b\": 2}\n");
        bool found = false;
        uint256 count = parser.getNodeCount();
        for (uint256 i = 0; i < count; i++) {
            if (parser.getNodeType(i) == NodeType.DICT_LITERAL) {
                found = true;
                assertEq(parser.getAuxCount(i), 2, "Should have 2 pairs");
            }
        }
        assertTrue(found, "Should have DICT_LITERAL node");
    }

    // Test 11: Set with single element
    function testSetSingleElement() public {
        Parser parser = _parse("s = {42}\n");
        bool found = false;
        uint256 count = parser.getNodeCount();
        for (uint256 i = 0; i < count; i++) {
            if (parser.getNodeType(i) == NodeType.SET_LITERAL) {
                found = true;
                assertEq(parser.getAuxCount(i), 1, "Should have 1 element");
            }
        }
        assertTrue(found, "Should have SET_LITERAL node");
    }

    // Test 12: Multiple dicts in same program
    function testMultipleDicts() public {
        Parser parser = _parse("a = {1: 2}\nb = {3: 4}\n");
        uint256 dictCount = 0;
        uint256 count = parser.getNodeCount();
        for (uint256 i = 0; i < count; i++) {
            if (parser.getNodeType(i) == NodeType.DICT_LITERAL) {
                dictCount++;
            }
        }
        assertEq(dictCount, 2, "Should have 2 DICT_LITERAL nodes");
    }
}
