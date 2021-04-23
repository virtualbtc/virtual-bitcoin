// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "./VirtualBitcoinInterface.sol";
import "./VirtualBitcoinUsable.sol";

contract VirtualBitcoin is VirtualBitcoinInterface {

    string  constant public NAME = "Virtual Bitcoin";
    string  constant public SYMBOL = "VBTC";
    uint8   constant public DECIMALS = 8;
    uint256 constant public COIN = 10 ** uint256(DECIMALS);
    uint256 constant public PIZZA_POWER_PRICE = 10000 * COIN;
    uint256 constant public MAXIMUM_SUPPLY = 21000000 * COIN;
    uint32  constant public SUBSIDY_HALVING_INTERVAL = 210000 * 10;
    uint32  constant public SUBSIDY_BLOCK_LIMIT = 64 * SUBSIDY_HALVING_INTERVAL;

    uint256 public genesisEthereumBlockNumber;
    uint256 public _totalSupply;

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

        uint256 amount = 5 * COIN;
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

    function recordHistory() internal {
        
        uint256 blockNumber = block.number - genesisEthereumBlockNumber;
        require(blockNumber < SUBSIDY_BLOCK_LIMIT);

        history.push(Record({
            blockNumber: blockNumber,
            totalPower: _totalPower
        }));
    }

    function createPizza(uint256 power) internal returns (uint256) {
        require(power > 0);

        uint256 pizzaId = pizzas.length;
        pizzas.push(Pizza({
            owner: msg.sender,
            power: power,
            minedHistoryIndex: history.length - 1,
            minedBlockNumber: block.number - genesisEthereumBlockNumber
        }));

        _totalPower += power;
        recordHistory();

        return pizzaId;
    }

    function buyPizza(uint256 power) external override returns (uint256) {
        balances[msg.sender] -= power * PIZZA_POWER_PRICE;
        uint256 pizzaId = createPizza(power);
        emit BuyPizza(msg.sender, pizzaId, power);
        return pizzaId;
    }

    function sellPizza(uint256 pizzaId) external override {
        
        Pizza storage pizza = pizzas[pizzaId];
        require(pizza.owner == msg.sender);

        mineAll(pizzaId);
        pizza.owner = address(0);
        _totalPower -= pizza.power;
        recordHistory();

        balances[msg.sender] += pizza.power * PIZZA_POWER_PRICE;

        emit SellPizza(msg.sender, pizzaId);
    }

    function blockSubsidy(uint256 fromHistoryIndex, uint256 toBlockNumber, uint256 totalPower) internal view returns (uint256) {

        Record memory record = history[fromHistoryIndex];

        uint256 historyLength = history.length;
        uint256 subsidy = 0;
        for (uint256 i = fromHistoryIndex; i < historyLength; i += 1) {

            Record memory next = i == historyLength - 1 ? Record({
                blockNumber: toBlockNumber,
                totalPower: totalPower
            }) : history[i + 1];

            uint256 recordBlockNumber = record.blockNumber;
            uint256 nextBlockNumber = next.blockNumber;
            if (nextBlockNumber > toBlockNumber) {
                nextBlockNumber = toBlockNumber;
            }

            uint256 divided = recordBlockNumber / SUBSIDY_HALVING_INTERVAL;
            uint256 nextDivided = nextBlockNumber / SUBSIDY_HALVING_INTERVAL;
            if (divided != nextDivided) {
                uint256 boundary = nextDivided * SUBSIDY_HALVING_INTERVAL;
                subsidy += (boundary - recordBlockNumber) * subsidies[divided].amount / record.totalPower;
                subsidy += (nextBlockNumber - boundary) * subsidies[nextDivided].amount / record.totalPower;
            } else {
                subsidy += (nextBlockNumber - recordBlockNumber) * subsidies[divided].amount / record.totalPower;
            }

            if (nextBlockNumber == toBlockNumber) {
                break;
            }
            record = next;
        }

        return subsidy;
    }

    function subsidyOf(uint256 pizzaId) external view override returns (uint256) {        
        Pizza memory pizza = pizzas[pizzaId];
        return blockSubsidy(pizza.minedHistoryIndex, block.number - genesisEthereumBlockNumber, _totalPower) * pizza.power;
    }

    function mine(uint256 pizzaId, uint256 blockNumber) public override {

        Pizza storage pizza = pizzas[pizzaId];
        require(pizza.owner == msg.sender);

        uint256 subsidy = blockSubsidy(pizza.minedHistoryIndex, blockNumber, _totalPower) * pizza.power;
        require(subsidy > 0);
        if (_totalSupply + subsidy > MAXIMUM_SUPPLY) {
            subsidy = MAXIMUM_SUPPLY - _totalSupply;
        }

        balances[msg.sender] += subsidy;
        _totalSupply += subsidy;
        pizza.minedBlockNumber = blockNumber;

        emit Mine(msg.sender, blockNumber, subsidy);
    }

    function mineAll(uint256 pizzaId) public override {
        mine(pizzaId, block.number - genesisEthereumBlockNumber);
    }

    function use(address contractAddress, uint256 amount) external override returns (bool) {

        require(transfer(contractAddress, amount));

        VirtualBitcoinUsable _contract = VirtualBitcoinUsable(contractAddress);
        bool success = _contract.useVirtualBitcoin(msg.sender, amount);
        emit Use(msg.sender, contractAddress, amount);
        return success;
    }
}