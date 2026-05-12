// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/PythonCompiler.sol";
import "../src/phases/VM.sol";

contract StringMethodsTest is Test {
    PythonCompiler compiler;
    VM pyVm;

    function setUp() public {
        compiler = new PythonCompiler();
        pyVm = new VM();
    }

    function _compileAndRun(string memory src) internal returns (uint256[] memory) {
        bytes memory bytecode = compiler.compile(src);
        vm.recordLogs();
        pyVm.execute(bytecode);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        uint256 printCount = 0;
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == keccak256("Print(uint256[])")) {
                printCount++;
            }
        }

        uint256[] memory results = new uint256[](printCount);
        uint256 idx = 0;
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == keccak256("Print(uint256[])")) {
                uint256[] memory vals = abi.decode(logs[i].data, (uint256[]));
                if (vals.length == 1) {
                    results[idx++] = vals[0];
                }
            }
        }
        return results;
    }

    function _compileAndRunString(string memory src) internal returns (string[] memory) {
        bytes memory bytecode = compiler.compile(src);
        vm.recordLogs();
        pyVm.execute(bytecode);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        uint256 printCount = 0;
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == keccak256("PrintString(string)")) {
                printCount++;
            }
        }

        string[] memory results = new string[](printCount);
        uint256 idx = 0;
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == keccak256("PrintString(string)")) {
                results[idx++] = abi.decode(logs[i].data, (string));
            }
        }
        return results;
    }

    // ==================== String Length Tests ====================

    function testStrLen() public {
        string memory src = 's = "hello"\nprint(len(s))\n';
        uint256[] memory results = _compileAndRun(src);
        assertEq(results.length, 1);
        assertEq(results[0], 5);
    }

    function testStrLenEmpty() public {
        string memory src = 's = ""\nprint(len(s))\n';
        uint256[] memory results = _compileAndRun(src);
        assertEq(results.length, 1);
        assertEq(results[0], 0);
    }

    // ==================== String Upper/Lower Tests ====================

    function testStrUpper() public {
        string memory src = 's = "hello"\nresult = s.upper()\nprint(result)\n';
        string[] memory results = _compileAndRunString(src);
        assertEq(results.length, 1);
        assertEq(keccak256(bytes(results[0])), keccak256("HELLO"));
    }

    function testStrLower() public {
        string memory src = 's = "WORLD"\nresult = s.lower()\nprint(result)\n';
        string[] memory results = _compileAndRunString(src);
        assertEq(results.length, 1);
        assertEq(keccak256(bytes(results[0])), keccak256("world"));
    }

    function testStrUpperLowerMixed() public {
        string memory src = 's = "Hello World"\nprint(s.upper())\nprint(s.lower())\n';
        string[] memory results = _compileAndRunString(src);
        assertEq(results.length, 2);
        assertEq(keccak256(bytes(results[0])), keccak256("HELLO WORLD"));
        assertEq(keccak256(bytes(results[1])), keccak256("hello world"));
    }

    // ==================== String Contains Tests ====================

    function testStrContains() public {
        string memory src = 's = "hello world"\nprint(s.contains("world"))\n';
        uint256[] memory results = _compileAndRun(src);
        assertEq(results.length, 1);
        assertEq(results[0], 1); // True
    }

    function testStrContainsFalse() public {
        string memory src = 's = "hello world"\nprint(s.contains("xyz"))\n';
        uint256[] memory results = _compileAndRun(src);
        assertEq(results.length, 1);
        assertEq(results[0], 0); // False
    }

    // ==================== String Split Tests ====================

    function testStrSplit() public {
        string memory src = 's = "a,b,c"\nparts = s.split(",")\nprint(len(parts))\n';
        uint256[] memory results = _compileAndRun(src);
        assertEq(results.length, 1);
        assertEq(results[0], 3);
    }

    // ==================== Int/Str Conversion Tests ====================

    function testIntToStr() public {
        string memory src = 'n = 42\ns = str(n)\nprint(s)\n';
        string[] memory results = _compileAndRunString(src);
        assertEq(results.length, 1);
        assertEq(keccak256(bytes(results[0])), keccak256("42"));
    }

    function testStrToInt() public {
        string memory src = 's = "123"\nn = int(s)\nprint(n)\n';
        uint256[] memory results = _compileAndRun(src);
        assertEq(results.length, 1);
        assertEq(results[0], 123);
    }

    function testIntToStrNegative() public {
        string memory src = 'n = -5\ns = str(n)\nprint(s)\n';
        string[] memory results = _compileAndRunString(src);
        assertEq(results.length, 1);
        assertEq(keccak256(bytes(results[0])), keccak256("-5"));
    }

    // ==================== String Slice Tests ====================

    function testStrSlice() public {
        string memory src = 's = "hello world"\nprint(s[0:5])\n';
        string[] memory results = _compileAndRunString(src);
        assertEq(results.length, 1);
        assertEq(keccak256(bytes(results[0])), keccak256("hello"));
    }

    function testStrSliceFromIndex() public {
        string memory src = 's = "hello world"\nprint(s[6:])\n';
        string[] memory results = _compileAndRunString(src);
        assertEq(results.length, 1);
        assertEq(keccak256(bytes(results[0])), keccak256("world"));
    }

    function testStrSliceToEnd() public {
        string memory src = 's = "hello world"\nprint(s[:5])\n';
        string[] memory results = _compileAndRunString(src);
        assertEq(results.length, 1);
        assertEq(keccak256(bytes(results[0])), keccak256("hello"));
    }

    // ==================== String Concatenation Tests ====================

    function testStrConcat() public {
        string memory src = 'a = "hello"\nb = " world"\nprint(a + b)\n';
        string[] memory results = _compileAndRunString(src);
        assertEq(results.length, 1);
        assertEq(keccak256(bytes(results[0])), keccak256("hello world"));
    }

    // ==================== String Equality Tests ====================

    function testStrEquality() public {
        string memory src = 'a = "hello"\nb = "hello"\nprint(a == b)\n';
        uint256[] memory results = _compileAndRun(src);
        assertEq(results.length, 1);
        assertEq(results[0], 1); // True
    }

    function testStrInequality() public {
        string memory src = 'a = "hello"\nb = "world"\nprint(a == b)\n';
        uint256[] memory results = _compileAndRun(src);
        assertEq(results.length, 1);
        assertEq(results[0], 0); // False
    }

    // ==================== Combined String Operations Tests ====================

    function testStrCombinedOps() public {
        string memory src = 's = "Hello World"\nresult = s.lower()\nprint(result.contains("hello"))\n';
        uint256[] memory results = _compileAndRun(src);
        assertEq(results.length, 1);
        assertEq(results[0], 1); // True
    }

    function testStrLenAfterTransform() public {
        string memory src = 's = "hello"\nresult = s.upper()\nprint(len(result))\n';
        uint256[] memory results = _compileAndRun(src);
        assertEq(results.length, 1);
        assertEq(results[0], 5);
    }
}
