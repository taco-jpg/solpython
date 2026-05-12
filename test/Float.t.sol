// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import {Lexer} from "../src/phases/Lexer.sol";
import {Parser} from "../src/phases/Parser.sol";
import {SemanticAnalyzer} from "../src/phases/SemanticAnalyzer.sol";
import {CodeGenerator} from "../src/phases/CodeGenerator.sol";
import {VM} from "../src/phases/VM.sol";
import {Token, TokenType} from "../src/types/Token.sol";

contract FloatTest is Test {
    event Print(uint256[] values);
    event PrintString(string value);
    event VMError(string message, uint256 pc);

    function _compile(string memory src) internal returns (bytes memory) {
        Lexer lexer = new Lexer();
        lexer.tokenize(src);
        Parser parser = new Parser();
        parser.parse(lexer);
        SemanticAnalyzer analyzer = new SemanticAnalyzer();
        analyzer.analyze(parser);
        CodeGenerator gen = new CodeGenerator();
        return gen.generate(parser);
    }

    function _run(string memory src) internal returns (VM) {
        bytes memory bytecode = _compile(src);
        VM pyVm = new VM();
        pyVm.execute(bytecode);
        return pyVm;
    }

    // ==================== Lexer Tests ====================

    function testLexerFloat314() public {
        Lexer lexer = new Lexer();
        Token[] memory tokens = lexer.tokenize("3.14");
        assertEq(uint256(tokens[0].tokenType), uint256(TokenType.FLOAT));
        assertEq(tokens[0].intValue, 3_140_000);
    }

    function testLexerFloat15() public {
        Lexer lexer = new Lexer();
        Token[] memory tokens = lexer.tokenize("1.5");
        assertEq(uint256(tokens[0].tokenType), uint256(TokenType.FLOAT));
        assertEq(tokens[0].intValue, 1_500_000);
    }

    function testLexerFloat0001() public {
        Lexer lexer = new Lexer();
        Token[] memory tokens = lexer.tokenize("0.001");
        assertEq(uint256(tokens[0].tokenType), uint256(TokenType.FLOAT));
        assertEq(tokens[0].intValue, 1_000);
    }

    function testLexerFloat100() public {
        Lexer lexer = new Lexer();
        Token[] memory tokens = lexer.tokenize("10.0");
        assertEq(uint256(tokens[0].tokenType), uint256(TokenType.FLOAT));
        assertEq(tokens[0].intValue, 10_000_000);
    }

    // ==================== Float Arithmetic Tests ====================

    function testFloatAdd() public {
        // 1.5 + 1.5 == 3.0
        bytes memory bytecode = _compile("print((1.5 + 1.5) == 3.0)\n");
        VM pyVm = new VM();

        vm.recordLogs();
        pyVm.execute(bytecode);

        Vm.Log[] memory logs = vm.getRecordedLogs();
        bool foundPrint = false;
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == keccak256("Print(uint256[])")) {
                uint256[] memory vals = abi.decode(logs[i].data, (uint256[]));
                assertEq(vals[0], 1, "1.5 + 1.5 should equal 3.0");
                foundPrint = true;
            }
        }
        assertTrue(foundPrint, "No Print event");
    }

    function testFloatSub() public {
        // 3.14 - 1.14 == 2.0
        bytes memory bytecode = _compile("print((3.14 - 1.14) == 2.0)\n");
        VM pyVm = new VM();

        vm.recordLogs();
        pyVm.execute(bytecode);

        Vm.Log[] memory logs = vm.getRecordedLogs();
        bool foundPrint = false;
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == keccak256("Print(uint256[])")) {
                uint256[] memory vals = abi.decode(logs[i].data, (uint256[]));
                assertEq(vals[0], 1, "3.14 - 1.14 should equal 2.0");
                foundPrint = true;
            }
        }
        assertTrue(foundPrint, "No Print event");
    }

    function testFloatMul() public {
        // 2.0 * 3.0 == 6.0
        bytes memory bytecode = _compile("print((2.0 * 3.0) == 6.0)\n");
        VM pyVm = new VM();

        vm.recordLogs();
        pyVm.execute(bytecode);

        Vm.Log[] memory logs = vm.getRecordedLogs();
        bool foundPrint = false;
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == keccak256("Print(uint256[])")) {
                uint256[] memory vals = abi.decode(logs[i].data, (uint256[]));
                assertEq(vals[0], 1, "2.0 * 3.0 should equal 6.0");
                foundPrint = true;
            }
        }
        assertTrue(foundPrint, "No Print event");
    }

    function testFloatDiv() public {
        // 7.0 / 2.0 == 3.5
        bytes memory bytecode = _compile("print((7.0 / 2.0) == 3.5)\n");
        VM pyVm = new VM();

        vm.recordLogs();
        pyVm.execute(bytecode);

        Vm.Log[] memory logs = vm.getRecordedLogs();
        bool foundPrint = false;
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == keccak256("Print(uint256[])")) {
                uint256[] memory vals = abi.decode(logs[i].data, (uint256[]));
                assertEq(vals[0], 1, "7.0 / 2.0 should equal 3.5");
                foundPrint = true;
            }
        }
        assertTrue(foundPrint, "No Print event");
    }

    function testFloatIntPromotion() public {
        // 1.5 + 1 == 2.5
        bytes memory bytecode = _compile("print((1.5 + 1) == 2.5)\n");
        VM pyVm = new VM();

        vm.recordLogs();
        pyVm.execute(bytecode);

        Vm.Log[] memory logs = vm.getRecordedLogs();
        bool foundPrint = false;
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == keccak256("Print(uint256[])")) {
                uint256[] memory vals = abi.decode(logs[i].data, (uint256[]));
                assertEq(vals[0], 1, "1.5 + 1 should equal 2.5");
                foundPrint = true;
            }
        }
        assertTrue(foundPrint, "No Print event");
    }

    // ==================== Float Comparison Tests ====================

    function testFloatLessThan() public {
        // 1.5 < 2.0 == True
        bytes memory bytecode = _compile("print(1.5 < 2.0)\n");
        VM pyVm = new VM();

        vm.recordLogs();
        pyVm.execute(bytecode);

        Vm.Log[] memory logs = vm.getRecordedLogs();
        bool foundPrint = false;
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == keccak256("Print(uint256[])")) {
                uint256[] memory vals = abi.decode(logs[i].data, (uint256[]));
                assertEq(vals[0], 1, "1.5 < 2.0 should be True");
                foundPrint = true;
            }
        }
        assertTrue(foundPrint, "No Print event");
    }

    function testFloatEquality() public {
        // 3.0 == 3.0 == True
        bytes memory bytecode = _compile("print(3.0 == 3.0)\n");
        VM pyVm = new VM();

        vm.recordLogs();
        pyVm.execute(bytecode);

        Vm.Log[] memory logs = vm.getRecordedLogs();
        bool foundPrint = false;
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == keccak256("Print(uint256[])")) {
                uint256[] memory vals = abi.decode(logs[i].data, (uint256[]));
                assertEq(vals[0], 1, "3.0 == 3.0 should be True");
                foundPrint = true;
            }
        }
        assertTrue(foundPrint, "No Print event");
    }

    function testFloatGreaterThan() public {
        // 1.5 > 2.0 == False
        bytes memory bytecode = _compile("print(1.5 > 2.0)\n");
        VM pyVm = new VM();

        vm.recordLogs();
        pyVm.execute(bytecode);

        Vm.Log[] memory logs = vm.getRecordedLogs();
        bool foundPrint = false;
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == keccak256("Print(uint256[])")) {
                uint256[] memory vals = abi.decode(logs[i].data, (uint256[]));
                assertEq(vals[0], 0, "1.5 > 2.0 should be False");
                foundPrint = true;
            }
        }
        assertTrue(foundPrint, "No Print event");
    }

    // ==================== Float Variable and Function Tests ====================

    function testFloatVariable() public {
        // x = 3.14; print(x == 3.14)
        bytes memory bytecode = _compile("x = 3.14\nprint(x == 3.14)\n");
        VM pyVm = new VM();

        vm.recordLogs();
        pyVm.execute(bytecode);

        Vm.Log[] memory logs = vm.getRecordedLogs();
        bool foundPrint = false;
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == keccak256("Print(uint256[])")) {
                uint256[] memory vals = abi.decode(logs[i].data, (uint256[]));
                assertEq(vals[0], 1, "x should equal 3.14");
                foundPrint = true;
            }
        }
        assertTrue(foundPrint, "No Print event");
    }

    function testFloatInFunction() public {
        // def f(x): return x * 2.0; print(f(1.5) == 3.0)
        string memory src = "def f(x):\n    return x * 2.0\nprint(f(1.5) == 3.0)\n";
        bytes memory bytecode = _compile(src);
        VM pyVm = new VM();

        vm.recordLogs();
        pyVm.execute(bytecode);

        Vm.Log[] memory logs = vm.getRecordedLogs();
        bool foundPrint = false;
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == keccak256("Print(uint256[])")) {
                uint256[] memory vals = abi.decode(logs[i].data, (uint256[]));
                assertEq(vals[0], 1, "f(1.5) should equal 3.0");
                foundPrint = true;
            }
        }
        assertTrue(foundPrint, "No Print event");
    }

    // ==================== str() with Float ====================

    function testStrFloat() public {
        // str(3.14) should produce "3.14"
        bytes memory bytecode = _compile("print(str(3.14))\n");
        VM pyVm = new VM();

        vm.recordLogs();
        pyVm.execute(bytecode);

        Vm.Log[] memory logs = vm.getRecordedLogs();
        bytes32 printStrTopic = keccak256("PrintString(string)");
        bool found = false;
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == printStrTopic) {
                string memory val = abi.decode(logs[i].data, (string));
                assertEq(keccak256(bytes(val)), keccak256("3.14"), "str(3.14) should be '3.14'");
                found = true;
            }
        }
        assertTrue(found, "No PrintString event");
    }

    // ==================== Float Print Direct ====================

    function testPrintFloat() public {
        // print(3.14) should output "3.14" as PrintString
        bytes memory bytecode = _compile("print(3.14)\n");
        VM pyVm = new VM();

        vm.recordLogs();
        pyVm.execute(bytecode);

        Vm.Log[] memory logs = vm.getRecordedLogs();
        bytes32 printStrTopic = keccak256("PrintString(string)");
        bool found = false;
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == printStrTopic) {
                string memory val = abi.decode(logs[i].data, (string));
                assertEq(keccak256(bytes(val)), keccak256("3.14"), "print(3.14) should output '3.14'");
                found = true;
            }
        }
        assertTrue(found, "No PrintString event for float print");
    }

    function testPrintFloatTrailingZero() public {
        // print(1.5) should output "1.5"
        bytes memory bytecode = _compile("print(1.5)\n");
        VM pyVm = new VM();

        vm.recordLogs();
        pyVm.execute(bytecode);

        Vm.Log[] memory logs = vm.getRecordedLogs();
        bytes32 printStrTopic = keccak256("PrintString(string)");
        bool found = false;
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == printStrTopic) {
                string memory val = abi.decode(logs[i].data, (string));
                assertEq(keccak256(bytes(val)), keccak256("1.5"), "print(1.5) should output '1.5'");
                found = true;
            }
        }
        assertTrue(found, "No PrintString event");
    }

    function testFloatArithmeticNoError() public {
        // Verify complex float expression compiles and runs without error
        string memory src = "a = 1.5\nb = 2.5\nc = a + b\nd = c * 2.0\ne = d / 4.0\nprint(e == 2.0)\n";
        bytes memory bytecode = _compile(src);
        VM pyVm = new VM();

        vm.recordLogs();
        pyVm.execute(bytecode);

        Vm.Log[] memory logs = vm.getRecordedLogs();
        bool foundPrint = false;
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == keccak256("Print(uint256[])")) {
                uint256[] memory vals = abi.decode(logs[i].data, (uint256[]));
                assertEq(vals[0], 1, "complex float arithmetic should be correct");
                foundPrint = true;
            }
        }
        assertTrue(foundPrint, "No Print event");
    }
}
