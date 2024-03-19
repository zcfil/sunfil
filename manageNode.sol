// SPDX-License-Identifier: MIT
pragma solidity >=0.4.16 <0.9.0;

import { MinerAPI } from "@zondax/filecoin-solidity/contracts/v0.8/MinerAPI.sol";
import { PrecompilesAPI } from "@zondax/filecoin-solidity/contracts/v0.8/PrecompilesAPI.sol";
import { FilAddresses } from "@zondax/filecoin-solidity/contracts/v0.8/utils/FilAddresses.sol";
import { BigInts } from "@zondax/filecoin-solidity/contracts/v0.8/utils/BigInts.sol";
import { CommonTypes } from "@zondax/filecoin-solidity/contracts/v0.8/types/CommonTypes.sol";
import { MinerTypes } from "@zondax/filecoin-solidity/contracts/v0.8/types/MinerTypes.sol";
import "./utils/FilAddress.sol";

interface PondCall {
    function changeOwnerAddress(uint64,CommonTypes.FilAddress memory) external;
    function withdraw(uint64 target, uint256 amount) external;
    function changeBeneficiary(uint64 target, MinerTypes.ChangeBeneficiaryParams memory params) external;
    function changeWorkerAddress(uint64 target, MinerTypes.ChangeWorkerAddressParams memory params) external;
    function confirmChangeWorkerAddress(uint64 target) external;
}

