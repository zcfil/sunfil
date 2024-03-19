// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.0;

library DataConvert {
    // Uint256 to String
    function Uint256ToString(uint256 value) internal pure returns (string memory) {
        if (value == 0) {
            return "0";
        }
        uint256 temp = value;
        uint256 digits;
        while (temp != 0) {
            digits++;
            temp /= 10;
        }
        bytes memory buffer = new bytes(digits);
        while (value != 0) {
            digits -= 1;
            buffer[digits] = bytes1(uint8(48 + uint256(value % 10)));
            value /= 10;
        }
        return string(buffer);
    }

    // String character concatenation
    function StrAppend(string memory str0, string memory str1) internal pure returns (string memory) {

        bytes memory bytesA = bytes(str0);
        bytes memory bytesB = bytes(str1);
        string memory concatenatedString = new string(bytesA.length + bytesB.length);
        bytes memory bytesConcatenated = bytes(concatenatedString);

        uint256 k = 0;
        for (uint256 i = 0; i < bytesA.length; i++) {
            bytesConcatenated[k++] = bytesA[i];
        }
        for (uint256 i = 0; i < bytesB.length; i++) {
            bytesConcatenated[k++] = bytesB[i];
        }

        return string(bytesConcatenated);
    }
    
    // String to Uint256
    function StringToUint256(string memory str) internal pure returns (uint256) {
        uint256 result = 0;
        uint256 i = 0;

        if (bytes(str)[0] == '-') {
            require(bytes(str).length > 1, "Invalid input");
            i = 1; // Ignore the '-' sign for negative numbers
        }

        for (; i < bytes(str).length; i++) {
            uint256 digit = uint256(uint8(bytes(str)[i])) - 48;
            require(digit <= 9, "Invalid digit");

            result = result * 10 + digit;
        }

        if (bytes(str)[0] == '-') {
            result = 0 - result; // Convert back to negative if the number is negative
        }

        return result;
    }

    // Bytes to Uint
    function BytesToUint(bytes memory data) internal pure returns (uint256) {
        uint256 number;
        for (uint256 i = 0; i < data.length; i++) {
            number = number + uint256(uint8(data[i]))*(2**(8*(data.length-(i+1))));
        }
        return number;
    }

    // Append string
    function appendString(string memory _str1, string memory _str2) internal pure returns (string memory) {
        string memory result = string(abi.encodePacked(_str1, _str2));
        return result;
    }

    // Obtain a timestamp after a certain day
    function getDayTimestamp(uint256 day,uint256 currentTimestamp) internal pure  returns (uint256) {
        uint256 twoDaysInSec = day * 1 days; 
        uint256 twoDaysLaterTimestamp = currentTimestamp + twoDaysInSec;
        return twoDaysLaterTimestamp;
    }
	
	// String concatenation
    function concatenateCharacters(string memory str, string memory character) internal pure returns (string memory) {
        bytes memory strBytes = bytes(str);
        bytes memory charBytes = bytes(character);
        bytes memory result = new bytes(strBytes.length + charBytes.length);

        uint256 index = 0;
        for (uint256 i = 0; i < strBytes.length; i++) {
            result[index++] = strBytes[i];
        }

        for (uint256 i = 0; i < charBytes.length; i++) {
            result[index++] = charBytes[i];
        }

        return string(result);
    }

    // String length
    function getStringLength(string memory str) internal pure returns (uint256) {
        bytes memory encoded = bytes(str);
        return encoded.length;
    }

    // Uint256 custom increase in length, followed by 0
    function complementLength(uint256 str,uint256 len) internal pure returns (uint256){
           
           if(getStringLength(Uint256ToString(str)) >= len){
                return str;
           }else{
                string memory strData;
                uint256 strLen = len - getStringLength(Uint256ToString(str));
                
                for (uint256 i=0;i<strLen;i++){

                        if(getStringLength(strData) == 0){
                            strData = concatenateCharacters(Uint256ToString(str),"0");
                        }else{
                            strData = concatenateCharacters(strData,"0");
                        }
                }

                if (strLen <= 0 || str <= 0){
                        return str;
                }else{
                        return StringToUint256(strData);
                }  
           }
    }
}