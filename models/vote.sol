// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.0;

struct nodeInfo{
     address addr ; // Address
} 

struct joinNode{
    uint64 minerId;
    address addr ; // Address
} 

struct pledgeInfo {
    address addr;   // Address
    uint256 sunFil; // Holding tokens
}

struct warnNodeInfo{
    uint64 minerId;         // Node number
    address addr;           // Wallet address
    uint256 totalDebt;      // Total debt
    uint256 warnTime;       // Alarm time
    uint256 agreeCount;     // Agree to statistics
    uint256 rejectCount;    // Refuse statistics
    uint256 abstainCount;   // Waiver statistics
    uint256 totalVote;      // Total number of votes
}

 // Voters
struct Voter {
    address addr;       // Voters
    uint256 weight;     // Vote counting
    bool voted;         // If true, it means that the person has voted
    address delegate;   // Entrusted person
    uint256 voteType;   // Voting type 1: Abstention, 2: Agree, 3: Oppose
}

// Proposal
struct Proposal {
    string name;            // For short
    uint256 agreeCount;     // Agree to statistics
    uint256 rejectCount;    // Refuse statistics
    uint256 abstainCount;   // Waiver statistics
}