contract ManageNode {
    // Define the Response event and output the result success and data returned by the call
    event Response(bool success, bytes data);

    // Node information
    struct ActorInfo {
        uint64  actorId;        // Node ID
        address operator;       // Operator
        uint64  ownerId;        // owner ID
        int16   mortgageType;   // 1 owner，2 beneficiary
        uint256  height;
    }
    address admin;           // Administrator address
    
    // Beneficiary parameters
    uint256 constant beneficiaryQuota =    4000000000000000000000000000000000000;
    int64 constant beneficiaryExpiration = 4600000000000000000;

    address public debtAddress;   // Loan Contract Address
    address public pondAddress;   // Pond Contract Address
    uint64 PondActorID;     // Contract ID

    mapping(uint64 => ActorInfo) miners ; // List of miner arrays
    uint64 minerTotal;      // Total miners
    mapping(uint64 => uint64) minerIndex; // Node ID miners array index

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
    
    // Replace with a new admin
    function updateAdmin(address _admin) public onlyAdmin {
        admin = _admin;
    }

    // Set loan contract address
    function setDebtContractAddr(address addr) public onlyAdmin {
       debtAddress = addr;
    }

    // Set Pool Contract Address
    function setPondContractAddr(address addr) public onlyAdmin {
       pondAddress = addr;
       PondActorID = PrecompilesAPI.resolveEthAddress(addr);
    }

    // Initialize partial information
    constructor() {
        admin = msg.sender;
        address addr;
        ActorInfo memory act = ActorInfo(18141,addr,0,1,block.number);
        // Save array index
        minerTotal++;
        minerIndex[18141] = minerTotal;
        miners[minerTotal]= act;
        ActorInfo memory act2 = ActorInfo(18142,addr,0,2,block.number);
        // Save array index
        minerTotal++;
        minerIndex[18142] = minerTotal;
        miners[minerTotal]= act2;
    }

    // Node information
    function getMinersByActorId(uint64 actorId) public view returns(ActorInfo memory) {
        uint64 index = minerIndex[actorId];
        return miners[index];
    }
    // Get the miner list
    function getMiners() public view returns(ActorInfo[] memory) {
        ActorInfo[] memory actors = new ActorInfo[](minerTotal);
        for (uint64 i = 0;i<minerTotal;i++){
            actors[i] = miners[i+1];
        }
        return actors;
    }
    // Node onboarding
    function minerJoining(uint64 target,address op) public {
        ActorInfo memory actor = getMinersByActorId(target);
        require(actor.ownerId == 0, "miner already exists");

        // Obtain the original owner save
        uint64 ownerID = getOwner(target);
        require( ownerID == getBeneficiary(target), "Owner != Beneficiary");
        // Replace with a new owner
        CommonTypes.FilAddress memory filAddr = FilAddresses.fromActorID(PondActorID);
        PondCall(pondAddress).changeOwnerAddress(target, filAddr);
        // Save onboarding data
        ActorInfo memory act = ActorInfo(target,op,ownerID,1,block.number);
        // Save array index
        minerTotal++;
        minerIndex[target] = minerTotal;
        miners[minerTotal] = act;
    }

    // Node Resignation
    function minerExiting(uint64 actorID) public onlyOwner(actorID) {
        ActorInfo memory actor = getMinersByActorId(actorID);
        require(actor.ownerId > 0, "miner not exists");
        // Judging Debts
        address addr = FilAddress.toIDAddress(actorID);
        // Query token quantity from pledged smart contracts
        (bool success, bytes memory result) = debtAddress.call(
            abi.encodeWithSignature("balanceOf(address)", addr)
        );
        require(success, "External call failed");
        uint256 actorBalance = abi.decode(result, (uint256));
        // Determine whether the node is in debt
        require(actorBalance == 0, "Node debt, unable to resign");

        replace_with_old_owner_address(actorID);
        // Remove node
        miners[minerIndex[actorID]] = miners[minerTotal];
        minerIndex[miners[minerTotal].actorId] = minerIndex[actorID];
        delete miners[minerTotal];
        delete minerIndex[actorID];
        minerTotal--;
    }
    // Change owner to old owner
    function replace_with_old_owner_address(uint64 target) private {
        ActorInfo memory info = getMinersByActorId(target);
        CommonTypes.FilAddress memory filAddr = FilAddresses.fromActorID(info.ownerId);
        
        PondCall(pondAddress).changeOwnerAddress(target, filAddr);
    }

    // Node setting operator
    function setOperator(uint64 actorId,address op) public onlyOwner(actorId) {
        uint64 index = minerIndex[actorId];
        miners[index].operator = op;
    }

    // Obtain node owner
    function getOwner(uint64 target) private returns (uint64) {
        MinerTypes.GetOwnerReturn memory owner =  MinerAPI.getOwner(CommonTypes.FilActorId.wrap(target));
        return PrecompilesAPI.resolveAddress(owner.owner);
    }
    // Obtain node beneficiaries
    function getBeneficiary(uint64 target) private returns (uint64) {
        MinerTypes.GetBeneficiaryReturn memory beneficiary =  MinerAPI.getBeneficiary(CommonTypes.FilActorId.wrap(target));
        return PrecompilesAPI.resolveAddress(beneficiary.active.beneficiary);
    }

    // Employment of beneficiaries
    function minerJoiningBeneficiary(uint64 target,address op) public {
        // Obtain the original owner save
        uint64 ownerID = getOwner(target);
        // Replace with a new beneficiary
        MinerTypes.ChangeBeneficiaryParams memory params = MinerTypes.ChangeBeneficiaryParams(FilAddresses.fromActorID(PondActorID),BigInts.fromUint256(beneficiaryQuota),CommonTypes.ChainEpoch.wrap(beneficiaryExpiration));
        PondCall(pondAddress).changeBeneficiary(target, params);
        // Save onboarding data
        ActorInfo memory act = ActorInfo(target,op,ownerID,2,block.number);
        // Save array index
        minerTotal++;
        minerIndex[target] = minerTotal;
        miners[minerTotal] = act;
    }
    
    // Resignation of beneficiary nodes
    function minerExitingBeneficiary(uint64 actorID) public onlyOwner(actorID) {
        // Judging Debts
        address addr = FilAddress.toIDAddress(actorID);
        // Query token quantity from pledged smart contracts
        (bool success, bytes memory result) = debtAddress.call(
            abi.encodeWithSignature("balanceOf(address)", addr)
        );
        require(success, "External call failed");
        uint256 actorBalance = abi.decode(result, (uint256));
        // Determine whether the node is in debt
        require(actorBalance == 0, "Node debt, unable to resign");

        replace_beneficiary_with_old_owner(actorID);
        // Remove node
        miners[minerIndex[actorID]] = miners[minerTotal];
        minerIndex[miners[minerTotal].actorId] = minerIndex[actorID];
        delete miners[minerTotal];
        delete minerIndex[actorID];
        minerTotal--;
    }

    // Replace beneficiary with old owner
    function replace_beneficiary_with_old_owner(uint64 target) private {
        ActorInfo memory info = getMinersByActorId(target);
        CommonTypes.FilAddress memory filAddr = FilAddresses.fromActorID(info.ownerId);
        
        MinerTypes.ChangeBeneficiaryParams memory params = MinerTypes.ChangeBeneficiaryParams(filAddr,BigInts.fromUint256(0),CommonTypes.ChainEpoch.wrap(0));
        PondCall(pondAddress).changeBeneficiary(target, params);
    }

    // Determine whether the repayment conditions are met
    function isSufficient(uint64 target, uint256 amount) private returns (bool) {
        (uint256 value,) = BigInts.toUint256(MinerAPI.getAvailableBalance(CommonTypes.FilActorId.wrap(target)));
        //判断金额是否充足
        require(value >= amount,"Insufficient available balance");
        //判断欠款金额
        address targetAddr = FilAddress.toIDAddress(target);
        (bool success, bytes memory result) = debtAddress.call(
            abi.encodeWithSignature("balanceOf(address)", targetAddr)
        );
        require(success, "External call balanceOf failed");
        (uint256 targetBalance) = abi.decode(result, (uint256));
        // Determine if there is any outstanding amount
        require(targetBalance > 0,"Node has no outstanding payments");
        return true;
    }

    // Modify Worker Wallet
    function changeWorkerAddress(uint256 paramTarget,uint256 paramWorker, uint256[] memory paramControl) public onlyOwner(uint64(paramTarget)) {

        uint64 target = uint64(paramTarget);
        uint64 worker = uint64(paramWorker);
        uint64[] memory control = new uint64[](paramControl.length);
        for(uint256 i = 0;i<paramControl.length;i++){
            control[i] = uint64(paramControl[i]);
        }

        CommonTypes.FilAddress memory filAddr = FilAddresses.fromActorID(worker);
        CommonTypes.FilAddress[] memory controlFil = new CommonTypes.FilAddress[](control.length);
        for (uint256 i = 0;i<control.length;i++){
            controlFil[i] = FilAddresses.fromActorID(control[i]);
        }
        MinerTypes.ChangeWorkerAddressParams memory param = MinerTypes.ChangeWorkerAddressParams(filAddr,controlFil);
        
        PondCall(pondAddress).changeWorkerAddress(target,param);
    }

    // Confirm modifying the worker wallet
    function confirmChangeWorkerAddress(uint64 target) public onlyOwner(target) {
        PondCall(pondAddress).confirmChangeWorkerAddress(target);
    }
}