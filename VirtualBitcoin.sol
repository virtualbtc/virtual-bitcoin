// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "./VirtualBitcoinInterface.sol";

contract VirtualBitcoin is VirtualBitcoinInterface {

    string  constant private NAME = "Virtual Bitcoin";
    string  constant private SYMBOL = "VBTC";
    uint8   constant private DECIMALS = 8;
    uint256 constant public COIN = 10 ** uint256(DECIMALS);
    uint256 constant public MAX_COIN = 21000000 * COIN;
    uint256 constant public PIZZA_POWER_PRICE = 10000 * COIN;
    uint32  constant public SUBSIDY_HALVING_INTERVAL = 210000 * 20;
    uint32  constant public SUBSIDY_BLOCK_LIMIT = 64 * SUBSIDY_HALVING_INTERVAL;

    uint256 immutable public genesisEthereumBlockNumber;
    uint256 private _totalSupply;

    mapping(address => uint256) private balances;
    mapping(address => mapping(address => uint256)) private allowed;

    struct Subsidy {
        uint256 blockNumber;
        uint256 amount;
    }
    Subsidy[] public subsidies;

    struct Pizza {
        address owner;
        uint256 power;
        uint256 minedHistoryIndex;
        uint256 minedBlockNumber;
    }
    Pizza[] public pizzas;

    struct Record {
        uint256 blockNumber;
        uint256 totalPower;
    }
    Record[] private history;

    uint256 public _totalPower;

    constructor() {
        genesisEthereumBlockNumber = block.number;

        uint256 amount = 25 * COIN / 10;
        uint256 blockNumber = 0;
        for (uint8 i = 0; i < 64; i += 1) {
            subsidies.push(Subsidy({
                blockNumber: blockNumber,
                amount: amount
            }));
            blockNumber += SUBSIDY_HALVING_INTERVAL;
            amount /= 2;
        }
        createPizza(1); // genesis pizza
        history.push(Record({
            blockNumber: block.number,
            totalPower: _totalPower
        }));
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

    function subsidiesRealBlockConverter(uint8 i) external view returns (uint256, uint256) {
        return (subsidies[i].blockNumber + genesisEthereumBlockNumber, subsidies[i].amount);
    }
    
    //Gas inefficient check for about 56 years.
    function recordHistory(uint256 pizzaId, uint8 typeId) internal {
        if(block.number - genesisEthereumBlockNumber < SUBSIDY_HALVING_INTERVAL * 28) {
            history.push(Record({
                blockNumber: block.number,
                totalPower: _totalPower
            }));
        } else if(typeId == 0) {
            pizzas[pizzaId].minedHistoryIndex = type(uint256).max;
        }
    }

    function pizzaPrice(uint256 power) external pure override returns (uint256) {
        return power * PIZZA_POWER_PRICE;
    }

    function createPizza(uint256 power) internal returns (uint256) {
        require(power > 0);

        uint256 pizzaId = pizzas.length;
        pizzas.push(Pizza({
            owner: msg.sender,
            power: power,
            minedHistoryIndex: history.length,
            minedBlockNumber: block.number
        }));

        _totalPower += power;

        return pizzaId;
    }

    function buyPizza(uint256 power) external override returns (uint256) {
        balances[msg.sender] -= power * PIZZA_POWER_PRICE;
        uint256 pizzaId = createPizza(power);
        recordHistory(pizzaId, 0);
        emit BuyPizza(msg.sender, pizzaId, power);
        return pizzaId;
    }

    function sellPizza(uint256 pizzaId) external override {
        Pizza storage pizza = pizzas[pizzaId];
        require(pizzaId != 0);
        require(pizza.owner == msg.sender);

        uint256 power = pizza.power;
        mineAll(pizzaId);
        pizza.owner = address(0);
        _totalPower -= power;
        recordHistory(pizzaId, 1);

        balances[msg.sender] += power * PIZZA_POWER_PRICE;

        emit SellPizza(msg.sender, pizzaId);
    }

    function blockSubsidy(uint256 fromHistoryIndex, uint256 fromBlockNumber, uint256 toBlockNumber) internal view returns (uint256, uint256) {
        Record memory record = history[fromHistoryIndex];
        record.blockNumber = fromBlockNumber;

        uint256 genesisBlockNumber = genesisEthereumBlockNumber;
        uint256 historyIndex = fromHistoryIndex;
        uint256 historyLength = history.length;
        uint256 subsidy = 0;

        for (; historyIndex < historyLength; historyIndex += 1) {

            Record memory next = historyIndex == historyLength - 1 ? Record({
                blockNumber: toBlockNumber,
                totalPower: record.totalPower
            }) : history[historyIndex + 1];

            uint256 recordBlockNumber = record.blockNumber;
            uint256 nextBlockNumber = next.blockNumber;
            if (nextBlockNumber > toBlockNumber) {
                nextBlockNumber = toBlockNumber;
            }

            uint256 divided = (recordBlockNumber - genesisBlockNumber) / SUBSIDY_HALVING_INTERVAL;
            uint256 nextDivided = (nextBlockNumber - genesisBlockNumber) / SUBSIDY_HALVING_INTERVAL;
            if (divided == nextDivided) {
                subsidy += (nextBlockNumber - recordBlockNumber) * subsidies[divided].amount / record.totalPower;
            } else {
                uint256 span = nextDivided - divided;
                uint256 boundary = (divided + 1) * SUBSIDY_HALVING_INTERVAL + genesisBlockNumber;
                subsidy += (boundary - recordBlockNumber) * subsidies[divided].amount / record.totalPower;
                for(uint256 j = 1; j < span; j += 1) {
                    boundary = (divided + j + 1) * SUBSIDY_HALVING_INTERVAL + genesisBlockNumber;
                    subsidy += SUBSIDY_HALVING_INTERVAL * subsidies[divided + j].amount / record.totalPower;
                }
                subsidy += (nextBlockNumber - boundary) * subsidies[nextDivided].amount / record.totalPower;
            }

            if (nextBlockNumber == toBlockNumber) {
                break;
            }
            record = next;
        }

        return (subsidy, historyIndex);
    }

    function subsidyOf(uint256 pizzaId) external view override returns (uint256) {
        Pizza memory pizza = pizzas[pizzaId];
        if(pizza.owner == address(0)) return 0;
        uint256 lastMiningBlock = SUBSIDY_HALVING_INTERVAL * 28 + genesisEthereumBlockNumber;
        (uint256 subsidy,) = block.number > lastMiningBlock ? blockSubsidy(pizza.minedHistoryIndex, pizza.minedBlockNumber, lastMiningBlock) : blockSubsidy(pizza.minedHistoryIndex, pizza.minedBlockNumber, block.number);
        return subsidy * pizza.power;
    }

    function mine(uint256 pizzaId, uint256 toBlockNumber) public override returns (uint256) {
        require(toBlockNumber <= block.number);
        uint256 lastMiningBlock = SUBSIDY_HALVING_INTERVAL * 28 + genesisEthereumBlockNumber;
        if(toBlockNumber > lastMiningBlock) toBlockNumber = lastMiningBlock;

        Pizza storage pizza = pizzas[pizzaId];
        require(pizza.owner == msg.sender);

        (uint256 subsidy, uint256 historyIndex) = blockSubsidy(pizza.minedHistoryIndex, pizza.minedBlockNumber, toBlockNumber);
        subsidy *= pizza.power;

        balances[msg.sender] += subsidy;
        _totalSupply += subsidy;
        pizza.minedHistoryIndex = historyIndex;
        pizza.minedBlockNumber = toBlockNumber;

        emit Mine(msg.sender, toBlockNumber, subsidy);
        return subsidy;
    }

    function mineAll(uint256 pizzaId) public override returns (uint256) {
        return mine(pizzaId, block.number);
    }
}