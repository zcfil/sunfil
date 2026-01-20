// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;


import { MinerAPI } from "@zondax/filecoin-solidity/contracts/v0.8/MinerAPI.sol";
import { BigInts } from "@zondax/filecoin-solidity/contracts/v0.8/utils/BigInts.sol";
import { CommonTypes } from "@zondax/filecoin-solidity/contracts/v0.8/types/CommonTypes.sol";
import "./utils/FilAddress.sol";
import {DataConvert} from "./utils/data-convert.sol";
import "./models/actorInfo.sol";

interface PondNodeCall {
    function getMinersByActorId(uint64) external view returns(ActorInfo calldata);
    function withdraw(uint64,uint256) external payable;
    function contractToAddress(uint256,address) external payable;
    function send(uint64,uint256) external payable;
}

interface RateContract {
    function withdrawalLimit(uint64) external returns (uint256);
    function getMaxBorrowableAmount(uint64) external view returns(uint256);
}

interface DebtContract {
    function balanceOf(address) external view returns (uint256);
}

contract OpNode {
    using DataConvert for *;
    address admin;           // Administrator address

    address public debtAddress;   // Loan Contract Address
    address public rateAddress;   // Interest rate contract address
    address public manageAddress;   // Node Contract Address
    address public pondAddress;   // Fund pool sub contract address
    address operateAddr;        // Operating profit distribution address
    address riskAddr;           // Risk capital address

    // Determine if it is the operator's method
    modifier onlyOperator(uint64 actorId) {
        // Node contract acquisition operator
        ActorInfo memory miner = PondNodeCall(manageAddress).getMinersByActorId(actorId);
        require(msg.sender == miner.operator || msg.sender == admin, "No operation permissions");
        _;
    }

    // Determine if it is an administrator
    modifier onlyAdmin() {
        require(msg.sender == admin, "No admin permissions");
        _;
    }

    // Replace with a new admin
    function updateAdmin(address _admin) public onlyAdmin {
        admin = _admin;
    }

    // Set interest rate contract address
    function setRateAddrContractAddr(address addr) public onlyAdmin {
       rateAddress = addr;
    }

    // Set loan contract address
    function setDebtContractAddr(address addr) public onlyAdmin {
       debtAddress = addr;
    }

    // Set Pool Contract Address
    function setPondContractAddr(address addr) public onlyAdmin {
       pondAddress = addr;
    }

    // Set operating profit distribution address
    function setOperateAddr(address addr) public onlyAdmin {
       operateAddr = addr;
    }
    
    // Set risk pool address
    function setRiskAddr(address addr) public onlyAdmin {
       riskAddr = addr;
    }

    // Set node contract address
    function setManageContractAddr(address addr) public onlyAdmin {
       manageAddress = addr;
    }

    // Set associated contract address at once
    function setAllContractAddr(address[4] calldata addrList) public onlyAdmin {
        rateAddress = addrList[0];
        debtAddress = addrList[1];
        pondAddress = addrList[2];
        manageAddress = addrList[3];
    }
    
    // Initialize partial information
    constructor() {
        admin = msg.sender;
    }

    // Node withdrawal
    function withdraw(uint64 target, uint256 amount, uint256 isTotal) external onlyOperator(target) {
        // Query node data
        ActorInfo memory miner = PondNodeCall(manageAddress).getMinersByActorId(target);

        uint256 wLimit = RateContract(rateAddress).withdrawalLimit(target);

        // If there is a corresponding identifier, assign the maximum amount queried to the account
        if (isTotal == 0) {
            amount = wLimit;
        }else {
            require(amount <= wLimit && amount > 0,"Exceeding available limit");
        }
        
        // Withdrawal to internal contract
        PondNodeCall(pondAddress).withdraw(target,amount);
        // Transfer to existing owner
        PondNodeCall(pondAddress).contractToAddress(amount,FilAddress.toIDAddress(miner.ownerId));
    }

    // Loan
    function loan(uint64 target, uint256 amount, uint256 isTotal) external onlyOperator(target) {
        // Obtain maximum loan amount
        uint256 maxLoan = RateContract(rateAddress).getMaxBorrowableAmount(target);

        if (isTotal == 0) {
            amount = maxLoan;
        }else {
            // Determine whether the loan amount is greater than the available loan amount
            // Determine whether the loan amount is greater than the amount of the smart contract
            require(amount <= maxLoan && amount <= pondAddress.balance, "Excessive borrowing amount");
        }

        // Bookkeeping
        // Bookkeeping in lending smart contracts
        address targetAddr = FilAddress.toIDAddress(target);
        (bool successAddDebt, ) = debtAddress.call(
            abi.encodeWithSignature("addDebts(uint256,address)", amount, targetAddr)
        );
        require(successAddDebt, "External call failed");

        // Transfer to node
        PondNodeCall(pondAddress).send(target,amount);
    }

    // Repayment
    function repayment(uint64 target, uint256 amount,uint256 isTotal) public onlyOperator(target) {
        address targetAddr = FilAddress.toIDAddress(target);
        require(isSufficient(target,targetAddr,amount), "External call failed");
        // Write off accounts and obtain the amount that should be transferred
        (bool successRepay, bytes memory resultRepay) = debtAddress.call(
            abi.encodeWithSignature("repayDebts(uint256,address,bool)", amount, targetAddr, isTotal)
        );
        require(successRepay, "External call failed");
        (uint256 pondRepay,uint256 operateRepay,uint256 riskRepay) = abi.decode(resultRepay, (uint256,uint256,uint256));

        // Withdrawal to internal contract
        PondNodeCall(pondAddress).withdraw(target,pondRepay);
        // Divide accounts
        PondNodeCall(pondAddress).contractToAddress(operateRepay,operateAddr);// Operating profit sharing

        if (riskRepay > 0) {
            PondNodeCall(pondAddress).contractToAddress(riskRepay,riskAddr);  // Risk pool
        }
    }

    // Determine whether the repayment conditions are met
    function isSufficient(uint64 target, address targetAddr, uint256 amount) private returns (bool) {
        (uint256 value,) = BigInts.toUint256(MinerAPI.getAvailableBalance(CommonTypes.FilActorId.wrap(target)));
        // Determine if the amount is sufficient
        require(value >= amount,"Insufficient available balance");
        // Determine the amount of debt owed
        uint256 targetBalance = DebtContract(debtAddress).balanceOf(targetAddr);

        //Determine if there is any outstanding amount
        require(targetBalance > 0,"Node has no outstanding payments");
        return true;
    }
}
