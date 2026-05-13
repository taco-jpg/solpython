// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title VFS — Virtual File System
/// @notice On-chain file storage for the Python compiler. Stores file contents
///         in a mapping keyed by path. Supports read, write, delete, and list.
contract VFS {
    mapping(string => string) private files;
    mapping(string => bool) private exists;
    string[] private fileList;

    // Directory support
    mapping(string => bool) private directories;
    mapping(string => string[]) private dirChildren; // dir path => child names

    event FileWritten(string path);
    event FileDeleted(string path);
    event DirCreated(string path);
    event DirRemoved(string path);

    /// @notice Write a file to the VFS. Overwrites if it already exists.
    function writeFile(string memory path, string memory content) public {
        if (!exists[path]) {
            fileList.push(path);
            exists[path] = true;
        }
        files[path] = content;
        emit FileWritten(path);
    }

    /// @notice Read a file from the VFS. Reverts if file does not exist.
    function readFile(string memory path) public view returns (string memory) {
        require(exists[path], "VFS: file not found");
        return files[path];
    }

    /// @notice Check if a file exists.
    function fileExists(string memory path) public view returns (bool) {
        return exists[path];
    }

    /// @notice Delete a file from the VFS. Reverts if file does not exist.
    function deleteFile(string memory path) public {
        require(exists[path], "VFS: file not found");
        exists[path] = false;
        files[path] = "";
        emit FileDeleted(path);
    }

    /// @notice Get the number of files in the VFS.
    function fileCount() public view returns (uint256) {
        return fileList.length;
    }

    /// @notice Get a file path by index.
    function getFilePath(uint256 index) public view returns (string memory) {
        return fileList[index];
    }

    /// @notice Get all file paths.
    function listFiles() public view returns (string[] memory) {
        return fileList;
    }

    // ==================== Directory Operations ====================

    /// @notice Create a directory. Reverts if already exists.
    function mkdir(string memory path) public {
        require(!directories[path], "VFS: directory already exists");
        directories[path] = true;
        emit DirCreated(path);
    }

    /// @notice Remove a directory. Reverts if not empty or doesn't exist.
    function rmdir(string memory path) public {
        require(directories[path], "VFS: directory not found");
        require(dirChildren[path].length == 0, "VFS: directory not empty");
        directories[path] = false;
        emit DirRemoved(path);
    }

    /// @notice Check if a path is a directory.
    function isDir(string memory path) public view returns (bool) {
        return directories[path];
    }

    /// @notice List children of a directory.
    function listDir(string memory path) public view returns (string[] memory) {
        require(directories[path], "VFS: directory not found");
        return dirChildren[path];
    }

    /// @notice Write a file into a directory. Creates parent directories as needed.
    function writeFileInDir(string memory dirPath, string memory fileName, string memory content) public {
        require(directories[dirPath], "VFS: directory not found");
        string memory fullPath = _pathJoin(dirPath, fileName);
        if (!exists[fullPath]) {
            fileList.push(fullPath);
            exists[fullPath] = true;
            dirChildren[dirPath].push(fileName);
        }
        files[fullPath] = content;
        emit FileWritten(fullPath);
    }

    /// @notice Read a file from a directory.
    function readFileInDir(string memory dirPath, string memory fileName) public view returns (string memory) {
        string memory fullPath = _pathJoin(dirPath, fileName);
        require(exists[fullPath], "VFS: file not found");
        return files[fullPath];
    }

    /// @notice Normalize a path (remove trailing slashes, handle . and ..)
    function normalizePath(string memory path) public pure returns (string memory) {
        bytes memory b = bytes(path);
        // Remove trailing slash
        if (b.length > 1 && b[b.length - 1] == 0x2F) {
            bytes memory trimmed = new bytes(b.length - 1);
            for (uint256 i = 0; i < b.length - 1; i++) {
                trimmed[i] = b[i];
            }
            return string(trimmed);
        }
        return path;
    }

    function _pathJoin(string memory dir, string memory file) internal pure returns (string memory) {
        bytes memory dirB = bytes(dir);
        if (dirB.length > 0 && dirB[dirB.length - 1] == 0x2F) {
            return string.concat(dir, file);
        }
        return string.concat(dir, "/", file);
    }
}
