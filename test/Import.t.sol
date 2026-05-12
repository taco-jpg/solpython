// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import {Lexer} from "../src/phases/Lexer.sol";
import {Parser} from "../src/phases/Parser.sol";
import {CodeGenerator} from "../src/phases/CodeGenerator.sol";
import {VM} from "../src/phases/VM.sol";
import {PythonCompiler} from "../src/PythonCompiler.sol";

contract ImportTest is Test {
    PythonCompiler private compiler;

    function setUp() public {
        compiler = new PythonCompiler();
    }

    function _runWithImport(
        string memory mainSrc,
        string memory modName,
        string memory modSrc
    ) internal returns (VM) {
        string[] memory names = new string[](1);
        names[0] = modName;
        string[] memory sources = new string[](1);
        sources[0] = modSrc;

        bytes memory bytecode = compiler.compileWithImports(mainSrc, names, sources);
        VM vm = new VM();
        vm.execute(bytecode);
        return vm;
    }

    // ==================== Basic Import ====================

    function testImportSimpleFunction() public {
        string memory mod = "def add(a, b):\n    return a + b\n";
        string memory main = "from math import add\nx = add(1, 2)\nprint(x)\n";
        _runWithImport(main, "math", mod);
        // Should execute without revert
    }

    function testImportMultipleFunctions() public {
        string memory mod = "def add(a, b):\n    return a + b\ndef mul(a, b):\n    return a * b\n";
        string memory main = "from math import add\nfrom math import mul\nx = add(2, mul(3, 4))\nprint(x)\n";
        _runWithImport(main, "math", mod);
    }

    function testImportFunctionCallsFunction() public {
        // Module with functions that call each other
        string memory mod = "def double(x):\n    return x * 2\n\ndef quadruple(x):\n    return double(double(x))\n";
        string memory main = "from utils import quadruple\nx = quadruple(5)\nprint(x)\n";
        _runWithImport(main, "utils", mod);
    }

    function testImportWithMainCode() public {
        string memory mod = "def square(x):\n    return x * x\n";
        string memory main = "from math import square\ns = 0\nfor i in range(5):\n    s += square(i)\nprint(s)\n";
        _runWithImport(main, "math", mod);
    }

    function testImportParserRecognizesImport() public {
        // Test that the parser correctly creates IMPORT_STMT nodes
        Lexer lexer = new Lexer();
        lexer.tokenize("from math import add\n");
        Parser parser = new Parser();
        parser.parse(lexer);

        // Node 0 is PROGRAM, node 1 should be IMPORT_STMT
        uint256 stmtIdx = parser.getAuxData(parser.getAuxIndex(0));
        assertEq(uint256(parser.getNodeType(stmtIdx)), 15, "should be IMPORT_STMT (enum value 15)");
    }

    function testImportStatementParsed() public {
        // Test that 'import module' is parsed
        Lexer lexer = new Lexer();
        lexer.tokenize("import math\n");
        Parser parser = new Parser();
        parser.parse(lexer);

        uint256 stmtIdx = parser.getAuxData(parser.getAuxIndex(0));
        assertEq(uint256(parser.getNodeType(stmtIdx)), 15, "should be IMPORT_STMT");
        assertEq(parser.getStrValue(stmtIdx), "math", "module name should be math");
    }

    function testFromImportParsed() public {
        // Test that 'from module import name' is parsed
        Lexer lexer = new Lexer();
        lexer.tokenize("from math import add\n");
        Parser parser = new Parser();
        parser.parse(lexer);

        uint256 stmtIdx = parser.getAuxData(parser.getAuxIndex(0));
        assertEq(uint256(parser.getNodeType(stmtIdx)), 15, "should be IMPORT_STMT");
        assertEq(parser.getStrValue(stmtIdx), "math", "module name");
    }

    function testImportNoOpInCodegen() public {
        // import statement alone should compile and execute without error
        string memory src = "import math\nx = 42\nprint(x)\n";
        bytes memory bytecode = compiler.compile(src);
        VM vm = new VM();
        vm.execute(bytecode);
    }

    function testImportWithForLoop() public {
        string memory mod = "def factorial(n):\n    r = 1\n    for i in range(1, n + 1):\n        r *= i\n    return r\n";
        string memory main = "from math import factorial\nx = factorial(5)\nprint(x)\n";
        _runWithImport(main, "math", mod);
    }

    function testImportNoModules() public {
        // Empty module list should work like normal compile
        string[] memory names = new string[](0);
        string[] memory sources = new string[](0);
        bytes memory bytecode = compiler.compileWithImports("x = 42\nprint(x)\n", names, sources);
        VM vm = new VM();
        vm.execute(bytecode);
    }

    function testImportMultipleModules() public {
        string memory mod1 = "def add(a, b):\n    return a + b\n";
        string memory mod2 = "def mul(a, b):\n    return a * b\n";

        string[] memory names = new string[](2);
        names[0] = "math";
        names[1] = "calc";
        string[] memory sources = new string[](2);
        sources[0] = mod1;
        sources[1] = mod2;

        bytes memory bytecode = compiler.compileWithImports(
            "from math import add\nfrom calc import mul\nx = add(2, mul(3, 4))\nprint(x)\n",
            names,
            sources
        );
        VM vm = new VM();
        vm.execute(bytecode);
    }
}
