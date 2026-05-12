// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import {Venv} from "../src/venv/Venv.sol";
import {VFS} from "../src/vfs/VFS.sol";
import {PythonCompiler} from "../src/PythonCompiler.sol";
import {VM} from "../src/phases/VM.sol";

contract VenvTest is Test {
    // ==================== Basic Creation ====================

    function testCreateVenv() public {
        Venv env = new Venv("test");
        assertEq(env.getName(), "test");
    }

    function testDefaultSettings() public {
        Venv env = new Venv("default");
        assertEq(env.getOptimizationLevel(), 1, "default opt level");
        assertTrue(env.isGCEnabled(), "GC enabled by default");
        assertEq(env.getTargetBackend(), "bytecode", "default backend");
    }

    // ==================== Settings ====================

    function testSetOptimizationLevel() public {
        Venv env = new Venv("test");
        env.setOptimizationLevel(2);
        assertEq(env.getOptimizationLevel(), 2);
    }

    function testInvalidOptimizationLevel() public {
        Venv env = new Venv("test");
        vm.expectRevert("invalid optimization level");
        env.setOptimizationLevel(3);
    }

    function testSetGC() public {
        Venv env = new Venv("test");
        env.setEnableGC(false);
        assertFalse(env.isGCEnabled());
    }

    function testSetBackend() public {
        Venv env = new Venv("test");
        env.setTargetBackend("solidity");
        assertEq(env.getTargetBackend(), "solidity");
    }

    // ==================== VFS Integration ====================

    function testWriteAndRead() public {
        Venv env = new Venv("test");
        env.writeFile("hello.py", "x = 42\n");
        assertEq(env.readFile("hello.py"), "x = 42\n");
    }

    function testFileExists() public {
        Venv env = new Venv("test");
        assertFalse(env.fileExists("nope.py"));
        env.writeFile("nope.py", "pass\n");
        assertTrue(env.fileExists("nope.py"));
    }

    function testGetVFS() public {
        Venv env = new Venv("test");
        VFS vfs = env.getVFS();
        vfs.writeFile("via_vfs.py", "x = 1\n");
        assertEq(env.readFile("via_vfs.py"), "x = 1\n");
    }

    // ==================== Module Paths ====================

    function testAddModulePath() public {
        Venv env = new Venv("test");
        env.addModulePath("lib");
        env.addModulePath("vendor");
        assertEq(env.getModulePathCount(), 2);
    }

    function testGetModulePaths() public {
        Venv env = new Venv("test");
        env.addModulePath("lib");
        string[] memory paths = env.getModulePaths();
        assertEq(paths[0], "lib");
    }

    function testResolveModuleDirect() public {
        Venv env = new Venv("test");
        env.writeFile("math.py", "def add(a, b):\n    return a + b\n");
        (string memory path, bool found) = env.resolveModule("math.py");
        assertTrue(found);
        assertEq(path, "math.py");
    }

    function testResolveModuleWithPyExtension() public {
        Venv env = new Venv("test");
        env.writeFile("math.py", "def add(a, b):\n    return a + b\n");
        (string memory path, bool found) = env.resolveModule("math");
        assertTrue(found);
        assertEq(path, "math.py");
    }

    function testResolveModuleInPath() public {
        Venv env = new Venv("test");
        env.addModulePath("lib");
        env.writeFile("lib/utils.py", "def helper():\n    return 1\n");
        (string memory path, bool found) = env.resolveModule("utils");
        assertTrue(found);
        assertEq(path, "lib/utils.py");
    }

    function testResolveModuleNotFound() public {
        Venv env = new Venv("test");
        (string memory path, bool found) = env.resolveModule("missing");
        assertFalse(found);
        assertEq(path, "");
    }

    // ==================== Full Pipeline ====================

    function testVenvWithCompiler() public {
        Venv env = new Venv("test");
        env.writeFile("math.py", "def add(a, b):\n    return a + b\n");

        PythonCompiler compiler = new PythonCompiler();
        string memory mainSrc = "from math import add\nx = add(3, 4)\nprint(x)\n";

        // Resolve the module
        (string memory modPath, bool found) = env.resolveModule("math");
        assertTrue(found);

        // Compile with imports
        string[] memory names = new string[](1);
        names[0] = "math";
        string[] memory sources = new string[](1);
        sources[0] = env.readFile(modPath);

        bytes memory bytecode = compiler.compileWithImports(mainSrc, names, sources);
        VM vm = new VM();
        vm.execute(bytecode);
    }

    function testVenvMultipleModules() public {
        Venv env = new Venv("test");
        env.addModulePath("lib");
        env.writeFile("lib/math.py", "def add(a, b):\n    return a + b\n");
        env.writeFile("lib/calc.py", "def mul(a, b):\n    return a * b\n");

        PythonCompiler compiler = new PythonCompiler();

        // Resolve modules
        (string memory mathPath, bool mFound) = env.resolveModule("math");
        (string memory calcPath, bool cFound) = env.resolveModule("calc");
        assertTrue(mFound);
        assertTrue(cFound);

        string[] memory names = new string[](2);
        names[0] = "math";
        names[1] = "calc";
        string[] memory sources = new string[](2);
        sources[0] = env.readFile(mathPath);
        sources[1] = env.readFile(calcPath);

        bytes memory bytecode = compiler.compileWithImports(
            "from math import add\nfrom calc import mul\nx = add(2, mul(3, 4))\nprint(x)\n",
            names,
            sources
        );
        VM vm = new VM();
        vm.execute(bytecode);
    }
}
