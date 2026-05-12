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

    function upper(bytes memory b) internal pure returns (bytes memory) {
        bytes memory result = new bytes(b.length);
        for (uint256 i = 0; i < b.length; i++) {
            bytes1 c = b[i];
            if (c >= 0x61 && c <= 0x7A) { // a-z
                result[i] = bytes1(uint8(c) - 32);
            } else {
                result[i] = c;
            }
        }
        return result;
    }

    function lower(bytes memory b) internal pure returns (bytes memory) {
        bytes memory result = new bytes(b.length);
        for (uint256 i = 0; i < b.length; i++) {
            bytes1 c = b[i];
            if (c >= 0x41 && c <= 0x5A) { // A-Z
                result[i] = bytes1(uint8(c) + 32);
            } else {
                result[i] = c;
            }
        }
        return result;
    }

    function sliceStr(bytes memory b, uint256 start, uint256 end) internal pure returns (bytes memory) {
        if (start >= b.length) return new bytes(0);
        if (end > b.length) end = b.length;
        if (start >= end) return new bytes(0);
        bytes memory result = new bytes(end - start);
        for (uint256 i = start; i < end; i++) {
            result[i - start] = b[i];
        }
        return result;
    }

    function contains(bytes memory haystack, bytes memory needle) internal pure returns (bool) {
        if (needle.length == 0) return true;
        if (needle.length > haystack.length) return false;
        for (uint256 i = 0; i <= haystack.length - needle.length; i++) {
            bool found = true;
            for (uint256 j = 0; j < needle.length; j++) {
                if (haystack[i + j] != needle[j]) {
                    found = false;
                    break;
                }
            }
            if (found) return true;
        }
        return false;
    }

    function split(bytes memory b, bytes memory delim) internal pure returns (bytes[] memory) {
        if (delim.length == 0) {
            bytes[] memory result = new bytes[](1);
            result[0] = b;
            return result;
        }
        // Count parts
        uint256 count = 1;
        for (uint256 i = 0; i <= b.length - delim.length; i++) {
            bool isMatch = true;
            for (uint256 j = 0; j < delim.length; j++) {
                if (b[i + j] != delim[j]) { isMatch = false; break; }
            }
            if (isMatch) { count++; i += delim.length - 1; }
        }
        bytes[] memory result = new bytes[](count);
        uint256 partIdx = 0;
        uint256 start = 0;
        for (uint256 i = 0; i <= b.length - delim.length; i++) {
            bool isMatch = true;
            for (uint256 j = 0; j < delim.length; j++) {
                if (b[i + j] != delim[j]) { isMatch = false; break; }
            }
            if (isMatch) {
                result[partIdx] = slice(b, start, i);
                partIdx++;
                start = i + delim.length;
                i += delim.length - 1;
            }
        }
        result[partIdx] = slice(b, start, b.length);
        return result;
    }

    function intToBytes(int256 value) internal pure returns (bytes memory) {
        if (value == 0) return "0";
        bool neg = value < 0;
        uint256 absVal = neg ? uint256(-value) : uint256(value);
        bytes memory digits = uintToBytes(absVal);
        if (neg) {
            return abi.encodePacked("-", digits);
        }
        return digits;
    }

    function bytesToInt(bytes memory b) internal pure returns (int256, bool) {
        if (b.length == 0) return (0, false);
        bool neg = false;
        uint256 start = 0;
        if (b[0] == 0x2D) { // '-'
            neg = true;
            start = 1;
        }
        uint256 result = 0;
        bool valid = false;
        for (uint256 i = start; i < b.length; i++) {
            if (b[i] >= 0x30 && b[i] <= 0x39) {
                result = result * 10 + (uint8(b[i]) - 48);
                valid = true;
            } else {
                return (0, false);
            }
        }
        if (!valid) return (0, false);
        int256 signed = neg ? -int256(result) : int256(result);
        return (signed, true);
    }
}
