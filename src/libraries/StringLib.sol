// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

library StringLib {
    function toBytes(string memory s) internal pure returns (bytes memory) {
        return bytes(s);
    }

    function fromBytes(bytes memory b) internal pure returns (string memory) {
        return string(b);
    }

    function slice(bytes memory b, uint256 start, uint256 end) internal pure returns (bytes memory) {
        require(end >= start, "StringLib: invalid slice");
        bytes memory result = new bytes(end - start);
        for (uint256 i = start; i < end; i++) {
            result[i - start] = b[i];
        }
        return result;
    }

    function charAt(bytes memory b, uint256 index) internal pure returns (bytes1) {
        require(index < b.length, "StringLib: index out of bounds");
        return b[index];
    }

    function isDigit(bytes1 c) internal pure returns (bool) {
        return c >= 0x30 && c <= 0x39; // '0' to '9'
    }

    function isAlpha(bytes1 c) internal pure returns (bool) {
        return (c >= 0x41 && c <= 0x5A) || // 'A' to 'Z'
               (c >= 0x61 && c <= 0x7A) || // 'a' to 'z'
               c == 0x5F;                   // '_'
    }

    function isAlphaNumeric(bytes1 c) internal pure returns (bool) {
        return isAlpha(c) || isDigit(c);
    }

    function isWhitespace(bytes1 c) internal pure returns (bool) {
        return c == 0x20 || c == 0x09; // space or tab
    }

    function isNewline(bytes1 c) internal pure returns (bool) {
        return c == 0x0A || c == 0x0D; // \n or \r
    }

    function bytesToUint(bytes memory b) internal pure returns (uint256) {
        uint256 result;
        for (uint256 i = 0; i < b.length; i++) {
            if (b[i] == 0x2E) break; // stop at decimal point
            result = result * 10 + (uint8(b[i]) - 48);
        }
        return result;
    }

    function uintToBytes(uint256 value) internal pure returns (bytes memory) {
        if (value == 0) return "0";
        uint256 temp = value;
        uint256 digits;
        while (temp != 0) {
            digits++;
            temp /= 10;
        }
        bytes memory result = new bytes(digits);
        while (value != 0) {
            digits--;
            result[digits] = bytes1(uint8(48 + value % 10));
            value /= 10;
        }
        return result;
    }

    function concat(string memory a, string memory b) internal pure returns (string memory) {
        return string(abi.encodePacked(a, b));
    }

    function equals(string memory a, string memory b) internal pure returns (bool) {
        return keccak256(bytes(a)) == keccak256(bytes(b));
    }

    function formatError(string memory prefix, uint256 line, uint256 col, string memory message) internal pure returns (string memory) {
        return string(abi.encodePacked(prefix, " Line ", uintToBytes(line), ", Col ", uintToBytes(col), ": ", message));
    }
}
