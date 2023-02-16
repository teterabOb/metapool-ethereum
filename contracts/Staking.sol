// SPDX-License-Identifier: MIT
pragma solidity ^0.8;

import "@openzeppelin/contracts-upgradeable/utils/CountersUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/math/MathUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

import "./IDeposit.sol";
import "./LiquidUnstakePool.sol";
import "./IWETH.sol";

contract Staking is Initializable, ERC4626Upgradeable, OwnableUpgradeable {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    struct Node {
        bytes pubkey;
        bytes withdrawCredentials;
        bytes signature;
        bytes32 depositDataRoot;
    }
    mapping(uint => Node) public nodes;

    uint public nodesTotalBalance;

    address public LIQUID_POOL;
    uint64 public nodesBalanceUnlockTime;
    IDeposit public depositContract;
    uint64 private constant UPDATE_BALANCE_TIMELOCK = 4 hours;
    uint64 private constant MIN_DEPOSIT = 0.01 ether;
    uint64 private estimatedRewardsPerSecond;
    uint32 public currentNode;

    event Mint(
        address indexed sender,
        address indexed owner,
        uint256 assets,
        uint256 shares
    );
    event Stake(uint nodeId, bytes indexed pubkey);
    event UpdateNodeData(uint nodeId, Node data);
    event UpdateNodesBalance(uint balance);

    modifier validDeposit(uint _amount) {
        _checkDeposit(_amount);
        _;
    }

    function _checkDeposit(uint _amount) internal view {
        require(
            _amount >= minDeposit(msg.sender),
            "Staking: MIN_DEPOSIT_ERROR"
        );
        require(
            _amount <= maxDeposit(msg.sender),
            "Staking: MAX_DEPOSIT_ERROR"
        );
    }

    function initialize(
        IDeposit _depositContract,
        Node[] memory _nodes,
        IERC20MetadataUpgradeable _weth
    ) external payable initializer {
        __ERC4626_init(IERC20Upgradeable(_weth));
        __ERC20_init("MetaPoolETH", "mpETH");
        __Ownable_init();
        require(
            _weth.decimals() == 18,
            "wNative token error, implementation for 18 decimals"
        );
        uint initialStake = address(this).balance;
        require(initialStake % 32 ether == 0, "Invalid ETH amount");
        uint nodesLength = _nodes.length;
        for (uint i = 0; i < nodesLength; i++) nodes[i] = _nodes[i];
        depositETH(msg.sender);
        depositContract = _depositContract;
    }

    receive() external payable {
        depositETH(msg.sender);
    }

    /// @notice Returns total ETH held by vault + validators
    function totalAssets() public view override returns (uint) {
        return
            address(this).balance +
            nodesTotalBalance +
            estimatedRewardsPerSecond *
            (uint64(block.timestamp) -
                nodesBalanceUnlockTime -
                UPDATE_BALANCE_TIMELOCK);
    }

    function minDeposit(address) public pure returns (uint) {
        return MIN_DEPOSIT;
    }

    /// @notice Will return the max withdraw for an user once Ethereum enable staking withdraw
    function maxWithdraw(address) public pure override returns (uint) {
        return 0;
    }

    function updateLiquidPool(address _liquidPool) external onlyOwner {
        require(_liquidPool != address(0), "Invalid address zero");
        LIQUID_POOL = _liquidPool;
    }

    /// @notice Update node data
    function updateNode(uint _nodeId, Node memory _node) external onlyOwner {
        require(
            _nodeId > currentNode,
            "ERROR: Trying to update a previous node"
        );
        nodes[_nodeId] = _node;
        emit UpdateNodeData(_nodeId, _node);
    }

    /// @notice Updates nodes total balance
    function updateNodesBalance(uint _newBalance) external onlyOwner {
        // TODO: Get % of rewards as mpETH for metapool
        uint64 _nodesBalanceUnlockTime = nodesBalanceUnlockTime;
        require(
            block.timestamp > _nodesBalanceUnlockTime,
            "Unlock time not reached"
        );
        uint _nodesTotalBalance = nodesTotalBalance;
        uint diff = _newBalance > _nodesTotalBalance
            ? _newBalance - _nodesTotalBalance
            : _nodesTotalBalance - _newBalance;
        require(
            diff <= _nodesTotalBalance / 1000,
            "Difference greater than 0.1%"
        );

        estimatedRewardsPerSecond = uint64(
            diff /
                (uint64(block.timestamp) -
                    _nodesBalanceUnlockTime -
                    UPDATE_BALANCE_TIMELOCK)
        );
        nodesBalanceUnlockTime =
            uint64(block.timestamp) +
            UPDATE_BALANCE_TIMELOCK;
        nodesTotalBalance = _newBalance;
        emit UpdateNodesBalance(_newBalance);
    }

    /// @notice Stake ETH in contract to validators
    function pushToBacon(uint32 _nodesAmount) external {
        _nodesAmount = uint32(
            MathUpgradeable.min(
                (address(this).balance % 32 ether),
                _nodesAmount
            )
        );
        require(
            _nodesAmount > 0,
            "Not enough balance or trying to push 0 nodes"
        );
        require(_stake(_nodesAmount), "ERROR: Node data empty at last index");
    }

    /// @notice Deposit WETH
    function deposit(uint256 _assets, address _receiver)
        public
        override
        validDeposit(_assets)
        returns (uint256)
    {
        uint256 _shares = previewDeposit(_assets);
        _deposit(msg.sender, _receiver, _assets, _shares);
        return _shares;
    }

    /// @notice Deposit ETH
    function depositETH(address _receiver)
        public
        payable
        validDeposit(msg.value)
        returns (uint256)
    {
        uint256 _shares = previewDeposit(msg.value);
        _deposit(msg.sender, _receiver, 0, _shares);
        return _shares;
    }

    /// @notice Confirm ETH or WETH deposit
    /// @dev Get ETH or get and convert WETH to ETH, get mpETH from pool and/or mint new mpETH, and try to stake to 1 node
    function _deposit(
        address _caller,
        address _receiver,
        uint256 _assets,
        uint256 _shares
    ) internal override {
        if (_assets != 0) {
            IERC20Upgradeable(asset()).safeTransferFrom(
                msg.sender,
                address(this),
                _assets
            );
            IWETH(asset()).withdraw(_assets);
        } else {
            _assets = msg.value;
        }
        uint availableShares = MathUpgradeable.min(
            IERC20Upgradeable(asset()).balanceOf(LIQUID_POOL),
            _shares
        );
        uint assetsToPool = convertToAssets(availableShares);
        require(
            LiquidUnstakePool(LIQUID_POOL).swapETHForAsset{value: assetsToPool}(
                _receiver
            ) == availableShares,
            "Pool _shares transfer error"
        );
        _shares -= availableShares;
        if (_shares > 0) {
            _mint(_receiver, _shares);
            emit Mint(_caller, _receiver, _assets - assetsToPool, _shares);
        }

        emit Deposit(_caller, _receiver, _assets, _shares + availableShares);
    }

    function _stake(uint32 _newNodesAmount) private returns (bool) {
        uint32 _currentNode = currentNode;
        uint32 _lastNode = _currentNode + _newNodesAmount;
        if (nodes[_lastNode].pubkey.length == 0) return false;

        for (uint i = _currentNode; i < _lastNode; i++) {
            Node memory node = nodes[i];
            depositContract.deposit{value: 32 ether}(
                node.pubkey,
                node.withdrawCredentials,
                node.signature,
                node.depositDataRoot
            );
            emit Stake(i, node.pubkey);
        }
        nodesTotalBalance += _newNodesAmount * 32 ether;
        currentNode = _lastNode;
        return true;
    }

    function _withdraw(
        address _caller,
        address _receiver,
        address _owner,
        uint256 _assets,
        uint256 _shares
    ) internal pure override {
        _caller;
        _receiver;
        _owner;
        _assets;
        _shares;
        revert("Withdraw not implemented");
    }
}
