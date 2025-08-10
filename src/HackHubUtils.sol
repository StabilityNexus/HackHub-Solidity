// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
 
library HackHubUtils {
    error InvalidIndexRange();
    error EndIndexOutOfBounds();
     
    function getSlice(address[] storage source, uint256 startIndex, uint256 endIndex) 
        internal view returns (address[] memory) {
        if (startIndex > endIndex) revert InvalidIndexRange();
        if (endIndex >= source.length) revert EndIndexOutOfBounds();
        
        uint256 length = endIndex - startIndex + 1;
        address[] memory result = new address[](length);
        
        unchecked {
            for (uint256 i = 0; i < length; ++i) {
                result[i] = source[startIndex + i];
            }
        }
        return result;
    }
     
    function removeFromArray(address[] storage arr, address item) internal {
        uint256 length = arr.length;
        for (uint256 i = 0; i < length;) {
            if (arr[i] == item) {
                arr[i] = arr[length - 1];
                arr.pop();
                return;
            }
            unchecked { ++i; }
        }
    }
    
    function moveItem(address[] storage from, address[] storage to, address item) internal {
        to.push(item);
        removeFromArray(from, item);
    }
} 