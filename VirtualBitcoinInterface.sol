// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

interface VirtualBitcoinInterface {

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
    event BuyPizza(address indexed user, uint256 pizzaId, uint256 power);
    event SellPizza(address indexed user, uint256 pizzaId);
    event Mine(address indexed user, uint256 blockNumber, uint256 subsidy);
    event Use(address indexed user, address indexed _contract, uint256 value);

    function name() external view returns (string memory);
    function symbol() external view returns (string memory);
    function decimals() external view returns (uint8);

    function totalSupply() external view returns (uint256);
    function balanceOf(address owner) external view returns (uint256 balance);
    function transfer(address to, uint256 value) external returns (bool success);
    function transferFrom(address from, address to, uint256 value) external returns (bool success);
    function approve(address spender, uint256 value) external returns (bool success);
    function allowance(address owner, address spender) external view returns (uint256 remaining);

    function buyPizza(uint256 power) external returns (uint256);
    function sellPizza(uint256 pizzaId) external;
    function subsidyOf(uint256 pizzaId) external view returns (uint256);
    function mine(uint256 pizzaId, uint256 blockNumber) external;
    function mineAll(uint256 pizzaId) external;
    function use(address contractAddress, uint256 amount) external returns (bool);
}