// SPDX-License-Identifier: MIT
pragma solidity >=0.4.16 <0.9.0;

import { MinerAPI } from "@zondax/filecoin-solidity/contracts/v0.8/MinerAPI.sol";
import { PrecompilesAPI } from "@zondax/filecoin-solidity/contracts/v0.8/PrecompilesAPI.sol";
import { FilAddresses } from "@zondax/filecoin-solidity/contracts/v0.8/utils/FilAddresses.sol";
import { BigInts } from "@zondax/filecoin-solidity/contracts/v0.8/utils/BigInts.sol";
import { CommonTypes } from "@zondax/filecoin-solidity/contracts/v0.8/types/CommonTypes.sol";
import { MinerTypes } from "@zondax/filecoin-solidity/contracts/v0.8/types/MinerTypes.sol";
import "./utils/FilAddress.sol";
import {SafeMath} from "./math/SafeMath.sol";
import {DataConvert} from "./utils/data-convert.sol";

contract Miners {
    using DataConvert for *;
    // Define the Response event and output the result success and data returned by the call
    event Response(bool success, bytes data);

    // Node information
    struct ActorInfo {
        uint64  actorId;        // Node ID
        address operator;       // Operator
        uint64  ownerId;       // owner ID
        int16   mortgageType;  // 1 owner，2 beneficiary
    }
    address admin;           // Administrator address
    address public rateAddr = 0xdb4e6Bff063de9D104280067b1e9e3d3644b36f4; // Interest rate contract address
    address operateAddr;
    address riskAddr;
    
    // Beneficiary parameters
    uint256 constant beneficiaryQuota =    4000000000000000000000000000000000000;
    int64 constant beneficiaryExpiration = 4600000000000000000;

    address public stakeAddress;   // Pledge Contract Address
    address public debtAddress;   // Loan Contract Address
    address public rateAddress;   // Loan Contract Address

    uint64 contractActorID;     // Contract ID

    mapping(uint64 => ActorInfo) miners ; // List of miner arrays
    uint64 minerTotal;      // Total miners
    mapping(uint64 => uint64) minerIndex; // Node ID-miners array index
    
    //mapping(address => uint) public operatorActorID; //操作人-节点ID
    event Log(bool success, bytes data,uint256 balance);

    // Determine if it is the operator's method
    modifier onlyOperator(uint64 actorId) {
        uint64 index = minerIndex[actorId];
        require(index > 0 && index <= minerTotal, "Invalid miner index.");
        require(msg.sender == miners[index].operator || msg.sender == admin, "No operation permissions");
        _;
    }
    // Determine if it is an owner
    modifier onlyOwner(uint64 actorId) {
        uint64 index = minerIndex[actorId];
        require(index > 0 && index <= minerTotal, "Invalid miner index.");
        require(msg.sender == FilAddress.toIDAddress(miners[index].ownerId) || msg.sender == admin, "No owner permissions");
        _;
    }
    // Determine if it is an administrator
    modifier onlyAdmin() {
        require(msg.sender == admin, "No admin permissions");
        _;
    }

    // Determine if it is from a pledge contract request
    modifier onlyStakeContract() {
        require(msg.sender == stakeAddress, "No stake permissions");
        _;
    }

    // Set interest rate contract address
    function setRateAddrContractAddr(address addr) public onlyAdmin {
       rateAddr = addr;
    }

    // Set up a pledge contract address
    function setStakeContractAddr(address addr) public onlyAdmin {
       stakeAddress = addr;
    }

    // Set loan contract address
    function setDebtContractAddr(address addr) public onlyAdmin {
       debtAddress = addr;
    }

    // Initialize partial information
    constructor() {
        operateAddr = FilAddress.toIDAddress(26573);
        riskAddr = FilAddress.toIDAddress(26572);
        admin = msg.sender;
        contractActorID = PrecompilesAPI.resolveEthAddress(address(this));
        address addr;
        ActorInfo memory act = ActorInfo(18141,addr,0,1);
        // Save array index
        minerTotal++;
        minerIndex[18141] = minerTotal;
        miners[minerTotal]= act;
        ActorInfo memory act2 = ActorInfo(18142,addr,0,2);
        // Save array index
        minerTotal++;
        minerIndex[18142] = minerTotal;
        miners[minerTotal]= act2;
    }
    function getContractActorID() public view returns(uint64){
        return contractActorID;
    }
    // Node length
    function getMinersLenght() public view returns(uint) {
        return minerTotal;
    }
    // Node information
    function getMinersByIndex(uint64 i) public view returns(ActorInfo memory) {
        require(i > 0 && i <= minerTotal, "Invalid miner index.");
        return miners[i];
    }
    // Node information
    function getMinersByActorId(uint64 actorId) public view returns(ActorInfo memory) {
        uint64 index = minerIndex[actorId];
        require(index > 0 && index <= minerTotal, "Invalid miner index.");
        return miners[index];
    }
    // Node onboarding
    function minerJoining(uint64 target,address op) public {
        // Obtain the original owner save
        uint64 ownerID = getOwner(CommonTypes.FilActorId.wrap(target));
        // Replace with a new owner
        CommonTypes.FilAddress memory filAddr = FilAddresses.fromActorID(contractActorID);
        MinerAPI.changeOwnerAddress(CommonTypes.FilActorId.wrap(target), filAddr);
        // Save onboarding data
        ActorInfo memory act = ActorInfo(target,op,ownerID,1);
        // Save array index
        minerTotal++;
        minerIndex[target] = minerTotal;
        miners[minerTotal] = act;
    }
    ActorInfo actor;
    // Node Resignation
    function minerExiting(uint64 actorID) public onlyOperator(actorID) {
        // Judging Debts
        operateAddr = FilAddress.toIDAddress(actorID);
        // Query token quantity from pledged smart contracts
        (bool success, bytes memory result) = stakeAddress.call(
            abi.encodeWithSignature("balanceOf(address)", operateAddr)
        );
        require(success, "External call failed");
        uint256 actorBalance = abi.decode(result, (uint256));
        // Determine whether the node is in debt
        require(actorBalance == 0, "Node debt, unable to resign");

        replace_with_old_owner_address(actorID);
        // Remove node
        delete miners[minerIndex[actorID]];
        delete minerIndex[actorID];
        minerTotal--;
    }

    // Node setting operator
    function setOperator(uint64 actorId,address op) public onlyOwner(actorId) {
        uint64 index = minerIndex[actorId];
        miners[index].operator = op;
    }

    // Query existing operators
    function getOperator(uint64 actorId) public view returns (address) {
        uint64 index = minerIndex[actorId];
        return miners[index].operator;
    }

    // Node withdrawal
    function withdraw(uint64 target, uint256 amount) external payable onlyOperator(target) {
        ActorInfo memory miner = getMinersByActorId(target);
        (bool success, bytes memory data) = rateAddr.call(
            abi.encodeWithSignature("WithdrawalLimit(uint64)",target)
        );
        require(success, "balanceOf Contract request failed");
        uint256 wLimit = DataConvert.BytesToUint(data);
        require(amount <= wLimit && amount > 0,"Exceeding available limit");
        // Withdrawal to internal contract
        MinerAPI.withdrawBalance(CommonTypes.FilActorId.wrap(target),BigInts.fromUint256(amount));  
        // Transfer to existing owner
        payable(FilAddress.toIDAddress(miner.ownerId)).transfer(amount);
    }

    // Loan
    function loan(uint64 target, uint256 amount) external payable onlyOperator(target) {
        // Obtain maximum loan amount
        (bool successRepay, bytes memory resultRepay) = rateAddress.call(
            abi.encodeWithSignature("MaxBorrowableAmount(uint64)", target)
        );
        require(successRepay, "External call WithdrawalLimit failed");
        (uint256 maxLoan) = abi.decode(resultRepay, (uint256));

        // Determine whether the loan amount is greater than the available loan amount
        // Determine whether the loan amount is greater than the amount of the smart contract
        require(amount <= maxLoan && amount <= address(this).balance, "Excessive borrowing amount");

        // Bookkeeping
        // Bookkeeping in lending smart contracts
        address targetAddr = FilAddress.toIDAddress(target);
        (bool successAddDebt, ) = debtAddress.call(
            abi.encodeWithSignature("addDebts(uint256,address)", amount, targetAddr)
        );
        require(successAddDebt, "External call failed");

        // Transfer to node
        payable(FilAddress.toIDAddress(target)).transfer(amount);
    }

    
   // Node available balance
   // target node number
   function getAvailableBalance(CommonTypes.FilActorId minerId) public returns (uint256){
      CommonTypes.BigInt memory ba = MinerAPI.getAvailableBalance(minerId);
      return ba.val.BytesToUint();
   }

    // Repayment
    function repayment(uint64 target, uint256 amount,bool isTotal) public onlyOperator(target) {
        (uint256 value,) = BigInts.toUint256(MinerAPI.getAvailableBalance(CommonTypes.FilActorId.wrap(target)));
        // Determine if the amount is sufficient
        require(value >= amount,"Insufficient available balance");
        // Determine the amount of debt owed
        address targetAddr = FilAddress.toIDAddress(target);
        (bool success, bytes memory result) = debtAddress.call(
            abi.encodeWithSignature("balanceOf(address)", targetAddr)
        );
        require(success, "External call balanceOf failed");
        (uint256 targetBalance) = abi.decode(result, (uint256));
        // Determine if there is any outstanding amount
        require(targetBalance > 0,"Node has no outstanding payments");

        // Write off accounts and obtain the amount that should be transferred
        (bool successRepay, bytes memory resultRepay) = debtAddress.call(
            abi.encodeWithSignature("repayDebts(uint256,bool)", target, isTotal)
        );
        require(successRepay, "External call failed");
        (,uint256 operateRepay,uint256 riskRepay) = abi.decode(resultRepay, (uint256,uint256,uint256));

        // Withdrawal to internal contract
        MinerAPI.withdrawBalance(CommonTypes.FilActorId.wrap(target),BigInts.fromUint256(amount));
        // Divide accounts
        payable(operateAddr).transfer(operateRepay);  // Operating profit sharing
        payable(riskAddr).transfer(riskRepay);     // Risk pool

    }

    function getOwner(CommonTypes.FilActorId target) public returns (uint64) {
        MinerTypes.GetOwnerReturn memory owner =  MinerAPI.getOwner(target);
        return PrecompilesAPI.resolveAddress(owner.owner);
    }

    // Replace owner
    function replace_with_old_owner_address(uint64 target) public {
        ActorInfo memory info = getMinersByActorId(target);
        CommonTypes.FilAddress memory filAddr = FilAddresses.fromActorID(info.ownerId);
        
        MinerAPI.changeOwnerAddress(CommonTypes.FilActorId.wrap(target), filAddr);
    }

    // Transfer currency from contract to specified address (payable)
    function contractToAddress(uint256 amount,address _address) external payable onlyStakeContract {
       payable(_address).transfer(amount);
    }

    // Currency transfer from address to contract (payable)
    function addressToContract() external payable{}
    
    
    // Get the miner list
    function getMiners() public view returns(ActorInfo[] memory) {
        ActorInfo[] memory actors = new ActorInfo[](minerTotal);
        for (uint64 i = 0;i<minerTotal;i++){
            actors[i] = miners[i+1];
        }
        return actors;
    }

    // Employment of beneficiaries
    function minerJoiningBeneficiary(uint64 target,address op) public {
        // Obtain the original owner save
        uint64 ownerID = getOwner(CommonTypes.FilActorId.wrap(target));
        // Replace with a new beneficiary
        MinerTypes.ChangeBeneficiaryParams memory params = MinerTypes.ChangeBeneficiaryParams(FilAddresses.fromActorID(contractActorID),BigInts.fromUint256(beneficiaryQuota),CommonTypes.ChainEpoch.wrap(beneficiaryExpiration));
        MinerAPI.changeBeneficiary(CommonTypes.FilActorId.wrap(target), params);
        // Save onboarding data
        ActorInfo memory act = ActorInfo(target,op,ownerID,2);
        // Save array index
        minerTotal++;
        minerIndex[target] = minerTotal;
        miners[minerTotal] = act;
    }
    
    // Resignation of beneficiary nodes
    function minerExitingBeneficiary(uint64 actorID) public onlyOperator(actorID) {
        // Judging Debts
        operateAddr = FilAddress.toIDAddress(actorID);
        // Query token quantity from pledged smart contracts
        (bool success, bytes memory result) = stakeAddress.call(
            abi.encodeWithSignature("balanceOf(address)", operateAddr)
        );
        require(success, "External call failed");
        uint256 actorBalance = abi.decode(result, (uint256));
        // Determine whether the node is in debt
        require(actorBalance == 0, "Node debt, unable to resign");

        replace_beneficiary_with_old_owner(actorID);
        // Remove node
        delete miners[minerIndex[actorID]];
        delete minerIndex[actorID];
        minerTotal--;
    }

    // Change of beneficiary
    function replace_beneficiary_with_old_owner(uint64 target) private  {
        ActorInfo memory info = getMinersByActorId(target);
        CommonTypes.FilAddress memory filAddr = FilAddresses.fromActorID(info.ownerId);
        
        MinerTypes.ChangeBeneficiaryParams memory params = MinerTypes.ChangeBeneficiaryParams(filAddr,BigInts.fromUint256(0),CommonTypes.ChainEpoch.wrap(0));
        MinerAPI.changeBeneficiary(CommonTypes.FilActorId.wrap(target), params);
    }

}