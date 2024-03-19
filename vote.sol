// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.0;

import {SafeMath} from "./math/SafeMath.sol";
import "./models/vote.sol";
import "./models/actorInfo.sol";
import "./models/stake.sol";
import { FilAddress } from "./utils/FilAddress.sol";
import {DataConvert} from "./utils/data-convert.sol";
import {Rate} from "./rate.sol";

interface RateContract {
    function getSpNodeInfo() view external returns (Rate.SpNode[] memory);
}

interface StakeContract {
    function getStakeAddressList() view external returns (StakeInfo[] memory);
}

contract toLiquidate {

    using FilAddress for *;
    using DataConvert for *;
    using SafeMath for *;
    // Owner
    address owner;
    // Voting status
    uint agree = 2;
    uint reject = 3;
    uint abstain = 1;
    uint256 constant pointTenLength=10 ** 18; // Decimal point length
    uint256 public minSunFile = 1 * pointTenLength; // Minimum Pledge
    uint256 public warnPeriod = 5; // Alarm cycle
    uint256 public votePeriod = 8; // Voting cycle

    Voter[]  vs; // Voter array
    warnNodeInfo [] wnfs; // Alarm node
    mapping (address => Voter[]) public warnNodeMap; // Fixed proposal, voters

    address public rateContractAddr; // Interest rate contract address
    address public loanContractAddr; // Loan Contract Address
    address public stakeContractAddr; // Pledge Contract Address

    // Initialization
    constructor(){
        owner = msg.sender;
    }

    // Log
    event Log(address,uint256,bool,bool);

    // Verify owner
    modifier checkAdmin(){
        require(owner == msg.sender, "Not an administrator, can't make changes");
        _;
    }

    // Update administrator
    function modifyAdmin(address admin) public checkAdmin {
        owner = admin;
    }

    // Alarm node list
    function getWarnNode() public view returns (warnNodeInfo[] memory){
        return wnfs;
    }

    // Set interest rate contract address
    function setRateContractAddr(address rateAddr) public checkAdmin{
        rateContractAddr = rateAddr;
    }

    // Set loan contract address
    function setLoanContractAddr(address loanAddr) public checkAdmin{
        loanContractAddr = loanAddr;
    }

    // Set up a pledge contract address
    function setStakeContractAddr(address stakeAddr) public checkAdmin{
        stakeContractAddr = stakeAddr;
    }

    // Set associated contract address at once
    function setAllContractAddr(address[3] calldata addrList) public checkAdmin {
        rateContractAddr = addrList[0];
        loanContractAddr = addrList[1];
        stakeContractAddr = addrList[2];
    }

    // Set alarm cycle
    function setWarnPeriod(uint256 value) public checkAdmin{
        require(value > 0 ,"warnPeriod cannot be zero");
        warnPeriod = value;
    }

    // Set voting cycle
    function setVotePeriod(uint256 value) public checkAdmin{
        require(value > 0 ,"votePeriod cannot be zero");
        votePeriod = value;
    }

    // Set the minimum amount of fixed currency
    function setMinSunFile(uint256 value) public checkAdmin{
        require(value > 0 ,"minSunFile cannot be zero");
        minSunFile = value * pointTenLength;
    }


    // Check alarm nodes
    function checkWarnNode() public checkAdmin view returns (warnNodeInfo[] memory){
        // Joining node, liquidation rate
        Rate.SpNode[] memory af = RateContract(rateContractAddr).getSpNodeInfo();

        uint h = 0;
        warnNodeInfo[] memory wnfs1 = new warnNodeInfo[](af.length);
        for(uint256 i = 0;i < af.length; i++){
            // acAddress
            address acAddress = af[i].actorId.toIDAddress();
            // Total balance
            uint256 totalBa = acAddress.balance;
            // Debt ratio
            uint256 debtRate;
            if (af[i].nodeDebt == 0 || totalBa == 0){
                debtRate = 0;
            }else{
                debtRate = af[i].nodeDebt * pointTenLength / totalBa;
            }

            if(debtRate >= af[i].liquidationRate){
                warnNodeInfo memory wf;
                wf.minerId = af[i].actorId;
                wf.addr = acAddress;
                wf.totalDebt = af[i].nodeDebt;
                wf.warnTime = block.timestamp;
                wnfs1[h] = wf;
                h++;
            }
        }

        return wnfs1;
    }


    // Fixed voting
    function solidifiedVote(address warnNodeAddr) public checkAdmin {
        if(!checkwarnNodeMap(warnNodeAddr)){
            delete vs;
            // Pledged users
            StakeInfo[] memory sf = StakeContract(stakeContractAddr).getStakeAddressList();
            uint256 votes; // Vote count
            for(uint256 i = 0;i < sf.length; i++){

                if(sf[i].stakeBalance < minSunFile){
                    continue ;
                }
                Voter memory v;
                v.addr = sf[i].stakeAddr;
                v.weight = sf[i].stakeBalance;
                vs.push(v);
                votes += sf[i].stakeBalance;
            }

            // Obtain proposals
            warnNodeInfo memory wnif;
            // Proposal binding voters
            wnif.addr = warnNodeAddr;
            wnif.totalVote = votes;
            wnfs.push(wnif);
            warnNodeMap[wnif.addr] = vs;
        }
    }

    // Obtain individual alarm information
    function getWarnNodeByIndex(address addr) public view returns (warnNodeInfo memory){
        warnNodeInfo memory wf;
        warnNodeInfo[] memory wnif = checkWarnNode();
        for (uint256 i = 0; i < wnif.length; i++){
            if (wnif[i].addr == addr){
                wf = wnif[i];
                break;
            }
        }
        return wf;
    }

    // Participate in voting
    function takeVote(address proposal,uint256 voteType) public {
        bool checkProposal=  checkwarnNodeMap(proposal);
        require(checkProposal, "no proposals to vote on");

        // Positioning proposal
        if(checkwarnNodeMap(proposal) && voteType > 0 && proposal != address(0)){
            // Positioning voters
            Voter memory vr;
            bool checkVoted = false;
            uint256 voterIndex;
            Voter[] memory vrData = warnNodeMap[proposal];
            for(uint i = 0;i < vrData.length; i++){
                if(vrData[i].addr == msg.sender){
                    vr = vrData[i];
                    voterIndex = i;
                    checkVoted = true;
                    break;
                }
            }

            require(checkVoted, "you do not have voting rights");
            require(!vr.voted, "You already voted.");

            if(checkVoted && !vr.voted){
                // Positioning proposal node data
                warnNodeInfo memory wf;
                uint256 warnIndex;
                for (uint i = 0;i < wnfs.length; i++){
                    if(wnfs[i].addr == proposal){
                        wf = wnfs[i];
                        warnIndex = i;
                        break ;
                    }
                }

                // Counting votes
                if (voteType == abstain){
                    wf.abstainCount += vr.weight;
                }else if(voteType == agree){
                    wf.agreeCount += vr.weight;
                }else if (voteType == reject){
                    wf.rejectCount += vr.weight;
                }

                // Update voting results
                wnfs[warnIndex] = wf;

                // Update voter data
                vr.voted = true;
                vr.voteType = voteType;
                vr.weight = 0;
                warnNodeMap[proposal][voterIndex] = vr;
            }
        }
    }

    // Obtaining voting rights
    function getVoterWeight(address proposal) public view returns (uint256){
        uint256 weight;
        Voter[] memory voteAr = warnNodeMap[proposal];
        for (uint256 i=0;i<voteAr.length;i++){
            if(voteAr[i].addr == msg.sender){
                weight = voteAr[i].weight;
            }
        }

        return weight;
    }

    // Delete proposal, voters
    function delwarnNodeMap(address addr) public checkAdmin {
        delete warnNodeMap[addr];
        delWarnNode(addr);
    }

    // Check if the proposal exists
    function checkwarnNodeMap(address addr) private view returns(bool){
        Voter[] memory voteAr = warnNodeMap[addr];
        if (voteAr.length == 0){
            return false;
        }else{
            return true;
        }
    }

    // Delete alarm nodes
    function delWarnNode(address addr) public checkAdmin  {
        for (uint256 i = 0;i < wnfs.length;i++){
            if (addr == wnfs[i].addr){
                wnfs[i] = wnfs[wnfs.length - 1];
                wnfs.pop();
            }
        }
    }
}
