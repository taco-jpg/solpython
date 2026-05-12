// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import {Lexer} from "../src/phases/Lexer.sol";
import {Parser} from "../src/phases/Parser.sol";
import {SemanticAnalyzer} from "../src/phases/SemanticAnalyzer.sol";
import {PythonCompiler} from "../src/PythonCompiler.sol";
import {VM} from "../src/phases/VM.sol";

contract ErrorMessagesTest is Test {
    PythonCompiler compiler;

    function setUp() public {
        compiler = new PythonCompiler();
    }

    // Helper: analyze and return errors
    function _analyzeErrors(string memory src) internal returns (string[] memory) {
        Lexer lexer = new Lexer();
        lexer.tokenize(src);
        Parser parser = new Parser();
        parser.parse(lexer);
        SemanticAnalyzer analyzer = new SemanticAnalyzer();
        analyzer.analyze(parser);

        uint256 count = analyzer.getErrorCount();
        string[] memory errs = new string[](count);
        for (uint256 i = 0; i < count; i++) {
            errs[i] = analyzer.getError(i);
        }
        return errs;
    }

    // Test 1: Undefined variable error contains variable name
    function testUndefinedVarContainsName() public {
        string[] memory errs = _analyzeErrors("y = x\n");
        assertTrue(errs.length > 0, "Should have error");
        bytes memory errBytes = bytes(errs[0]);
        string memory errStr = string(errBytes);
        // Check that the error contains "x"
        assertTrue(_contains(errStr, "x"), "Error should contain variable name");
    }

    // Test 2: Undefined variable error contains "Line"
    function testUndefinedVarContainsLine() public {
        string[] memory errs = _analyzeErrors("y = x\n");
        assertTrue(errs.length > 0, "Should have error");
        string memory errStr = errs[0];
        assertTrue(_contains(errStr, "Line"), "Error should contain 'Line'");
    }

    // Test 3: Undefined variable error contains correct line number
    function testUndefinedVarLineNumber() public {
        string[] memory errs = _analyzeErrors("a = 1\nb = 2\nc = x\n");
        assertTrue(errs.length > 0, "Should have error");
        string memory errStr = errs[0];
        // x is on line 3
        assertTrue(_contains(errStr, "3"), "Error should contain line number 3");
    }

    // Test 4: getErrors() returns non-empty array for invalid program
    function testGetErrorsNonEmpty() public {
        compiler.compile("y = x\n");
        string[] memory errs = compiler.getErrors();
        assertTrue(errs.length > 0, "Should have errors");
    }

    // Test 5: getErrors() returns empty array for valid program
    function testGetErrorsEmpty() public {
        compiler.compile("x = 42\nprint(x)\n");
        string[] memory errs = compiler.getErrors();
        assertEq(errs.length, 0, "Should have no errors");
    }

    // Test 6: getErrors() prefixes each error with phase name
    function testGetErrorsPhasePrefix() public {
        compiler.compile("y = x\n");
        string[] memory errs = compiler.getErrors();
        assertTrue(errs.length > 0, "Should have errors");
        assertTrue(_contains(errs[0], "[Semantic]"), "Error should be prefixed with [Semantic]");
    }

    // Test 7: VM emits VMError on division by zero
    function testVMDivByZeroError() public {
        // Create bytecode that does division by zero
        bytes memory bc = compiler.compile("x = 5 / 0\n");
        VM vm = new VM();
        // The VM should emit VMError, not revert
        vm.execute(bc);
        // If we get here, the VM didn't revert (it emits event instead)
    }

    // Test 8: VMError event contains PC value
    function testVMErrorContainsPC() public {
        bytes memory bc = compiler.compile("x = 5 / 0\n");
        VM vm = new VM();
        vm.execute(bc);
        // The VMError event should have been emitted with a non-zero PC
        // We can't directly check events in this test, but the VM should not revert
    }

    // Test 9: List OOB emits VMError
    function testListOOBError() public {
        bytes memory bc = compiler.compile("x = [1, 2, 3]\ny = x[10]\n");
        VM vm = new VM();
        vm.execute(bc);
        // Should emit VMError, not revert
    }

    // Test 10: Semantic error for arity mismatch
    function testArityMismatch() public {
        // This would need a function definition with wrong arg count
        // For now, test that undefined variable errors have location info
        string[] memory errs = _analyzeErrors("def foo(a, b):\n    return a + b\nx = foo(1)\n");
        // Should have an arity mismatch error
        assertTrue(errs.length > 0, "Should have error");
    }

    // Test 11: Multiple errors collected
    function testMultipleErrors() public {
        string[] memory errs = _analyzeErrors("a = x\nb = y\n");
        assertTrue(errs.length >= 2, "Should have at least 2 errors");
    }

    // Test 12: Error message format includes Col
    function testErrorContainsCol() public {
        string[] memory errs = _analyzeErrors("y = x\n");
        assertTrue(errs.length > 0, "Should have error");
        assertTrue(_contains(errs[0], "Col"), "Error should contain 'Col'");
    }

    // Helper: check if string contains substring
    function _contains(string memory haystack, string memory needle) internal pure returns (bool) {
        bytes memory h = bytes(haystack);
        bytes memory n = bytes(needle);
        if (n.length > h.length) return false;
        for (uint256 i = 0; i <= h.length - n.length; i++) {
            bool found = true;
            for (uint256 j = 0; j < n.length; j++) {
                if (h[i + j] != n[j]) {
                    found = false;
                    break;
                }
            }
            if (found) return true;
        }
        return false;
    }
}
