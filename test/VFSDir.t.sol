// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import {VFS} from "../src/vfs/VFS.sol";

contract VFSDirTest is Test {
    function testMkdir() public {
        VFS vfs = new VFS();
        vfs.mkdir("/home");
        assertTrue(vfs.isDir("/home"), "should be a directory");
    }

    function testMkdirRevert() public {
        VFS vfs = new VFS();
        vfs.mkdir("/home");
        vm.expectRevert("VFS: directory already exists");
        vfs.mkdir("/home");
    }

    function testRmdir() public {
        VFS vfs = new VFS();
        vfs.mkdir("/tmp");
        vfs.rmdir("/tmp");
        assertFalse(vfs.isDir("/tmp"), "should not be a directory");
    }

    function testRmdirNotEmpty() public {
        VFS vfs = new VFS();
        vfs.mkdir("/home");
        vfs.writeFileInDir("/home", "test.py", "x = 1");
        vm.expectRevert("VFS: directory not empty");
        vfs.rmdir("/home");
    }

    function testWriteFileInDir() public {
        VFS vfs = new VFS();
        vfs.mkdir("/src");
        vfs.writeFileInDir("/src", "main.py", "print(42)");
        assertEq(vfs.readFileInDir("/src", "main.py"), "print(42)", "file content");
    }

    function testListDir() public {
        VFS vfs = new VFS();
        vfs.mkdir("/project");
        vfs.writeFileInDir("/project", "a.py", "x = 1");
        vfs.writeFileInDir("/project", "b.py", "y = 2");
        string[] memory children = vfs.listDir("/project");
        assertEq(children.length, 2, "2 children");
    }

    function testNestedDirs() public {
        VFS vfs = new VFS();
        vfs.mkdir("/project");
        vfs.mkdir("/project/src");
        vfs.writeFileInDir("/project/src", "main.py", "print(1)");
        assertTrue(vfs.isDir("/project"), "parent is dir");
        assertTrue(vfs.isDir("/project/src"), "child is dir");
        assertEq(vfs.readFileInDir("/project/src", "main.py"), "print(1)", "nested file");
    }

    function testNormalizePath() public {
        VFS vfs = new VFS();
        assertEq(vfs.normalizePath("/home/"), "/home", "remove trailing slash");
        assertEq(vfs.normalizePath("/home"), "/home", "no trailing slash");
    }
}
