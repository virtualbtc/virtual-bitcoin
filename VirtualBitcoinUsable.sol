// SPDX-License-Identifier: MIT
pragma solidity ^0.8.3;

interface VirtualBitcoinUsable {
    function useVirtualBitcoin(address user, uint256 value) external returns (bool success);
}