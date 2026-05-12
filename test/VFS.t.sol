// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import {VFS} from "../src/vfs/VFS.sol";
import {PythonCompiler} from "../src/PythonCompiler.sol";
import {VM} from "../src/phases/VM.sol";

contract VFSTest is Test {
    VFS private vfs;
    PythonCompiler private compiler;

    function setUp() public {
        vfs = new VFS();
        compiler = new PythonCompiler();
    }

    // ==================== Basic CRUD ====================

    function testWriteAndRead() public {
        vfs.writeFile("hello.py", "x = 42\n");
        assertEq(vfs.readFile("hello.py"), "x = 42\n");
    }

    function testFileExists() public {
        assertFalse(vfs.fileExists("nope.py"));
        vfs.writeFile("nope.py", "pass\n");
        assertTrue(vfs.fileExists("nope.py"));
    }

    function testOverwrite() public {
        vfs.writeFile("f.py", "x = 1\n");
        vfs.writeFile("f.py", "x = 2\n");
        assertEq(vfs.readFile("f.py"), "x = 2\n");
    }

    function testDelete() public {
        vfs.writeFile("f.py", "x = 1\n");
        vfs.deleteFile("f.py");
        assertFalse(vfs.fileExists("f.py"));
    }

    function testDeleteRevertsIfNotFound() public {
        vm.expectRevert("VFS: file not found");
        vfs.deleteFile("missing.py");
    }

    function testReadRevertsIfNotFound() public {
        vm.expectRevert("VFS: file not found");
        vfs.readFile("missing.py");
    }

    // ==================== File Listing ====================

    function testFileCount() public {
        assertEq(vfs.fileCount(), 0);
        vfs.writeFile("a.py", "x = 1\n");
        assertEq(vfs.fileCount(), 1);
        vfs.writeFile("b.py", "x = 2\n");
        assertEq(vfs.fileCount(), 2);
    }

    function testGetFilePath() public {
        vfs.writeFile("a.py", "x = 1\n");
        vfs.writeFile("b.py", "x = 2\n");
        assertEq(vfs.getFilePath(0), "a.py");
        assertEq(vfs.getFilePath(1), "b.py");
    }

    function testListFiles() public {
        vfs.writeFile("a.py", "x = 1\n");
        vfs.writeFile("b.py", "x = 2\n");
        string[] memory files = vfs.listFiles();
        assertEq(files.length, 2);
        assertEq(files[0], "a.py");
        assertEq(files[1], "b.py");
    }

    function testDeleteDoesNotRemoveFromList() public {
        vfs.writeFile("a.py", "x = 1\n");
        vfs.deleteFile("a.py");
        // File is still in the list (just marked as non-existent)
        assertEq(vfs.fileCount(), 1);
        assertFalse(vfs.fileExists("a.py"));
    }

    // ==================== Events ====================

    function testFileWrittenEvent() public {
        vm.expectEmit(true, false, false, false);
        emit VFS.FileWritten("test.py");
        vfs.writeFile("test.py", "x = 1\n");
    }

    function testFileDeletedEvent() public {
        vfs.writeFile("test.py", "x = 1\n");
        vm.expectEmit(true, false, false, false);
        emit VFS.FileDeleted("test.py");
        vfs.deleteFile("test.py");
    }

    // ==================== VFS + Compiler Integration ====================

    function testCompileWithVFS() public {
        vfs.writeFile("math.py", "def add(a, b):\n    return a + b\n");

        string memory mainSrc = "from math import add\nx = add(3, 4)\nprint(x)\n";
        bytes memory bytecode = compiler.compileWithVFS(mainSrc, vfs);

        VM vmInst = new VM();
        vmInst.execute(bytecode);
    }

    function testCompileWithVFSMultipleModules() public {
        vfs.writeFile("math.py", "def add(a, b):\n    return a + b\n");
        vfs.writeFile("calc.py", "def mul(a, b):\n    return a * b\n");

        string memory mainSrc = "from math import add\nfrom calc import mul\nx = add(2, mul(3, 4))\nprint(x)\n";
        bytes memory bytecode = compiler.compileWithVFS(mainSrc, vfs);

        VM vmInst = new VM();
        vmInst.execute(bytecode);
    }

    function testCompileWithVFSNoImports() public {
        string memory mainSrc = "x = 42\nprint(x)\n";
        bytes memory bytecode = compiler.compileWithVFS(mainSrc, vfs);

        VM vmInst = new VM();
        vmInst.execute(bytecode);
    }

    function testCompileWithVFSMissingModule() public {
        // Module not in VFS — import is skipped, function call will error
        string memory mainSrc = "from missing import foo\nx = foo()\n";
        // This should still compile (import is no-op), but function call may fail at runtime
        bytes memory bytecode = compiler.compileWithVFS(mainSrc, vfs);
        // Just verify it compiles — runtime behavior depends on the VM
        assertTrue(bytecode.length > 0, "should produce bytecode");
    }
}
