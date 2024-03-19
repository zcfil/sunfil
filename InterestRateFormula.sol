// SPDX-License-Identifier: MIT
pragma solidity >=0.4.16 <0.9.0;

import "./math/SafeMath.sol";

library InterestRateFormula {

    using SafeMath for uint256;

    uint256 constant baseRate = 10**18;
    uint256 constant yearSecond = 31536000;

    // Calculate liquidity interest rate
    function calculateLiquidityRate(uint256 financeUseRate,uint256 totalLoanInterestRate) external pure returns(uint256) {
        // Calculate the current liquidity rate
        uint256 currentLiquidityRate = financeUseRate.mul(totalLoanInterestRate).div(baseRate);
        return currentLiquidityRate;
    }
    
    // Calculate scaling factor - add
    function calculateScaleFactorAdd(uint256 standardInterestIndex,uint256 userBalance,uint256 userScaleFactor) external pure returns(uint256) {
        userScaleFactor = userScaleFactor.add(userBalance.mul(baseRate).mul(10).add(5).div(standardInterestIndex).div(10)) ;
        return userScaleFactor;
    }
    
    // Calculate scaling factor - subtract
    function calculateScaleFactorSub(uint256 standardInterestIndex,uint256 userBalance,uint256 userScaleFactor) external pure returns(uint256) {
        userScaleFactor = userScaleFactor.sub(userBalance.mul(baseRate).mul(10).add(5).div(standardInterestIndex).div(10)) ;
        return userScaleFactor;
    }

    // Calculate the current user's account balance
    function calculateUserBalance(uint256 standardInterestIndex,uint256 userScaleFactor) external pure returns(uint256) {
        uint256 userBalance = userScaleFactor.mul(standardInterestIndex).add(5 * baseRate.div(10)).div(baseRate);
        return userBalance;
    }


    /*Calculation Formula Method for Pledge Part*/
    // Calculate standardized interest rate index
    function calculateStandardIndexStake(uint256 timeDifference,uint256 currentLiquidityRate,uint256 standardInterestIndex) external pure returns(uint256) {
        // Calculate the proportion of time difference in one year
        uint256 timeRateInYear = timeDifference.mul(baseRate).mul(10).div(yearSecond).add(5).div(10);

        // Set the first standardized interest calculation index to 1 (t=0)
        if (standardInterestIndex == 0) {
            standardInterestIndex = baseRate;
        }

        // Calculate standardized interest rate index
        standardInterestIndex = currentLiquidityRate.mul(timeRateInYear).div(baseRate).add(baseRate).mul(standardInterestIndex).div(baseRate);
        return standardInterestIndex;
    }


    /* Calculation Formula Method for Loan and Loan Portion */

    // Calculate standardized interest rate index
    function calculateStandardIndexDebt(uint256 timeDifference,uint256 currentLiquidityRate,uint256 standardInterestIndex) external pure returns(uint256) {
        // Calculate the average liquidity rate per second for one year
        uint256 secondLiquidityRate = baseRate.add(currentLiquidityRate.mul(10).div(yearSecond).add(5).div(10));

        // Set the first standardized interest calculation index to 1 (t=0)
        if (standardInterestIndex == 0) {
            standardInterestIndex = baseRate;
        }

        // Calculate standardized interest rate index
        standardInterestIndex = calculateIndexByCut(timeDifference,secondLiquidityRate).mul(standardInterestIndex).div(baseRate);
        return standardInterestIndex;
    }

    // By dividing the index numbers, operations corresponding to larger data indices can be completed
    function calculateIndexByCut(uint256 index,uint256 origin) private pure returns (uint256) {
        uint256 baseIndex = 1000;       // The basic index of operations

        uint256 result = baseRate;       // Calculated total value
        uint256 lastResult;              // The value of calculating remainder

        uint256 indexLast =  index.mod(baseIndex);
        uint256 times = index.div(baseIndex);

        uint256 resultBase = result.mul(calculateRateIndex(baseIndex,origin)).div(baseRate);

        if (times > 0){
            for (uint256 i= 0; i < times; i++){
                result = result.mul(resultBase).div(baseRate);
            }
        }

        lastResult = calculateRateIndex(indexLast,origin);
        result = result.mul(lastResult).div(baseRate);
        
        return result;
    }

    // Using loops for exponential calculation
    function calculateRateIndex(uint256 index,uint256 origin) private pure returns (uint256) {
        uint256 result = baseRate;
        for (uint256 i = 0; i < index; i++) {
            result = result.mul(origin).div(baseRate);
        }
        return result;
    }

}