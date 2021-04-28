// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "./VirtualBitcoinInterface.sol";

contract VirtualBitcoin is VirtualBitcoinInterface {

    string  constant public NAME = "Virtual Bitcoin";
    string  constant public SYMBOL = "VBTC";
    uint8   constant public DECIMALS = 8;
    uint256 constant public COIN = 10 ** uint256(DECIMALS);
    uint256 constant public PIZZA_POWER_PRICE = 10000 * COIN;
    uint32  constant public SUBSIDY_HALVING_INTERVAL = 210000 * 20;

    uint256 public genesisEthBlock;
    
    uint256 private _totalSupply;
    mapping(address => uint256) private balances;
    mapping(address => mapping(address => uint256)) private allowed;

    uint256[] public subsidies;

    struct Pizza {
        address owner;
        uint256 power;
        uint256 minedBlock;
        uint256 accSubsidy;
    }
    Pizza[] public pizzas;

    uint256 private accSubsidyBlock;

    uint256 public accSubsidy;
    uint256 public totalPower;

    constructor() {
        genesisEthBlock = block.number;

        uint256 amount = 25 * COIN / 10;
        for (uint8 i = 0; i < 64; i += 1) {
            subsidies.push(amount);
            amount /= 2;
        }

        makePizza(1);
    }

    function name() external pure override returns (string memory) { return NAME; }
    function symbol() external pure override returns (string memory) { return SYMBOL; }
    function decimals() external pure override returns (uint8) { return DECIMALS; }
    function totalSupply() external view override returns (uint256) { return _totalSupply; }

    function balanceOf(address user) external view override returns (uint256 balance) {
        return balances[user];
    }

    function transfer(address to, uint256 amount) public override returns (bool success) {
        balances[msg.sender] -= amount;
        balances[to] += amount;
        emit Transfer(msg.sender, to, amount);
        return true;
    }

    function approve(address spender, uint256 amount) external override returns (bool success) {
        allowed[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function allowance(address user, address spender) external view override returns (uint256 remaining) {
        return allowed[user][spender];
    }

    function transferFrom(address from, address to, uint256 amount) external override returns (bool success) {
        balances[from] -= amount;
        balances[to] += amount;
        allowed[from][msg.sender] -= amount;
        emit Transfer(from, to, amount);
        return true;
    }

    function pizzaPrice(uint256 power) external pure override returns (uint256) {
        return power * PIZZA_POWER_PRICE;
    }

    function calculateAccSubsidy() internal view returns (uint256) {

        uint256 div1 = (accSubsidyBlock - genesisEthBlock) / SUBSIDY_HALVING_INTERVAL;
        uint256 div2 = (block.number - genesisEthBlock) / SUBSIDY_HALVING_INTERVAL;

        uint256 subsidy = 0;
        if (div1 == div2) {
            subsidy += (block.number - accSubsidyBlock) * subsidies[div1];
        } else {
            uint256 boundary = (div1 + 1) * SUBSIDY_HALVING_INTERVAL + genesisEthBlock;
            subsidy += (boundary - accSubsidyBlock) * subsidies[div1];
            uint256 span = div2 - div1;
            for (uint256 i = 1; i < span; i += 1) {
                boundary = (div1 + 1 + i) * SUBSIDY_HALVING_INTERVAL + genesisEthBlock;
                subsidy += SUBSIDY_HALVING_INTERVAL * subsidies[div1 + i];
            }
            subsidy += (block.number - boundary) * subsidies[div2];
        }

        return accSubsidy + subsidy / totalPower;
    }

    function makePizza(uint256 power) internal returns (uint256) {
        require(power > 0);

        accSubsidy = calculateAccSubsidy();
        accSubsidyBlock = block.number;

        uint256 pizzaId = pizzas.length;
        pizzas.push(Pizza({
            owner: msg.sender,
            power: power,
            minedBlock: block.number,
            accSubsidy: accSubsidy
        }));

        totalPower += power;
        
        return pizzaId;
    }

    function buyPizza(uint256 power) external override returns (uint256) {
        balances[msg.sender] -= power * PIZZA_POWER_PRICE;
        uint256 pizzaId = makePizza(power);
        emit BuyPizza(msg.sender, pizzaId, power);
        return pizzaId;
    }

    function changePizzaPower(uint256 pizzaId, uint256 power) external override {

        Pizza storage pizza = pizzas[pizzaId];
        require(pizzaId != 0);
        require(pizza.owner == msg.sender);
        
        uint256 currentPower = pizza.power;
        require(currentPower != power);
        mine(pizzaId);

        pizza.power = power;
    
        if (currentPower < power) { // upgrade
            uint256 diff = power - currentPower;
            totalPower += diff;
            balances[msg.sender] -= diff * PIZZA_POWER_PRICE;
        } else { // downgrade
            uint256 diff = currentPower - power;
            totalPower -= diff;
            balances[msg.sender] += diff * PIZZA_POWER_PRICE;
        }
        
        emit ChangePizzaPower(msg.sender, pizzaId, power);
    }

    function sellPizza(uint256 pizzaId) external override {
        
        Pizza storage pizza = pizzas[pizzaId];
        require(pizzaId != 0);
        require(pizza.owner == msg.sender);

        uint256 power = pizza.power;
        mine(pizzaId);
        pizza.owner = address(0);
        totalPower -= power;

        balances[msg.sender] += power * PIZZA_POWER_PRICE;

        emit SellPizza(msg.sender, pizzaId);
    }

    function subsidyOf(uint256 pizzaId) external view override returns (uint256) {
        Pizza memory pizza = pizzas[pizzaId];
        if (pizza.owner == address(0)) {
            return 0;
        }
        return (calculateAccSubsidy() - pizza.accSubsidy) * (block.number - pizza.minedBlock);
    }

    function mine(uint256 pizzaId) public override returns (uint256) {

        Pizza storage pizza = pizzas[pizzaId];
        require(pizza.owner == msg.sender);

        accSubsidy = calculateAccSubsidy();
        accSubsidyBlock = block.number;

        uint256 subsidy = (accSubsidy - pizza.accSubsidy) * (block.number - pizza.minedBlock);
        balances[msg.sender] += subsidy;

        pizza.minedBlock = block.number;
        pizza.accSubsidy = accSubsidy;

        emit Mine(msg.sender, pizzaId, subsidy);

        return subsidy;
    }
}