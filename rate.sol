// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.17;

import { MinerAPI } from "@zondax/filecoin-solidity/contracts/v0.8/MinerAPI.sol";
import { CommonTypes } from "@zondax/filecoin-solidity/contracts/v0.8/types/CommonTypes.sol";
import { FilAddress } from "./utils/FilAddress.sol";
import {DataConvert} from "./utils/data-convert.sol";
import {SafeMath} from "./math/SafeMath.sol";
import {ManageNode} from "./manageNode.sol";

interface ManageNodeContract {
    function getMinersByActorId(uint64 actorId) view external returns (ManageNode.ActorInfo memory);
    function getMiners() view external returns (ManageNode.ActorInfo[] memory);
}

interface StakeContract {
     function totalSupply() external view returns (uint256);
}

interface DebtContract {
    function balanceOf(address) external view returns (uint256);
}

contract Rate {
   
    // Interest rate related
    using DataConvert for *;
    using SafeMath for *;
    using FilAddress for *;
    // using CBORDecoder for bytes;
    uint256 public maxOmFee=5; // 5% Maximum interest rate reserved space (SP operation and maintenance fees)
    uint256 public omCoefficient=5; // 5% Platform operation and maintenance reserve coefficient
    uint256 public riskCoefficient=5; // 5% Platform risk reserve system
    uint256 public rateChangePoint=90; // 90% Inflection point of interest rate changes in Chi Zi
    uint256 public loanRateCoefficient=10; // 10% Starting point loan interest rate coefficient
    uint256 public pointBeforeCoefficient=5; // 0.5 Growth coefficient before turning point
    uint256 public pointAfterCoefficient=45; // 4.5 Growth coefficient before turning point
    uint256 public balanceCoefficient=55; // 0.55 Balance coefficient (ensuring that the two formulas have the same interest rate when the utilization rate is at the inflection point coefficient)
    uint256 public lever = 2 * 100; // Maximum borrowing leverage
    uint256 public beneficiaryLever = 1.25 * 100; // Maximum borrowing leverage for beneficiaries
    uint256 public liquidationRiskControl=15; // 15% Clearing risk control coefficient
    uint256 public withdrawRiskControl=0; // 10% Withdrawal risk control coefficient
    uint256 public warnPeriod = 5; // Alarm cycle
    uint256 public votePeriod = 8; // Voting cycle
    address owner; // Administrators
    uint256 constant pointTenLength=10 ** 18; // Decimal point length
    uint256 constant yearDate = 365;
    uint256 constant zero = 0;
    uint256 constant one = 100; 
    uint256 constant ten = 10;
    uint256 constant ninetyFive=95;
    uint256 constant ninety=90;
    uint256 constant fifty=50;
    uint256 constant hundred = 100; 
    uint256 public avgYield; // Average daily production per T in the past 7 days
    uint256 public avgStake; // Average pledge per T in the past 7 days
    address public loanAddr; // Loan Contract Address
    address public stakeAddr; // Pledge Contract Address
    address public manageAddr; // Node management contract address
    address public pondAddr; // Node fund contract address

    struct SpNode {
      uint64  actorId;        // Node ID
      uint256 liquidationRate;  // Clearing rate
      uint256 nodeDebt;  // Node debt
   }

   // Log
   event Log(bool success,uint256 balance);
   event LogData(uint256 a,uint256 b,uint256 c,uint256 d,uint256 e);

   constructor(){

      owner = msg.sender;
      // Default pledge
      avgYield = 7600000000000000;
      avgStake = 6232600000000000000;
   }

   modifier checkAdmin(){
      require(owner == msg.sender, "you are not admin");
      _;
   }

   // Update administrator
   function modifyAdmin(address admin) public checkAdmin {
          owner = admin;
   }

   // Set loan contract address
   function setLoanContractAddr(address addr) public checkAdmin {
       loanAddr = addr;
   }

   // Set up a pledge contract address
   function setStakeContractAddr(address addr) public checkAdmin {
       stakeAddr = addr;
   }

   // Set node management contract address
   function setManageContractAddr(address addr) public checkAdmin {
       manageAddr = addr;
   }

   // Set node management contract address
   function setPondContractAddr(address addr) public checkAdmin {
       pondAddr = addr;
   }
   
   // Set associated contract address at once
   function setAllContractAddr(address[4] calldata addrList) public checkAdmin {
      loanAddr = addrList[0];
      stakeAddr = addrList[1];
      manageAddr = addrList[2];
      pondAddr = addrList[3];
   }

   // Set maximum interest rate reserve space (SP operation and maintenance fees)
   function setMaxOmFee(uint256 value) public checkAdmin{
         require(value < hundred , "maxOmFee must be less than 100");
         maxOmFee = value;
   }

   // Set platform operation and maintenance reserve coefficient
   function setOmCoefficient(uint256 value) public checkAdmin{
           require(value < hundred, "omCoefficient must be less than 100");
           omCoefficient = value;
   }

   // Set up a platform risk reserve system
   function setRiskCoefficient(uint256 value) public checkAdmin{
         require(value < hundred, "riskCoefficient must be less than 100");
         riskCoefficient = value;
   }

   // Set inflection points for changes in pool interest rates
   function setRateChangePoint(uint256 value) public checkAdmin{
        require(value < hundred, "rateChangePoint must be less than 100");
        rateChangePoint = value;
   }

   // Set the starting point loan interest rate coefficient
   function setLoanRateCoefficient(uint256 value) public checkAdmin{
         require(value < hundred, "loanRateCoefficient must be less than 100");
         loanRateCoefficient = value;
   }

   // Set growth coefficient before turning point
   function setPointBeforeCoefficient(uint256 value) public checkAdmin{
          pointBeforeCoefficient = value;
   }

   // Growth coefficient after setting inflection point
   function setPointAfterCoefficient(uint256 value) public checkAdmin{
           pointAfterCoefficient = value;
   }

   // Set balance coefficient
   function setBalanceCoefficient(uint256 value) public checkAdmin{
           balanceCoefficient = value;
   }

   // Set maximum borrowing leverage
   function setLever(uint256 value) public checkAdmin{
           lever = value;
   }

   // Set withdrawal risk control coefficient
   function setLiquidationRiskControl(uint256 value) public checkAdmin{
            require(value < hundred, "liquidationRiskControl must be less than 100");
            liquidationRiskControl = value;
   }

   // Set withdrawal risk control coefficient
   function setwithdrawRiskControl(uint256 value) public checkAdmin{
            require(value < hundred, "withdrawRiskControl must be less than 100");
            withdrawRiskControl = value;
   }

   // Set alarm cycle
   function setWarnPeriod(uint256 value) public checkAdmin{
            require(value > zero ,"warnPeriod cannot be zero");
            warnPeriod = value;
   }

   // Set voting cycle
   function setVotePeriod(uint256 value) public checkAdmin{
            require(value > zero ,"votePeriod cannot be zero");
            votePeriod = value;
   }
    
   // Set up pledge
   function setPledge(uint256 yield,uint256 stake) public checkAdmin {
         require(yield > zero || stake > zero,"pledge cannot be zero");

         if (yield != avgYield){
              avgYield = yield;
         }
         if(stake != avgStake){
             avgStake = stake;
         }

    }
   
   // Currency pool utilization rate
   function getPoolUseRate() public view  returns (uint256){
      // Obtain the balance of the smart contract
      uint256 contractBalance = pondAddr.balance;
      // Obtained from lending smart contracts
      uint256 debtBalance = StakeContract(loanAddr).totalSupply();

      if (debtBalance == 0 && contractBalance == 0) {
         return 0;
      }else {
         // Calculate fund utilization rate
         uint256 financeUseRate = debtBalance.mul(pointTenLength).div(debtBalance.add(contractBalance));

         // Return fund utilization rate
         return financeUseRate;
      }
    }

   
   // Current annualized yield rate
   function getProductionYearRate() public view returns(uint256){
        require(avgStake > zero ,"avgStake cannot be zero");
        require(avgYield < avgStake ,"avgYield cannot be greater than avgStake");

        return avgYield.mul(pointTenLength).div(avgStake).mul(yearDate);
   }

   // Maximum lending rate
   function getMaxLoanRate() public view returns (uint256){
       return getProductionYearRate().mul(ninetyFive).div(hundred);
   }

   
   // Lending rate
   function getLoanRate () public view returns(uint256){
        // Currency pool utilization rate
        uint256 useRate = getPoolUseRate();
        // Maximum lending rate
        uint256 maxRate = getMaxLoanRate();
        
        uint256 ninetyRate = ninety.mul(pointTenLength).div(hundred);
        
        uint256 loanRate;
        if(useRate >= ninetyRate){
           loanRate = maxRate.mul(useRate.sub(ninety.mul(pointTenLength).div(hundred)).mul(pointAfterCoefficient).div(ten).add(balanceCoefficient.mul(pointTenLength).div(hundred))).div(pointTenLength);
        }else{
           loanRate = maxRate.mul(pointTenLength.mul(loanRateCoefficient).div(hundred).add(useRate.mul(pointBeforeCoefficient).div(ten))).div(pointTenLength);
        }
       
        return loanRate;
   }

   // Deposit interest rate
   function getDepositRate() public view returns (uint256){
         // Currency pool utilization rate
         uint256 useRate = getPoolUseRate();
         // Lending rate
         uint256 loanRate = getLoanRate();
         // Fixed proportion
         uint256 fiftyRate = fifty.mul(pointTenLength).div(hundred);
         uint256 depositRate;
         if(useRate  >= fiftyRate){
              depositRate = useRate.mul(loanRate).mul(hundred.sub(omCoefficient.add(riskCoefficient)).mul(pointTenLength).div(hundred)).div(pointTenLength).div(pointTenLength);
         }else{
            depositRate = useRate.mul(loanRate).mul(hundred.sub(riskCoefficient).mul(pointTenLength).div(hundred)).div(pointTenLength).div(pointTenLength);
         }

         return depositRate;
   }

   // Node load rate
   function getNodeDebtRate(uint64 minerId) public view returns(uint256){
      // Total balance of nodes
      uint256 totalBalance = minerId.toIDAddress().balance;
      // Debt
      (bool success,uint256 totalDebt) = getTotalDebt(minerId.toIDAddress());
      require(success, "balanceOf contract call failed"); 
      require(totalBalance > totalDebt ,"totalDebt cannot be greater than availableBalance");
      return totalDebt.mul(pointTenLength).div(totalBalance);
   }

   // Maximum debt ratio
   function getMaxDebtRatio(uint64 minerId) public view returns(uint256){
      uint256 resLever = getLever(minerId);
      if(resLever == 0){
         return 0;
      }
      require(resLever > zero ,"lever cannot be zero");
      return (resLever.sub(one)).mul(pointTenLength).div(hundred).div(resLever).mul(hundred);

   }

   // Obtain maximum leverage
   function getLever(uint64 minerId) public view returns (uint256){
      // Node onboarding information
      ManageNodeContract miner = ManageNodeContract(manageAddr);
      ManageNode.ActorInfo memory af = miner.getMinersByActorId(minerId);
      if(af.mortgageType == 1){
         return lever;
      }else if(af.mortgageType == 2){
         return beneficiaryLever;
      }else {
         return 0;
      }
   }

   // Obtain onboarding node and clear interest rate
   function getSpNodeInfo() public view returns (SpNode[] memory) {
      // Node information
      ManageNodeContract miner = ManageNodeContract(manageAddr);
      ManageNode.ActorInfo[] memory af = miner.getMiners();
      SpNode[] memory sn = new SpNode[](af.length);

      for(uint i = 0;i < af.length;i++){
         uint256 paramlever;
         if(af[i].mortgageType == 1){
           paramlever = lever;
         }else if(af[i].mortgageType == 2){
            paramlever = beneficiaryLever;
         }
         
         // Maximum debt ratio of nodes
         uint256 maxDebtRatio = paramlever.sub(one).mul(pointTenLength).div(hundred).div(paramlever.div(hundred));
         // Clearing rate
         uint256 rate = maxDebtRatio.add(pointTenLength.mul(liquidationRiskControl).div(hundred));
         // Node liabilities
         (bool success,uint256 totalDebt) = getTotalDebt(af[i].actorId.toIDAddress());
         require(success, "balanceOf contract call failed");
         sn[i].actorId = af[i].actorId;
         sn[i].liquidationRate = rate;
         sn[i].nodeDebt = totalDebt;
      }

      return sn;
   }

   // Maximum Borrowable Limit
   function getMaxBorrowableAmount(uint64 minerId) public view returns(uint256){
      require(minerId > 0, "minerId data is error");  
      // Maximum leverage
      uint256 maxLever = getLever(minerId);
      if(maxLever == 0){
         return 0;
      }
      // Node account balance
      uint256 totalBalance = minerId.toIDAddress().balance;
      // Total debt
      (bool success,uint256 totalDebt) = getTotalDebt(minerId.toIDAddress());
      require(success, "balanceOf contract call failed");  
      
      if (totalDebt >= totalBalance){
         return 0;
      }
      
      if (totalDebt >= totalBalance.sub(totalDebt).mul(maxLever.sub(one)).div(hundred)){
          return 0;
      } 

      uint256 amount = totalBalance.sub(totalDebt).mul(maxLever.sub(one)).div(hundred).sub(totalDebt);
      return amount;
   }

   // Obtain relevant parameters of interest rate contracts
   function getRateContractParam(uint256 target) public view returns (uint256,uint256,uint256,uint256){
       require(target > 0, "target data is error");  
       return (getMaxDebtRatio(uint64(target)),getLiquidationRate(uint64(target)),warnPeriod,votePeriod);
   }

   // Clearing rate
   function getLiquidationRate(uint64 minerId) public view returns(uint256){
      require(minerId > 0, "minerId data is error");
      require(liquidationRiskControl > zero ,"liquidationRiskControl cannot be zero");
      uint256 liquidationRate;
      liquidationRate = getMaxDebtRatio(minerId).add(pointTenLength.mul(liquidationRiskControl).div(hundred));
      return liquidationRate;
   }

   // Node available balance
   function getAvailableBalance(CommonTypes.FilActorId minerId) public returns (uint256){
      CommonTypes.BigInt memory ba = MinerAPI.getAvailableBalance(minerId);
      return ba.val.BytesToUint();
   }

   // Debt
   function getTotalDebt(address addr) public view returns (bool,uint256){
      if(addr == address(0) || loanAddr == address(0)){
         return (false,zero);
      }

      uint256 addrDebt = DebtContract(loanAddr).balanceOf(addr);

      return (true,addrDebt);
   }
    
   // Withdrawable limit
   function withdrawalLimit(uint64 minerId) public returns (uint256) {
       require(minerId > 0, "minerId data is error");   
       // Node available balance
       CommonTypes.FilActorId target = CommonTypes.FilActorId.wrap(minerId);
       uint256 availableBalance = getAvailableBalance(target);

       return withdrawalLimitView(minerId,availableBalance);
   }

   // Withdrawable limit
   function withdrawalLimitView(uint64 minerId,uint256 availableBalance) public view returns (uint256){
       require(availableBalance > 0, "availableBalance cannot be zero"); 
       require(minerId > 0, "minerId data is error");   
       // Debt
       (bool success,uint256 totalDebt) = getTotalDebt(minerId.toIDAddress());
       require(success, "balanceOf contract call failed");

       // Actual available balance of nodes
       if(totalDebt >= availableBalance){
           availableBalance = 0;
       }else{
           availableBalance = availableBalance.sub(totalDebt);
       }
       
       // Total amount
       uint256 totalBalance = minerId.toIDAddress().balance;
       // Withdrawable threshold
       uint256 wt = totalDebt.mul(pointTenLength).div(getMaxDebtRatio(minerId).add(withdrawRiskControl.mul(pointTenLength).div(hundred)));
       // Withdrawable limit
       uint256 wl;
       if (wt >= totalBalance){
          wt = 0;
       }else{
          wl = totalBalance.sub(wt);
       } 

       // If the withdrawal limit is greater than the available balance, return the available balance; otherwise, return the withdrawal limit
       if(wl > availableBalance){
           return availableBalance;
       }else{
           return wl;
       } 
   }
}


