// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/**
 * @title OpenAirdropUpgradeable
 * @dev A contract for managing token airdrops, where any user with tokens can create airdrops
 * @notice This contract allows any user with tokens to create and manage airdrops
 */

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract AirdropUpgradeable is
    Initializable,
    UUPSUpgradeable,
    AccessControlUpgradeable,
    ReentrancyGuardUpgradeable
{
    using SafeERC20 for IERC20;

    // Only needed for contract upgrades
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    struct AirdropData {
        IERC20 token;
        uint256 totalAllocated;
        uint256 startTime;
        uint256 airdropId;
        bool isDeleted;
        address creator; // Track who created the airdrop
        address[] investors;
        uint256[] currentAllocations;
        uint256[] claimed;
        mapping(address => uint256) investorIndex;
        mapping(address => uint256) allocations;
    }

    mapping(uint256 => AirdropData) public airdrops;
    uint256 public totalInvestors;
    uint256 public lastAirdropId;

    // Safety limits
    uint256 public constant MIN_RECIPIENTS = 1;
    uint256 public constant MAX_RECIPIENTS = 1000;

    event AirdropCreated(
        address indexed creator,
        address tokenAddress,
        uint256 indexed airdropId,
        uint256 startTime,
        address[] investors,
        uint256[] amounts
    );

    event TokenClaimed(
        address indexed user,
        uint256 indexed airdropId,
        uint256 amount,
        uint256 claimedAmount,
        uint256 remainingAllocation
    );

    event AirdropDeleted(
        uint256 indexed airdropId,
        address tokenAddress,
        uint256 timestamp
    );

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize() public initializer {
        __AccessControl_init();
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ADMIN_ROLE, msg.sender);
    }

    /**
     * @dev Creates a new airdrop. Any user can call this if they have the tokens
     * @param _tokenAddress Address of the token to be airdropped
     * @param _addresses Array of recipient addresses
     * @param _amounts Array of token amounts for each recipient
     * @param _startTime Timestamp when claiming can begin
     */
    function createAirdrop(
        address _tokenAddress,
        address[] memory _addresses,
        uint256[] memory _amounts,
        uint256 _startTime
    ) public {
        require(_tokenAddress != address(0), "Invalid token address");
        require(
            _addresses.length == _amounts.length,
            "Addresses and amounts length mismatch"
        );
        require(_startTime >= block.timestamp, "Start Time can't be in past");
        require(
            _addresses.length >= MIN_RECIPIENTS &&
                _addresses.length <= MAX_RECIPIENTS,
            "Invalid number of recipients"
        );

        uint256 totalTokensRequired = 0;
        for (uint256 i = 0; i < _amounts.length; i++) {
            require(_amounts[i] > 0, "Amount must be greater than 0");
            require(_addresses[i] != address(0), "Invalid address");
            totalTokensRequired += _amounts[i];
        }

        IERC20 token = IERC20(_tokenAddress);

        // Check if user has approved enough tokens
        require(
            token.allowance(msg.sender, address(this)) >= totalTokensRequired,
            "Insufficient allowance"
        );

        // Check if user has enough tokens
        require(
            token.balanceOf(msg.sender) >= totalTokensRequired,
            "Insufficient token balance"
        );

        // Transfer tokens using SafeERC20
        token.safeTransferFrom(msg.sender, address(this), totalTokensRequired);

        // Create new airdrop
        uint256 newAirdropId = lastAirdropId + 1;
        AirdropData storage newAirdrop = airdrops[newAirdropId];
        newAirdrop.token = token;
        newAirdrop.totalAllocated = totalTokensRequired;
        newAirdrop.startTime = _startTime;
        newAirdrop.airdropId = newAirdropId;
        newAirdrop.isDeleted = false;
        newAirdrop.creator = msg.sender;

        for (uint256 i = 0; i < _addresses.length; i++) {
            newAirdrop.investors.push(_addresses[i]);
            newAirdrop.currentAllocations.push(_amounts[i]);
            newAirdrop.claimed.push(0);
            newAirdrop.investorIndex[_addresses[i]] = i;
            newAirdrop.allocations[_addresses[i]] = _amounts[i];
        }

        totalInvestors += _addresses.length;
        lastAirdropId = newAirdropId;

        emit AirdropCreated(
            msg.sender,
            _tokenAddress,
            newAirdropId,
            _startTime,
            _addresses,
            _amounts
        );
    }

    /**
     * @dev Allows users to claim their allocated tokens
     * @param _airdropId ID of the airdrop to claim from
     */
    function claim(uint256 _airdropId) public nonReentrant {
        require(
            _airdropId > 0 && _airdropId <= lastAirdropId,
            "Invalid airdrop ID"
        );

        AirdropData storage airdrop = airdrops[_airdropId];
        require(!airdrop.isDeleted, "Airdrop has been deleted");
        require(block.timestamp >= airdrop.startTime, "Airdrop not started");

        uint256 investorIndex = airdrop.investorIndex[msg.sender];

        // Check if user is in the airdrop
        require(
            investorIndex < airdrop.investors.length,
            "Not eligible for this airdrop"
        );

        // Check if user has already claimed
        require(
            airdrop.claimed[investorIndex] < airdrop.allocations[msg.sender],
            "Already claimed full allocation"
        );

        uint256 claimableAmount = airdrop.currentAllocations[investorIndex];
        require(claimableAmount > 0, "Nothing left to claim");

        // Update state
        airdrop.claimed[investorIndex] += claimableAmount;
        airdrop.currentAllocations[investorIndex] = 0;

        // Check if all tokens have been claimed to mark airdrop as deleted
        bool canDelete = true;
        for (uint256 i = 0; i < airdrop.currentAllocations.length; i++) {
            if (airdrop.currentAllocations[i] > 0) {
                canDelete = false;
                break;
            }
        }

        if (canDelete) {
            airdrop.isDeleted = true;
            emit AirdropDeleted(
                _airdropId,
                address(airdrop.token),
                block.timestamp
            );
        }

        // Transfer tokens
        airdrop.token.safeTransfer(msg.sender, claimableAmount);

        emit TokenClaimed(
            msg.sender,
            _airdropId,
            claimableAmount,
            airdrop.claimed[investorIndex],
            airdrop.currentAllocations[investorIndex]
        );
    }

    /**
     * @dev Get airdrop information
     * @param _airdropId The ID of the airdrop
     * @return creator The address that created the airdrop
     * @return tokenAddress The address of the token being airdropped
     * @return totalAllocated Total amount of tokens allocated
     * @return startTime When the airdrop begins
     * @return isDeleted Whether the airdrop is deleted
     */
    function getAirdropInfo(
        uint256 _airdropId
    )
        public
        view
        returns (
            address creator,
            address tokenAddress,
            uint256 totalAllocated,
            uint256 startTime,
            bool isDeleted
        )
    {
        require(
            _airdropId > 0 && _airdropId <= lastAirdropId,
            "Invalid airdrop ID"
        );
        AirdropData storage airdrop = airdrops[_airdropId];
        return (
            airdrop.creator,
            address(airdrop.token),
            airdrop.totalAllocated,
            airdrop.startTime,
            airdrop.isDeleted
        );
    }

    function isAirdropDeleted(uint256 _airdropId) public view returns (bool) {
        require(
            _airdropId > 0 && _airdropId <= lastAirdropId,
            "Invalid airdrop ID"
        );
        return airdrops[_airdropId].isDeleted;
    }

    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyRole(ADMIN_ROLE) {}
}
