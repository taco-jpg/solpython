// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title VFS — Virtual File System
/// @notice On-chain file storage for the Python compiler. Stores file contents
///         in a mapping keyed by path. Supports read, write, delete, and list.
contract VFS {
    mapping(string => string) private files;
    mapping(string => bool) private exists;
    string[] private fileList;

    event FileWritten(string path);
    event FileDeleted(string path);

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
}
