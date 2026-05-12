// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {VFS} from "../vfs/VFS.sol";

/// @title Venv — Virtual Environment for Python compilation
/// @notice Manages compilation contexts with their own settings, module paths, and VFS.
contract VFS_Venv is VFS {}

/// @title Venv — Compilation environment
/// @notice Each Venv holds a VFS, module search paths, and compilation settings.
contract Venv {
    // The VFS for this environment
    VFS private vfs;

    // Settings
    string private name;
    uint256 private optimizationLevel; // 0 = none, 1 = basic, 2 = aggressive
    bool private enableGC;
    string private targetBackend; // "bytecode", "solidity", "yul"

    // Module search paths
    string[] private modulePaths;

    // Events
    event VenvCreated(string name);
    event SettingChanged(string setting, string value);

    constructor(string memory _name) {
        name = _name;
        vfs = new VFS();
        optimizationLevel = 1;
        enableGC = true;
        targetBackend = "bytecode";
        emit VenvCreated(_name);
    }

    // ==================== VFS Access ====================

    function writeFile(string memory path, string memory content) public {
        vfs.writeFile(path, content);
    }

    function readFile(string memory path) public view returns (string memory) {
        return vfs.readFile(path);
    }

    function fileExists(string memory path) public view returns (bool) {
        return vfs.fileExists(path);
    }

    function getVFS() public view returns (VFS) {
        return vfs;
    }

    // ==================== Settings ====================

    function setOptimizationLevel(uint256 level) public {
        require(level <= 2, "invalid optimization level");
        optimizationLevel = level;
    }

    function getOptimizationLevel() public view returns (uint256) {
        return optimizationLevel;
    }

    function setEnableGC(bool enabled) public {
        enableGC = enabled;
    }

    function isGCEnabled() public view returns (bool) {
        return enableGC;
    }

    function setTargetBackend(string memory backend) public {
        targetBackend = backend;
    }

    function getTargetBackend() public view returns (string memory) {
        return targetBackend;
    }

    function getName() public view returns (string memory) {
        return name;
    }

    // ==================== Module Paths ====================

    function addModulePath(string memory path) public {
        modulePaths.push(path);
    }

    function getModulePaths() public view returns (string[] memory) {
        return modulePaths;
    }

    function getModulePathCount() public view returns (uint256) {
        return modulePaths.length;
    }

    /// @notice Resolve a module name to a file path by searching module paths.
    function resolveModule(string memory moduleName) public view returns (string memory, bool) {
        // Try direct path
        if (vfs.fileExists(moduleName)) {
            return (moduleName, true);
        }

        // Try with .py extension
        string memory pyPath = string(abi.encodePacked(moduleName, ".py"));
        if (vfs.fileExists(pyPath)) {
            return (pyPath, true);
        }

        // Search module paths
        for (uint256 i = 0; i < modulePaths.length; i++) {
            string memory fullPath = string(abi.encodePacked(modulePaths[i], "/", moduleName));
            if (vfs.fileExists(fullPath)) {
                return (fullPath, true);
            }
            string memory fullPathPy = string(abi.encodePacked(modulePaths[i], "/", moduleName, ".py"));
            if (vfs.fileExists(fullPathPy)) {
                return (fullPathPy, true);
            }
        }

        return ("", false);
    }
}
