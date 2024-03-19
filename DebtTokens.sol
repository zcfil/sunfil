// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./math/SafeMath.sol";
import  {InterestRateFormula} from "./InterestRateFormula.sol";

interface IERC20 {
    function name() external view returns (string memory);
    function symbol() external view returns (string memory);
    function decimals() external view returns (uint8);
    function totalSupply() external view returns (uint);
    function balanceOf(address owner) external view returns (uint);
}


interface RateContract {
    function getLoanRate() external view returns (uint256);
    function getPoolUseRate() external view  returns (uint256);
    function omCoefficient() external view  returns (uint256); // Platform operation and maintenance reserve coefficient
    function riskCoefficient() external view  returns (uint256); // Platform risk reserve coefficient
}

interface StakeContract {
    function dealScaleFactor() external;
}

contract DebtTokens is IERC20 {
    using SafeMath for uint256;
    // Define the Response event and output the result success and data returned by the call
    event Response(bool success, bytes data);

    // Lending related
    address admin; // Admin user
    uint256 minDebts; // Minimum debit and credit value
    address public pondContractAddr; // Node Contract Address
    address public rateContractAddr; // Interest rate contract address
    address public stakeContractAddr; // Loan Contract Address
    address public opNodeContractAddr; // Node operation contract address

    // Loan token related
    string public constant name = "Debt FileCoin"; // Token Name
    string public constant symbol = "DebtFIL"; // Token symbols
    uint8 public constant decimals = 18; // Number of tokens
    uint256 public totalScaleFactor; // Total supply of token issuance
    mapping(address => uint256) public scaleFactor; // Scaling factor for the current issuance quantity of corresponding address tokens
    mapping(address => uint256) public addrBalance; // Actual loan amount corresponding to the address

    // User Pledge Information
    uint256 baseRate = 10**18;       // Interest rate basis
    uint256 yearSecond = 31536000;   // Seconds in a year

    uint256 public liquidityRate;            // Liquidity rate
    uint256 public liquidityRateTimeStamp;   // Liquidity rate corresponding timestamp
    uint256 public testTimeStamp;   // Liquidity rate corresponding timestamp

    uint256 public standardIndexDebt = 10**18;     // Standardized interest rate index
    uint256 public riskProfitLimitRate = 0.5*10**18;     // Platform risk profit margin percentage

    // Initialize partial information
    constructor() {
        admin = msg.sender; // The admin user is assigning the corresponding smart contract address
        minDebts = 1 ether;
        liquidityRateTimeStamp = block.timestamp;
        testTimeStamp = liquidityRateTimeStamp;
    }

    // Set associated node contracts
    function setPondContractAddr(address _address) public onlyAdmin {
        pondContractAddr = _address;
    }

    // Set associated interest rate contracts
    function setRateContractAddr(address _address) public onlyAdmin {
        rateContractAddr = _address;
    }

    // Set associated interest rate contracts
    function setStakeContractAddr(address _address) public onlyAdmin {
        stakeContractAddr = _address;
    }

    // Set associated node operation contracts
    function setOPNodeContractAddr(address _address) public onlyAdmin {
        opNodeContractAddr = _address;
    }

    // Set associated contract address at once
    function setAllContractAddr(address[4] calldata addrList) public onlyAdmin {
        pondContractAddr = addrList[0];
        rateContractAddr = addrList[1];
        stakeContractAddr = addrList[2];
        opNodeContractAddr = addrList[3];
    }

    // Judging whether it is an admin user method
    modifier onlyAdmin() {
        require(msg.sender == admin, "Only admin can call this function.");
        _;
    }

    // Replace with a new admin
    function updateAdmin(address _admin) public onlyAdmin {
        admin = _admin;
    }

    // Set platform risk profit margin percentage
    function updateRiskProfitLimitRate(uint256 limitRate) public onlyAdmin {
        riskProfitLimitRate = limitRate;
    }

    // Determine if it is a loan and node contract call
    modifier onlyStakeAndMiner() {
        require(stakeContractAddr != address(0) && pondContractAddr != address(0) && admin != address(0),
            "Please set the associated contract address first.");
        require(msg.sender == stakeContractAddr || msg.sender == pondContractAddr || msg.sender == admin || msg.sender == opNodeContractAddr,
            "Only stake or pond contract can call this function.");
        _;
    }


    // Obtain the corresponding user balance
    function balanceOf(address owner) override external view returns (uint256){
        // Get the current timestamp
        uint256 currentTime = block.timestamp;
        // Obtain time difference
        uint256 timeDiff = 0;
        if (currentTime > liquidityRateTimeStamp) {
            timeDiff = currentTime.sub(liquidityRateTimeStamp);
        }
        // Calculate the standardized interest calculation index for the corresponding time point
        uint256 tempStandardIndex = InterestRateFormula.calculateStandardIndexDebt(timeDiff,liquidityRate,standardIndexDebt);
        // Calculate account balance
        uint256 userBalance = InterestRateFormula.calculateUserBalance(tempStandardIndex,scaleFactor[owner]);
        return userBalance;
    }


    // Obtain the total supply of tokens
    function totalSupply() override public view returns (uint){
        uint256 currentTime = block.timestamp;
        uint256 timeDiff = 0;
        if (currentTime > liquidityRateTimeStamp) {
            timeDiff = currentTime.sub(liquidityRateTimeStamp);
        }
        // Calculate the standardized interest calculation index for the corresponding time point
        uint256 tempStandardIndex = InterestRateFormula.calculateStandardIndexDebt(timeDiff,liquidityRate,standardIndexDebt);
        // Calculate account balance
        uint256 totalBalance = InterestRateFormula.calculateUserBalance(tempStandardIndex,totalScaleFactor);
        return totalBalance;
    }

    // Obtain total amount
    function getTotalFilBalance() public view returns (uint256){
        // Obtain the total amount of pledge
        uint256 debtBalance = totalSupply();

        if (pondContractAddr == address(0)) {
            return 0 + debtBalance;
        }
        return pondContractAddr.balance + debtBalance;
    }


    // Perform debit and credit bookkeeping
    function addDebts(uint256 amount, address owner) public onlyStakeAndMiner {
        require(amount >= minDebts, "Invalid borrow amount.");
        // Calculate the standardized interest calculation index for the corresponding time point
        dealScaleFactorPrivate();
        // Calculate the scaling factor for the corresponding borrowing and lending
        uint256 scaleFactorNum = InterestRateFormula.calculateScaleFactorAdd(standardIndexDebt,amount,scaleFactor[owner]);

        /*Casting tokens for borrowers*/
        // Record the scaling factor of the user
        scaleFactor[owner] = scaleFactorNum;
        // Record the actual amount of the user
        addrBalance[owner] = addrBalance[owner].add(amount);
        // Count all scaling factors
        totalScaleFactor = InterestRateFormula.calculateScaleFactorAdd(standardIndexDebt,amount,totalScaleFactor);

        // Update loan contract data
        updateStakeLiquidityRate();

        // Update standardized interest calculation index
        dealScaleFactorPrivate();
    }

    // Repayment of debit and credit bookkeeping
    function repayDebts(uint256 amount,address debtAddress, uint256 isTotal) public onlyStakeAndMiner returns(uint256,uint256,uint256) {
        require(amount > 0, "Invalid pay back.");

        // Obtain fund utilization rate
        uint256 financeUseRate = RateContract(rateContractAddr).getPoolUseRate();

        // Calculate interest rate index
        dealScaleFactorPrivate();

        // Calculate account balance (needs to be calculated first, scaling factor will be changed later)
        uint256 userBalance = InterestRateFormula.calculateUserBalance(standardIndexDebt,scaleFactor[debtAddress]);

        if (isTotal != 0) {
            // If there are all identifiers, assign the account balance to the corresponding limit
            amount = userBalance;
            // Remove the scaling factor of the corresponding address from the total pledge factor
            totalScaleFactor = totalScaleFactor.sub(scaleFactor[debtAddress]);
            // Setting the scaling factor for empty users
            scaleFactor[debtAddress] = 0;
        }else {
            // Calculate scaling factor - subtract
            uint256 scaleFactorNum = InterestRateFormula.calculateScaleFactorSub(standardIndexDebt,amount,scaleFactor[debtAddress]);
            // Remove the scaling factor of the corresponding address from the total pledge factor
            totalScaleFactor = InterestRateFormula.calculateScaleFactorSub(standardIndexDebt,amount,totalScaleFactor);
            /*Destroy the borrower's token*/
            // Update user's scaling factor
            scaleFactor[debtAddress] = scaleFactorNum;
        }

        // Calculate the repayment amount and separate the principal and interest (priority given to interest repayment in cases of smaller repayment amounts)
        // Calculate the corresponding interest as
        uint256 addrInterest = userBalance.sub(addrBalance[debtAddress]);

        // The repayment amount needs to be deducted from the calculated interest
        uint256 amountRate;
        uint256 amountLeave;

        // Separate the principal and interest, and prioritize the repayment of interest
        if (amount > addrInterest){
            amountRate = addrInterest;
            amountLeave = amount.sub(addrInterest);
            if (scaleFactor[debtAddress] == 0){ //If the scaling factor is left blank, it is considered to have repaid the debt and cleared the true value of the record
                addrBalance[debtAddress] = 0;
            }else{
                // Deducting true values
                if (amountLeave > addrBalance[debtAddress]) {
                    addrBalance[debtAddress] = 0;
                }else{
                    addrBalance[debtAddress] = addrBalance[debtAddress].sub(amountLeave);
                }
            }
        }else {
            amountRate = addrInterest;
            amountLeave = 0;
        }

        // Perform separate profit sharing calculations
        uint256 userRate;
        uint256 plateOperationNum;
        uint256 plateRiskNum;

        uint256 plateOperationStoreRate = RateContract(rateContractAddr).omCoefficient();
        plateOperationStoreRate = plateOperationStoreRate.mul(baseRate).div(100);

        // Statistics on the number of coin transfers to the platform's operation and maintenance reserve system address
        plateOperationNum = amountRate.mul(plateOperationStoreRate).div(baseRate);
        userRate = plateOperationNum;

        // Statistics on the number of currency transfers to the platform's risk reserve system address
        if (financeUseRate >= riskProfitLimitRate) {
            uint256 plateRiskStoreRate = RateContract(rateContractAddr).riskCoefficient();
            plateRiskStoreRate = plateRiskStoreRate.mul(baseRate).div(100);
            plateRiskNum = amountRate.mul(plateRiskStoreRate).div(baseRate);
            userRate = userRate.add(plateRiskNum);
        }

        // Update loan contract data
        updateStakeLiquidityRate();

        // Update standardized interest calculation index
        dealScaleFactorPrivate();

        return (amountLeave.add(amountRate.sub(userRate)),plateOperationNum,plateRiskNum);
    }

    // Calculate and obtain the standardized interest calculation index for the corresponding time point
    function dealScaleFactorPrivate() private {
        // Obtaining loan interest rates from interest rate contracts
        uint256 loanRate = RateContract(rateContractAddr).getLoanRate();

        uint256 currentTime = block.timestamp;
        uint256 timeDiff = 0;
        if (currentTime >= liquidityRateTimeStamp) {
            timeDiff = currentTime-liquidityRateTimeStamp;
        }

        // Record new timestamps
        liquidityRateTimeStamp = currentTime;
        // Calculate the standardized interest calculation index for the corresponding time point
        standardIndexDebt = InterestRateFormula.calculateStandardIndexDebt(timeDiff,liquidityRate,standardIndexDebt);
        // Assign liquidity interest rate
        liquidityRate = loanRate;
    }

    // Calculate and obtain the standardized interest calculation index for the corresponding time point
    function dealScaleFactor() public onlyStakeAndMiner {
        dealScaleFactorPrivate();
    }

    // Update the liquidity interest index of the pledge contract after the loan settlement is completed
    function updateStakeLiquidityRate() private  {
        StakeContract(stakeContractAddr).dealScaleFactor();
    }
}
