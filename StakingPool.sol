// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.13;

import "./math/SafeMath.sol";
import  {InterestRateFormula} from "./InterestRateFormula.sol";
import "./models/stake.sol";


interface IERC20 {
    event Transfer(address indexed from ,address indexed to ,uint256 amount);

    function name() external view returns (string memory);
    function symbol() external view returns (string memory);
    function decimals() external view returns (uint8);
    function totalSupply() external view returns (uint);
    function balanceOf(address owner) external view returns (uint);
    function transfer(address to, uint amount) external returns(bool);
}

interface RateContract {
    function getDepositRate() external view returns (uint256);
}

interface DebtContract {
    function dealScaleFactor() external;
}

contract StakingPool is IERC20 {
    using SafeMath for uint256;

    // Pledge related
    address admin; // Admin user
    uint256 public minStakes; // Minimum pledge value
    address public pondContractAddr; // Node contract address (funds are gathered on the node address)
    address public rateContractAddr; // Interest rate contract address
    address public debtContractAddr; // Pledge Contract Address

    // Pledge token related
    string public constant name = "Sun FileCoin"; // Token Name
    string public constant symbol = "SunFIL"; // Token symbols
    uint8 public constant decimals = 18; // Number of tokens
    uint256 public totalScaleFactor; // Total supply of token issuance
    mapping(address => uint256) public scaleFactor; // Scaling factor for the current issuance quantity of corresponding address tokens

    address[] stakeAddressStr; // Record the corresponding pledged user address

    // User Pledge Information
    uint256 baseRate = 10**18;       // Interest rate basis
    uint256 yearSecond = 31536000;   // Seconds in a year

    // System pledged liquidity interest rate information
    uint256 public liquidityRate;            // Liquidity rate
    uint256 public liquidityRateTimeStamp;   // Liquidity rate corresponding timestamp
    uint256 public testTimeStamp;   // Liquidity rate corresponding timestamp

    uint256 public standardIndexStakes = 10**18;     // Initial standardized interest rate index

    // Initialize partial information
    constructor() {
        admin = msg.sender; // The admin user is assigning the corresponding smart contract address
        minStakes = 1 ether; // The minimum amount of pledge, in units of wei, here is 1 coin
        liquidityRateTimeStamp = block.timestamp;
        testTimeStamp = liquidityRateTimeStamp;
        
        pondContractAddr = 0xFC3e61D0a36bFb4d437E6bc7CBA9c0F7CAd661CA;
        rateContractAddr = 0x17268dc45a8953C77F10B12Ca18669e484d32a0C;
        debtContractAddr = 0xA663256eb3b09DBEa8b205D603170751232Ca6C0;
    }

    // Determine if it is an admin user method
    modifier onlyAdmin() {
        require(msg.sender == admin, "Only admin can call this function.");
        _;
    }

    // Replace with a new admin
    function updateAdmin(address _admin) public onlyAdmin {
        admin = _admin;
    }

    // Set the associated node contract address
    function setMinersContractAddr(address _address) public onlyAdmin {
        pondContractAddr = _address;
    }

    // Set associated interest rate contract address
    function setRateContractAddr(address _address) public onlyAdmin {
        rateContractAddr = _address;
    }

    // Set associated lending contract addresses
    function setDebtContractAddr(address _address) public onlyAdmin {
        debtContractAddr = _address;
    }

    // Set associated contract address at once
    function setAllContractAddr(address[3] calldata addrList) public onlyAdmin {
         pondContractAddr = addrList[0];
         rateContractAddr = addrList[1];
         debtContractAddr = addrList[2];
    }
    
    // Determine if it is a loan and node contract call
    modifier onlyDebtAndMiner() {
        require(debtContractAddr != address(0) && pondContractAddr != address(0) && admin != address(0), 
        "Please set the associated contract address first.");
        require(msg.sender == debtContractAddr || msg.sender == pondContractAddr || msg.sender == admin, 
        "Only debt or pond contract can call this function.");
        _;
    }

    // Obtain the balance of node smart contracts
    function getContractAmount() public view returns (uint256){
        return pondContractAddr.balance;
    }

    // Token transfer
    function transfer(address to, uint amount) external returns(bool){
        _transfer(msg.sender, to, amount);
        return true;
    }

    function _transfer(address from, address to,uint amount) private {
        // Calculate interest rate index
        dealScaleFactorPrivate();
        // Calculate scaling factor - subtract
        uint256 scaleFactorNum = InterestRateFormula.calculateScaleFactorSub(standardIndexStakes,amount,scaleFactor[from]);

        scaleFactor[from] = scaleFactorNum;
        scaleFactor[to] = InterestRateFormula.calculateScaleFactorAdd(standardIndexStakes,amount,scaleFactor[to]);

        // Record user address information
        addStakeStrElement(to);

        emit Transfer(from ,to ,amount);
    }

    // Obtain the corresponding user balance
    function balanceOf(address owner) override public view returns (uint256){
        // Get the current timestamp
        uint256 currentTime = block.timestamp;
        // Obtain time difference
        uint256 timeDiff = 0;
        if (currentTime > liquidityRateTimeStamp) {
            timeDiff = currentTime.sub(liquidityRateTimeStamp);
        }
        // Calculate the standardized interest calculation index for the corresponding time point
        uint256 tempStandardIndex = InterestRateFormula.calculateStandardIndexStake(timeDiff,liquidityRate,standardIndexStakes);
        // Calculate account balance
        uint256 userBalance = InterestRateFormula.calculateUserBalance(tempStandardIndex,scaleFactor[owner]);
        return userBalance;
    }

    // Obtain the total supply of tokens
    function totalSupply() override public view returns (uint256){
        // Get the current timestamp
        uint256 currentTime = block.timestamp;
        // Obtain time difference
        uint256 timeDiff = 0;
        if (currentTime > liquidityRateTimeStamp) {
            timeDiff = currentTime.sub(liquidityRateTimeStamp);
        }
        // Calculate the standardized interest calculation index for the corresponding time point
        uint256 tempStandardIndex = InterestRateFormula.calculateStandardIndexStake(timeDiff,liquidityRate,standardIndexStakes);
        // Calculate account balance
        uint256 totalBalance = InterestRateFormula.calculateUserBalance(tempStandardIndex,totalScaleFactor);
        return totalBalance;
    }

    // Add pledge
    function addStakes() external payable {
        // Pre judgment
        require(msg.value > 0, "Invalid pledge amount.");
        // Transfer tokens to node smart contracts
        (bool success, ) = pondContractAddr.call{value: msg.value}(
            abi.encodeWithSignature("addressToContract()")
        );
        require(success, "External call failed");
        // Record user address information
        addStakeStrElement(msg.sender);
        // Casting tokens for pledgers
        mint(msg.sender,msg.value);
    }

    // Extract pledge
    function withdrawStakes(uint256 amount,bool isTotal) external {
        // Pre judgment
        require(amount > 0, "Invalid withdrawal.");

        // Get the current timestamp
        uint256 currentTime = block.timestamp;
        // Obtain time difference
        uint256 timeDiff = 0;
        if (currentTime > liquidityRateTimeStamp) {
            timeDiff = currentTime.sub(liquidityRateTimeStamp);
        }
        // Calculate the standardized interest calculation index for the corresponding time point
        uint256 tempStandardIndex = InterestRateFormula.calculateStandardIndexStake(timeDiff,liquidityRate,standardIndexStakes);
        // Calculate account balance
        uint256 userBalance = InterestRateFormula.calculateUserBalance(tempStandardIndex,totalScaleFactor);

        if (isTotal) {
            amount = userBalance;
        }else {
            // Compare the calculated value of the user's pledged coins with the quantity of extracted pledged coins
            require(userBalance >= amount, "Should have enough Stakes to withdraw.");
        }

        // Retrieve coins from node smart contracts
        (bool success, ) = pondContractAddr.call(
            abi.encodeWithSignature("contractToAddress(uint256,address)", amount, msg.sender)
        );
        require(success, "External call failed");

        // Destroy the pledgor's token
        burn(amount,isTotal);
    }

    // Casting tokens
    function mint(address to ,uint256 amount) private  {
        // Calculate interest rate index
        dealScaleFactorPrivate();
        // Calculate scaling factor
        uint256 scaleFactorNum = InterestRateFormula.calculateScaleFactorAdd(standardIndexStakes,amount,scaleFactor[to]);
        // Count all scaling factors
        totalScaleFactor = InterestRateFormula.calculateScaleFactorAdd(standardIndexStakes,amount,totalScaleFactor);
        // Record the scaling factor of the user
        scaleFactor[to] = scaleFactorNum;
        // Update loan contract data
        updateDebtLiquidityRate();
        // Update calculation of interest rate index
        dealScaleFactorPrivate();
    }

    // Calculate and obtain the standardized interest calculation index for the corresponding time point
    function dealScaleFactorPrivate() private {
        // Get the current timestamp
        uint256 currentTime = block.timestamp;
        // Obtain time difference
        uint256 timeDiff = 0;
        if (currentTime >= liquidityRateTimeStamp) {
            timeDiff = currentTime-liquidityRateTimeStamp;
        }
        // Record new timestamps
        liquidityRateTimeStamp = currentTime;
        // Calculate the standardized interest calculation index for the corresponding time point
        standardIndexStakes = InterestRateFormula.calculateStandardIndexStake(timeDiff,liquidityRate,standardIndexStakes);

        // Obtaining pledged interest rates from interest rate contracts
        uint256 stakeRate = RateContract(rateContractAddr).getDepositRate();
        // Assign a new liquidity interest rate
        liquidityRate = stakeRate;
    }

    // Calculate and obtain the standardized interest calculation index for the corresponding time point
    function dealScaleFactor() public onlyDebtAndMiner  {
        dealScaleFactorPrivate();
    }

    // Destroy tokens
    function burn(uint256 amount,bool isTotal) private {
        address from = msg.sender;
        // Calculate interest rate index
        dealScaleFactorPrivate();
        if (isTotal){
            // Update the overall scaling factor
            totalScaleFactor = totalScaleFactor.sub(scaleFactor[from]);
            // Remove user records
            deleteStakeStrElement(from);
            // Update user's scaling factor
            scaleFactor[from] = 0;
        }else {
            // Calculate scaling factor - subtract
            uint256 scaleFactorNum = InterestRateFormula.calculateScaleFactorSub(standardIndexStakes,amount,scaleFactor[from]);
            // Update the overall scaling factor
            totalScaleFactor = InterestRateFormula.calculateScaleFactorSub(standardIndexStakes,amount,totalScaleFactor);
            // Update user's scaling factor
            scaleFactor[from] = scaleFactorNum;
        }
        // Update loan contract data
        updateDebtLiquidityRate();
        // Update calculation of interest rate index
        dealScaleFactorPrivate();
    }

    // Update the loan interest rate after completing the pledge settlement
    function updateDebtLiquidityRate() private  {
        // Modify the liquidity interest calculation index of lending smart contracts
        DebtContract(debtContractAddr).dealScaleFactor();
    }

    // Add specific addresses to an array
    function addStakeStrElement(address addr) private {
        bool isExist = false;
        for (uint256 i = 0;i < stakeAddressStr.length;i++){
            if (addr == stakeAddressStr[i]){
                isExist = true;
                break;
            }
        }
        if (!isExist) {
            stakeAddressStr.push(addr);
        }
    }

    // Remove specific addresses from the array
    function deleteStakeStrElement(address addr) private {
        for (uint256 i = 0;i < stakeAddressStr.length;i++){
            if (addr == stakeAddressStr[i]){
                stakeAddressStr[i] = stakeAddressStr[stakeAddressStr.length - 1];
                stakeAddressStr.pop();
                break;
            }
        }
    }

    // Return to the list of pledged users
    function getStakeAddressList() external view returns(StakeInfo[] memory)  {
        StakeInfo[] memory stakeInfoList = new StakeInfo[](stakeAddressStr.length);
        for (uint256 i = 0;i < stakeAddressStr.length;i++){
            stakeInfoList[i].stakeAddr = stakeAddressStr[i];
            stakeInfoList[i].stakeBalance = balanceOf(stakeAddressStr[i]);
        }
        return stakeInfoList;
    }

    // Return the number of pledged users
    function getStakeAddressNum() public view returns(uint256)  {
        return stakeAddressStr.length;
    }

}