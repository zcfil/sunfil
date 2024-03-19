// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.0;    
// Node information
struct ActorInfo {
    uint64  actorId;        // Node ID
    address operator;       // Operator
    uint64  ownerId;        // Owner ID
    int16   mortgageType;   // 1 owner，2 beneficiary
}