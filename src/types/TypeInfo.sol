// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

enum TypeTag {
    UNKNOWN,    // could not infer
    INT,
    FLOAT,
    STRING,
    BOOL,
    NONE,
    LIST,       // list of elementType
    FUNCTION,   // function with paramTypes and returnType
    DICT,       // dictionary
    SET         // set
}

struct TypeInfo {
    TypeTag tag;
    // For LIST: elementType index in typeInfos
    // For FUNCTION: return type index in typeInfos
    uint256 innerType;
    // For FUNCTION: index in auxTypes where param types start
    // For LIST: 0 (unused)
    uint256 auxStart;
    // For FUNCTION: number of params
    uint256 auxCount;
}

// Float fixed-point constants
uint256 constant FLOAT_SCALE = 1_000_000;
uint256 constant FLOAT_TAG = 5;
uint256 constant FLOAT_TAG_SHIFT = 252;
uint256 constant FLOAT_VALUE_MASK = (1 << 252) - 1;
