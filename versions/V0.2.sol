// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

interface VirtualBitcoinInterface {

    event Transfer(address indexed from, address indexed to, uint256 amount);
    event Approval(address indexed owner, address indexed spender, uint256 amount);
    event BuyPizza(address indexed user, uint256 pizzaId, uint256 power);
    event SellPizza(address indexed user, uint256 pizzaId);
    event Mine(address indexed user, uint256 blockNumber, uint256 subsidy);

    function name() external view returns (string memory);
    function symbol() external view returns (string memory);
    function decimals() external view returns (uint8);

    function totalSupply() external view returns (uint256);
    function balanceOf(address owner) external view returns (uint256 balance);
    function transfer(address to, uint256 amount) external returns (bool success);
    function transferFrom(address from, address to, uint256 amount) external returns (bool success);
    function approve(address spender, uint256 amount) external returns (bool success);
    function allowance(address owner, address spender) external view returns (uint256 remaining);

    function pizzaPrice(uint256 power) external view returns (uint256);
    function buyPizza(uint256 power) external returns (uint256);
    function sellPizza(uint256 pizzaId) external;
    function subsidyOf(uint256 pizzaId) external view returns (uint256);
    function mine(uint256 pizzaId, uint256 toBlockNumber) external returns (uint256);
    function mineAll(uint256 pizzaId) external returns (uint256);
}

contract VirtualBitcoin is VirtualBitcoinInterface {

    string  constant public NAME = "Virtual Bitcoin";
    string  constant public SYMBOL = "VBTC";
    uint8   constant public DECIMALS = 8;
    uint256 constant public COIN = 10 ** uint256(DECIMALS);
    uint256 constant public MAX_COIN = 21000000 * COIN;
    uint256 constant public PIZZA_POWER_PRICE = 10000 * COIN;
    uint32  constant public SUBSIDY_HALVING_INTERVAL = 210000 * 20;
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
        
        uint256 blockNumber = block.number;
        require(blockNumber < SUBSIDY_BLOCK_LIMIT);

        history.push(Record({
            blockNumber: blockNumber,
            totalPower: _totalPower
        }));
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

    function blockSubsidy(uint256 fromHistoryIndex, uint256 fromBlockNumber, uint256 toBlockNumber, uint256 totalPower) internal view returns (uint256, uint256) {

        Record memory record = history[fromHistoryIndex];
        record.blockNumber = fromBlockNumber;

        uint256 historyIndex = fromHistoryIndex;
        uint256 historyLength = history.length;
        uint256 subsidy = 0;

        for (; historyIndex < historyLength; historyIndex += 1) {

            Record memory next = historyIndex == historyLength - 1 ? Record({
                blockNumber: toBlockNumber,
                totalPower: totalPower
            }) : history[historyIndex + 1];

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

        return (subsidy, historyIndex);
    }

    function subsidyOf(uint256 pizzaId) external view override returns (uint256) {        
        Pizza memory pizza = pizzas[pizzaId];
        (uint256 subsidy,) = blockSubsidy(pizza.minedHistoryIndex, pizza.minedBlockNumber, block.number, _totalPower);
        return subsidy * pizza.power;
    }

    function mine(uint256 pizzaId, uint256 toBlockNumber) public override returns (uint256) {

        Pizza storage pizza = pizzas[pizzaId];
        require(pizza.owner == msg.sender);

        (uint256 subsidy, uint256 historyIndex) = blockSubsidy(pizza.minedHistoryIndex, pizza.minedBlockNumber, toBlockNumber, _totalPower);
        subsidy *= pizza.power;

        require(subsidy > 0);
        if (_totalSupply + subsidy > MAX_COIN) {
            subsidy = MAX_COIN - _totalSupply;
        }

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