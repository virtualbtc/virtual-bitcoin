// SPDX-License-Identifier: MIT
pragma solidity ^0.8.3;

import "./ERC20.sol";
import "./ERC165.sol";
import "./VirtualBitcoinUsable.sol";

contract VirtualBitcoin is ERC20, ERC165 {

    string  constant public NAME = "Virtual Bitcoin";
    string  constant public SYMBOL = "VBTC";
    uint8   constant public DECIMALS = 8;
    uint256 constant public COIN = 10 ** uint256(DECIMALS);
    uint256 constant public PIZZA_POWER_PRICE = 10000 * COIN;
    uint256 constant public MAXIMUM_SUPPLY = 21000000 * COIN;
    uint32  constant public SUBSIDY_HALVING_INTERVAL = 210000 * 10;

    event BuyPizza(address indexed user, uint256 pizzaId, uint256 power);
    event SellPizza(address indexed user, uint256 pizzaId);
    event Mine(address indexed user, uint256 subsidy);
    event Use(address indexed user, address indexed _contract, uint256 value);

    uint256 private genesisBlockNumber;
    uint256 private _totalSupply;

    struct Pizza {
        address owner;
        uint256 power;
        uint256 blockNumber;
        uint256 lastMinedBlockNumber;
        uint256 totalPower;
    }
    Pizza[] pizzas;
    uint256 totalPower;

    constructor() {
        genesisBlockNumber = block.number;
        createPizza(1); // genesis pizza
    }

    mapping(address => uint256) private balances;
    mapping(uint256 => uint256) private blockSubsidyCache;
    mapping(address => mapping(address => uint256)) private allowed;

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

    function supportsInterface(bytes4 interfaceID) external pure override returns (bool) {
        return
            // ERC165
            interfaceID == this.supportsInterface.selector ||
            // ERC20
            interfaceID == 0x942e8b22 ||
            interfaceID == 0x36372b07;
    }

    function createPizza(uint256 power) internal returns (uint256) {
        require(power > 0);
        totalPower += power;
        uint256 pizzaId = pizzas.length;
        pizzas.push(Pizza({
            owner: msg.sender,
            power: power,
            blockNumber: block.number,
            lastMinedBlockNumber: block.number,
            totalPower: totalPower
        }));
        return pizzaId;
    }

    function buyPizza(uint256 power) external returns (uint256) {
        balances[msg.sender] -= power * PIZZA_POWER_PRICE;
        uint256 pizzaId = createPizza(power);
        emit BuyPizza(msg.sender, pizzaId, power);
        return pizzaId;
    }

    function sellPizza(uint256 pizzaId) external {
        
        Pizza memory pizza = pizzas[pizzaId];
        require(pizza.owner == msg.sender);

        pizza.owner = address(0);
        totalPower -= pizza.power;

        pizzas.push(Pizza({
            owner: address(0),
            power: 0,
            blockNumber: block.number,
            lastMinedBlockNumber: block.number,
            totalPower: totalPower
        }));

        balances[msg.sender] += pizza.power * PIZZA_POWER_PRICE;

        emit SellPizza(msg.sender, pizzaId);
    }

    function subsidyOf(uint256 pizzaId) external view returns (uint256) {

        Pizza memory pizza = pizzas[pizzaId];

        uint256 subsidy = 0;
        uint256 pizzaIndex = pizzas.length - 1;
        uint256 blockPower = totalPower;

        for (uint256 blockNumber = block.number - 1; blockNumber > pizza.lastMinedBlockNumber; blockNumber -= 1) {
            if (blockSubsidyCache[blockNumber] != 0) {
                subsidy += blockSubsidyCache[blockNumber];
            } else {
                uint256 halvings = (blockNumber - genesisBlockNumber) / SUBSIDY_HALVING_INTERVAL;
                if (halvings < 64) {
                    uint256 blockSubsidy = 5 * COIN;
                    blockSubsidy >>= halvings;

                    while(true) {
                        Pizza memory p = pizzas[pizzaIndex];
                        if (blockNumber <= p.lastMinedBlockNumber) {
                            blockPower = p.power;
                            pizzaIndex -= 1;
                        } else {
                            break;
                        }
                    }
                    blockSubsidy /= blockPower;
                    subsidy += blockSubsidy;
                }
            }
        }

        return subsidy;
    }

    function mine(uint256 pizzaId) external {
        require(_totalSupply < MAXIMUM_SUPPLY);

        Pizza storage pizza = pizzas[pizzaId];
        require(pizza.owner == msg.sender);

        uint256 subsidy = 0;
        uint256 pizzaIndex = pizzas.length - 1;
        uint256 blockPower = totalPower;

        for (uint256 blockNumber = block.number - 1; blockNumber > pizza.lastMinedBlockNumber; blockNumber -= 1) {
            if (blockSubsidyCache[blockNumber] != 0) {
                subsidy += blockSubsidyCache[blockNumber];
            } else {
                uint256 halvings = (blockNumber - genesisBlockNumber) / SUBSIDY_HALVING_INTERVAL;
                if (halvings < 64) {
                    uint256 blockSubsidy = 50 * COIN;
                    blockSubsidy >>= halvings;

                    while(true) {
                        Pizza memory p = pizzas[pizzaIndex];
                        if (blockNumber <= p.lastMinedBlockNumber) {
                            blockPower = p.power;
                            pizzaIndex -= 1;
                        } else {
                            break;
                        }
                    }
                    blockSubsidy /= blockPower;
                    subsidy += blockSubsidy;
                    blockSubsidyCache[blockNumber] = blockSubsidy;
                }
            }
        }

        require(subsidy > 0);

        if (_totalSupply + subsidy > MAXIMUM_SUPPLY) {
            subsidy = MAXIMUM_SUPPLY - _totalSupply;
        }

        pizza.lastMinedBlockNumber = block.number - 1;
        balances[msg.sender] += subsidy;
        _totalSupply += subsidy;

        emit Mine(msg.sender, subsidy);
    }

    function use(address contractAddress, uint256 amount) external returns (bool) {

        require(transfer(contractAddress, amount));

        VirtualBitcoinUsable _contract = VirtualBitcoinUsable(contractAddress);
        bool success = _contract.useVirtualBitcoin(msg.sender, amount);
        emit Use(msg.sender, contractAddress, amount);
        return success;
    }
}