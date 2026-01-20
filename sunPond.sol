// SPDX-License-Identifier: MIT
pragma solidity >=0.4.16 <0.9.0;

import { MinerAPI } from "@zondax/filecoin-solidity/contracts/v0.8/MinerAPI.sol";
import { PrecompilesAPI } from "@zondax/filecoin-solidity/contracts/v0.8/PrecompilesAPI.sol";
import { BigInts } from "@zondax/filecoin-solidity/contracts/v0.8/utils/BigInts.sol";
import { CommonTypes } from "@zondax/filecoin-solidity/contracts/v0.8/types/CommonTypes.sol";
import { MinerTypes } from "@zondax/filecoin-solidity/contracts/v0.8/types/MinerTypes.sol";
import { SendAPI } from "@zondax/filecoin-solidity/contracts/v0.8/SendAPI.sol";

contract SunPond {

    address admin;           // Administrator address

    address[] public payAuthorityAddress; // Payment permissions
    address[] public opAuthorityAddress; // Operation permissions

    uint64 contractActorID;     // Contract ID

    event Log(bool success, bytes data,uint256 balance);

    constructor() {
        admin = msg.sender;
        contractActorID = PrecompilesAPI.resolveEthAddress(address(this));
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

    // Payment constraints
    modifier onlyPayableContract() {
        bool auth = false;
        for (uint256 i=0;i<payAuthorityAddress.length;i++){
            if (msg.sender == payAuthorityAddress[i]){
                auth = true;
                break;
            }
        }
        require(auth, "No pay permissions");
        _;
    }

    // Operational constraints
    modifier onlyOpContract() {
        bool auth = false;
        for (uint256 i=0;i<opAuthorityAddress.length;i++){
            if (msg.sender == opAuthorityAddress[i]){
                auth = true;
                break;
            }
        }
        require(auth, "No op permissions");
        _;
    }

    // Grant contract address payment permission
    function GrantPayableAuthority(address addr) external onlyAdmin() {
        payAuthorityAddress.push(addr);
    }

    // Grant contract address operation permissions
    function GrantOpAuthority(address addr) external onlyAdmin() {
        opAuthorityAddress.push(addr);
    }

    // Remove payment permissions for contract addresses
    function RemovePayableAuthority(address addr) external onlyAdmin() {
        for (uint256 i = 0;i < payAuthorityAddress.length;i++){
            if (addr == payAuthorityAddress[i]){
                payAuthorityAddress[i] = payAuthorityAddress[payAuthorityAddress.length - 1];
                payAuthorityAddress.pop();
            }
        }
    }

    // Remove contract address operation permissions
    function RemoveOpAuthority(address addr) external onlyAdmin() {
        for (uint256 i = 0;i < opAuthorityAddress.length;i++){
            if (addr == opAuthorityAddress[i]){
                opAuthorityAddress[i] = opAuthorityAddress[opAuthorityAddress.length - 1];
                opAuthorityAddress.pop();
            }
        }
    }

    // Transfer of currency from contract to specified address (payable)
    function contractToAddress(uint256 amount,address _address) external payable onlyPayableContract {
       payable(_address).transfer(amount);
    }

    // Node withdrawal
    function withdraw(uint64 target, uint256 amount) external onlyOpContract() {
        // Withdrawal to internal contract
        MinerAPI.withdrawBalance(CommonTypes.FilActorId.wrap(target),BigInts.fromUint256(amount));  
    }

    // Modify Owner
    function changeOwnerAddress(uint64 target, CommonTypes.FilAddress memory filAddr) external onlyOpContract() {
        MinerAPI.changeOwnerAddress(CommonTypes.FilActorId.wrap(target), filAddr);
    }

    // Modify beneficiaries
    function changeBeneficiary(uint64 target, MinerTypes.ChangeBeneficiaryParams memory params) external onlyOpContract() {
        MinerAPI.changeBeneficiary(CommonTypes.FilActorId.wrap(target), params);
    }
    // Modify worker
    function changeWorkerAddress(uint64 target, MinerTypes.ChangeWorkerAddressParams memory params) external onlyOpContract() {
        MinerAPI.changeWorkerAddress(CommonTypes.FilActorId.wrap(target), params);
    }

    // Confirm changing worker
    function confirmChangeWorkerAddress(uint64 target) external onlyOpContract() {
        MinerAPI.confirmChangeWorkerAddress(CommonTypes.FilActorId.wrap(target));
    }

    // Modify PeerId
    function changePeerId(uint64 target , CommonTypes.FilAddress memory newId) external onlyOpContract() {
        MinerAPI.changePeerId(CommonTypes.FilActorId.wrap(target), newId);
    }

    // Modify Multiaddresses
    function changeMultiaddresses(uint64 target , MinerTypes.ChangeMultiaddrsParams memory params) external onlyOpContract() {
        MinerAPI.changeMultiaddresses(CommonTypes.FilActorId.wrap(target), params);
    }

    // Repayment of node debts
    function repayDebt(uint64 target) external onlyOpContract() {
        MinerAPI.repayDebt(CommonTypes.FilActorId.wrap(target));
    }

    // Transferring Coins from Contracts to Nodes
    function send(uint64 target,uint256 value) external payable onlyPayableContract { 
        SendAPI.send(CommonTypes.FilActorId.wrap(target),value);
    }
}
