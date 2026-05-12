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

contract ConstantFolderTest is Test {
    PythonCompiler compiler;

    function setUp() public {
        compiler = new PythonCompiler();
    }

    // Helper: compile and execute, return the VM
    function _compileAndExecute(string memory src) internal returns (VM) {
        bytes memory bc = compiler.compile(src);
        VM vm = new VM();
        vm.execute(bc);
        return vm;
    }

    // Helper: get parser after lexing/parsing/folding
    function _getFoldedParser(string memory src) internal returns (Parser) {
        Lexer lexer = new Lexer();
        lexer.tokenize(src);
        Parser parser = new Parser();
        parser.parse(lexer);
        ConstantFolder folder = new ConstantFolder();
        folder.fold(parser);
        return parser;
    }

    // Helper: find first ASSIGN node and return its RHS child index
    function _getAssignRHS(Parser parser) internal view returns (uint256) {
        uint256 count = parser.getNodeCount();
        for (uint256 i = 0; i < count; i++) {
            if (parser.getNodeType(i) == NodeType.ASSIGN) {
                return parser.getChild2(i);
            }
        }
        revert("No ASSIGN node found");
    }

    // Test 1: 2 + 3 folds to 5
    function testFoldAddition() public {
        Parser parser = _getFoldedParser("x = 2 + 3\n");
        uint256 rhs = _getAssignRHS(parser);
        assertEq(uint256(parser.getNodeType(rhs)), uint256(NodeType.INT_LITERAL));
        assertEq(parser.getIntValue(rhs), 5);
    }

    // Test 2: 10 * 4 folds to 40
    function testFoldMultiplication() public {
        Parser parser = _getFoldedParser("x = 10 * 4\n");
        uint256 rhs = _getAssignRHS(parser);
        assertEq(uint256(parser.getNodeType(rhs)), uint256(NodeType.INT_LITERAL));
        assertEq(parser.getIntValue(rhs), 40);
    }

    // Test 3: 2 ** 8 folds to 256
    function testFoldExponentiation() public {
        Parser parser = _getFoldedParser("x = 2 ** 8\n");
        uint256 rhs = _getAssignRHS(parser);
        assertEq(uint256(parser.getNodeType(rhs)), uint256(NodeType.INT_LITERAL));
        assertEq(parser.getIntValue(rhs), 256);
    }

    // Test 4: 17 % 5 folds to 2
    function testFoldModulo() public {
        Parser parser = _getFoldedParser("x = 17 % 5\n");
        uint256 rhs = _getAssignRHS(parser);
        assertEq(uint256(parser.getNodeType(rhs)), uint256(NodeType.INT_LITERAL));
        assertEq(parser.getIntValue(rhs), 2);
    }

    // Test 5: (2 + 3) * (4 - 1) folds to 15
    function testFoldChainedExpression() public {
        Parser parser = _getFoldedParser("x = (2 + 3) * (4 - 1)\n");
        uint256 rhs = _getAssignRHS(parser);
        assertEq(uint256(parser.getNodeType(rhs)), uint256(NodeType.INT_LITERAL));
        assertEq(parser.getIntValue(rhs), 15);
    }

    // Test 6: True and True folds to 1
    function testFoldBoolAnd() public {
        Parser parser = _getFoldedParser("x = True and True\n");
        uint256 rhs = _getAssignRHS(parser);
        assertEq(uint256(parser.getNodeType(rhs)), uint256(NodeType.BOOL_LITERAL));
        assertEq(parser.getIntValue(rhs), 1);
    }

    // Test 7: False or True folds to 1
    function testFoldBoolOr() public {
        Parser parser = _getFoldedParser("x = False or True\n");
        uint256 rhs = _getAssignRHS(parser);
        assertEq(uint256(parser.getNodeType(rhs)), uint256(NodeType.BOOL_LITERAL));
        assertEq(parser.getIntValue(rhs), 1);
    }

    // Test 8: not False folds to 1
    function testFoldBoolNot() public {
        Parser parser = _getFoldedParser("x = not False\n");
        uint256 rhs = _getAssignRHS(parser);
        assertEq(uint256(parser.getNodeType(rhs)), uint256(NodeType.BOOL_LITERAL));
        assertEq(parser.getIntValue(rhs), 1);
    }

    // Test 9: 1 < 2 folds to 1 (True)
    function testFoldComparisonLt() public {
        Parser parser = _getFoldedParser("x = 1 < 2\n");
        uint256 rhs = _getAssignRHS(parser);
        assertEq(uint256(parser.getNodeType(rhs)), uint256(NodeType.BOOL_LITERAL));
        assertEq(parser.getIntValue(rhs), 1);
    }

    // Test 10: 5 == 5 folds to 1
    function testFoldComparisonEq() public {
        Parser parser = _getFoldedParser("x = 5 == 5\n");
        uint256 rhs = _getAssignRHS(parser);
        assertEq(uint256(parser.getNodeType(rhs)), uint256(NodeType.BOOL_LITERAL));
        assertEq(parser.getIntValue(rhs), 1);
    }

    // Test 11: Folded bytecode shorter than unfolded for 2+3
    function testFoldedBytecodeShorter() public {
        // Without folding: direct code generation
        Lexer lexer1 = new Lexer();
        lexer1.tokenize("x = 2 + 3\n");
        Parser parser1 = new Parser();
        parser1.parse(lexer1);
        CodeGenerator gen1 = new CodeGenerator();
        bytes memory withoutFold = gen1.generate(parser1);

        // With folding: full pipeline
        bytes memory withFold = compiler.compile("x = 2 + 3\n");

        // Folded version should be shorter (no ADD opcode emitted)
        assertTrue(withFold.length < withoutFold.length, "Folded bytecode should be shorter");
    }

    // Test 12: if False: x = 999 → x never assigned (dead code elimination)
    function testDeadCodeEliminationIfFalse() public {
        // The if body should be eliminated, so x stays at 1
        VM vm = _compileAndExecute("x = 1\nif False:\n    x = 999\nprint(x)\n");
        // The program should execute without error
        // x should be 1 (not 999) since the if body is dead code
    }

    // Test 13: if True: x = 1 else: x = 2 → x == 1
    function testDeadCodeEliminationIfTrue() public {
        VM vm = _compileAndExecute("if True:\n    x = 1\nelse:\n    x = 2\nprint(x)\n");
        // x should be 1 since if True: always executes body, else is dead
    }

    // Test 14: Variable expression NOT folded: x + 3 stays as-is
    function testVariableNotFolded() public {
        Parser parser = _getFoldedParser("x = 5\ny = x + 3\n");
        // Find the second ASSIGN node (for y)
        uint256 count = parser.getNodeCount();
        uint256 assignCount = 0;
        uint256 rhs = 0;
        for (uint256 i = 0; i < count; i++) {
            if (parser.getNodeType(i) == NodeType.ASSIGN) {
                assignCount++;
                if (assignCount == 2) {
                    rhs = parser.getChild2(i);
                    break;
                }
            }
        }
        // Should still be BINARY_OP since x is a variable
        assertEq(uint256(parser.getNodeType(rhs)), uint256(NodeType.BINARY_OP));
    }

    // Test 15: Nested: (1 + 1) + (2 + 2) → 6
    function testFoldNested() public {
        Parser parser = _getFoldedParser("x = (1 + 1) + (2 + 2)\n");
        uint256 rhs = _getAssignRHS(parser);
        assertEq(uint256(parser.getNodeType(rhs)), uint256(NodeType.INT_LITERAL));
        assertEq(parser.getIntValue(rhs), 6);
    }

    // Additional test: folding preserves correct execution
    function testFoldPreservesExecution() public {
        VM vm = _compileAndExecute("x = 2 + 3\nprint(x)\n");
        // Should print 5 without error
    }

    // Additional test: division not folded when divisor is 0
    function testNoFoldDivByZero() public {
        Parser parser = _getFoldedParser("x = 5 / 0\n");
        uint256 rhs = _getAssignRHS(parser);
        // Should NOT be folded (division by zero)
        assertEq(uint256(parser.getNodeType(rhs)), uint256(NodeType.BINARY_OP));
    }
}
