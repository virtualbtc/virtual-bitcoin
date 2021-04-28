// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

// this is a sample code for a new calculation of subsidy
contract NewCaluclateSubsidy {

    uint8 constant private DECIMALS = 8;
    uint256 constant public COIN = 10 ** uint256(DECIMALS);
    uint32 constant public SUBSIDY_HALVING_INTERVAL = 210000 * 20;

    uint256 immutable public genesisEthBlock;

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
    }

    function calculateAccSubsidy() internal {

        uint256 div1 = (accSubsidyBlock - genesisEthBlock) / SUBSIDY_HALVING_INTERVAL;
        uint256 div2 = (block.number - genesisEthBlock) / SUBSIDY_HALVING_INTERVAL;

        uint256 subsidy = 0;
        if (div1 == div2) {
            subsidy += (block.number - accSubsidyBlock) * subsidies[div1];
        } else {
            uint256 boundary = (div1 + 1) * SUBSIDY_HALVING_INTERVAL + genesisEthBlock;
            subsidy += (boundary - accSubsidyBlock) * subsidies[div1];
            uint256 span = div2 - div1;
            for(uint256 i = 1; i < span; i += 1) {
                boundary = (div1 + 1 + i) * SUBSIDY_HALVING_INTERVAL + genesisEthBlock;
                subsidy += SUBSIDY_HALVING_INTERVAL * subsidies[div1 + i];
            }
            subsidy += (block.number - boundary) * subsidies[div2];
        }
        accSubsidy += subsidy / totalPower;

        accSubsidyBlock = block.number;
    }

    function makePizza(uint256 power) external {
        require(power > 0);
        calculateAccSubsidy();

        pizzas.push(Pizza({
            owner: msg.sender,
            power: power,
            minedBlock: block.number,
            accSubsidy: accSubsidy
        }));

        totalPower += power;
    }

    function minePizza(uint256 pizzaId) external {

        Pizza storage pizza = pizzas[pizzaId];
        require(pizza.owner == msg.sender);

        balances[msg.sender] += (accSubsidy - pizza.accSubsidy) * (block.number - pizza.minedBlock);

        pizza.minedBlock = block.number;
        pizza.accSubsidy = accSubsidy;
    }
}