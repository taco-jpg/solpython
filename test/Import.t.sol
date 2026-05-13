// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import {Lexer} from "../src/phases/Lexer.sol";
import {Parser} from "../src/phases/Parser.sol";
import {CodeGenerator} from "../src/phases/CodeGenerator.sol";
import {VM} from "../src/phases/VM.sol";
import {PythonCompiler} from "../src/PythonCompiler.sol";

contract ImportTest is Test {
    event Print(uint256[] values);

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

    // ==================== Basic Import ====================

    function testImportSimpleFunction() public {
        string memory mod = "def add(a, b):\n    return a + b\n";
        string memory main = "from math import add\nx = add(1, 2)\nprint(x)\n";
        vm.recordLogs();
        _runWithImport(main, "math", mod);
        assertEq(_getLastPrint(), 3, "add(1,2) = 3");
    }

    function testImportMultipleFunctions() public {
        string memory mod = "def add(a, b):\n    return a + b\ndef mul(a, b):\n    return a * b\n";
        string memory main = "from math import add\nfrom math import mul\nx = add(2, mul(3, 4))\nprint(x)\n";
        vm.recordLogs();
        _runWithImport(main, "math", mod);
        assertEq(_getLastPrint(), 14, "add(2, mul(3,4)) = 14");
    }

    function testImportFunctionCallsFunction() public {
        string memory mod = "def double(x):\n    return x * 2\n\ndef quadruple(x):\n    return double(double(x))\n";
        string memory main = "from utils import quadruple\nx = quadruple(5)\nprint(x)\n";
        vm.recordLogs();
        _runWithImport(main, "utils", mod);
        assertEq(_getLastPrint(), 20, "quadruple(5) = 20");
    }

    function testImportWithMainCode() public {
        string memory mod = "def square(x):\n    return x * x\n";
        string memory main = "from math import square\ns = 0\nfor i in range(5):\n    s += square(i)\nprint(s)\n";
        vm.recordLogs();
        _runWithImport(main, "math", mod);
        assertEq(_getLastPrint(), 30, "sum of squares 0..4 = 30");
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
        string memory src = "import math\nx = 42\nprint(x)\n";
        bytes memory bytecode = compiler.compile(src);
        VM pyVm = new VM();
        vm.recordLogs();
        pyVm.execute(bytecode);
        assertEq(_getLastPrint(), 42, "import no-op, x=42");
    }

    function testImportWithForLoop() public {
        string memory mod = "def factorial(n):\n    r = 1\n    for i in range(1, n + 1):\n        r *= i\n    return r\n";
        string memory main = "from math import factorial\nx = factorial(5)\nprint(x)\n";
        vm.recordLogs();
        _runWithImport(main, "math", mod);
        assertEq(_getLastPrint(), 120, "factorial(5) = 120");
    }

    function testImportNoModules() public {
        string[] memory names = new string[](0);
        string[] memory sources = new string[](0);
        bytes memory bytecode = compiler.compileWithImports("x = 42\nprint(x)\n", names, sources);
        VM pyVm = new VM();
        vm.recordLogs();
        pyVm.execute(bytecode);
        assertEq(_getLastPrint(), 42, "no modules, x=42");
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
        VM pyVm = new VM();
        vm.recordLogs();
        pyVm.execute(bytecode);
        assertEq(_getLastPrint(), 14, "add(2, mul(3,4)) = 14");
    }
}
