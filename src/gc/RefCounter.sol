// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title RefCounter — Reference counting garbage collector
/// @notice Tracks reference counts for dynamically allocated objects (lists, dicts, sets, strings).
///         When refcount reaches 0, the object is freed.
library RefCounter {
    // Object types
    uint8 constant OBJ_LIST = 1;
    uint8 constant OBJ_DICT = 2;
    uint8 constant OBJ_SET = 3;
    uint8 constant OBJ_STRING = 4;

    struct GCState {
        mapping(uint256 => uint256) refcounts;   // objectId → refcount
        mapping(uint256 => uint8) objectTypes;    // objectId → type
        mapping(uint256 => bool) isLive;          // objectId → alive?
        uint256 nextObjectId;
        uint256 totalAllocated;
        uint256 totalFreed;
    }

    function alloc(GCState storage gc, uint8 objType) internal returns (uint256 id) {
        gc.nextObjectId++;
        id = gc.nextObjectId;
        gc.refcounts[id] = 1;
        gc.objectTypes[id] = objType;
        gc.isLive[id] = true;
        gc.totalAllocated++;
    }

    function incRef(GCState storage gc, uint256 id) internal {
        if (id == 0) return; // null reference
        if (!gc.isLive[id]) return; // already freed
        gc.refcounts[id]++;
    }

    function decRef(GCState storage gc, uint256 id) internal returns (bool freed) {
        if (id == 0) return false;
        if (!gc.isLive[id]) return false;
        gc.refcounts[id]--;
        if (gc.refcounts[id] == 0) {
            gc.isLive[id] = false;
            gc.totalFreed++;
            return true;
        }
        return false;
    }

    function getRefcount(GCState storage gc, uint256 id) internal view returns (uint256) {
        return gc.refcounts[id];
    }

    function isAlive(GCState storage gc, uint256 id) internal view returns (bool) {
        return gc.isLive[id];
    }

    function getObjectType(GCState storage gc, uint256 id) internal view returns (uint8) {
        return gc.objectTypes[id];
    }

    function stats(GCState storage gc) internal view returns (uint256 allocated, uint256 freed, uint256 live) {
        return (gc.totalAllocated, gc.totalFreed, gc.totalAllocated - gc.totalFreed);
    }
}
