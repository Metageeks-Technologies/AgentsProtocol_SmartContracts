// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/**
 * @title AirdropUpgradeable
 * @dev A contract for managing token airdrops with role-based access control
 * @notice This contract supports ERC20 token airdrops with configurable start times
 *
 * Features:
 * - Create token airdrops with specific allocation for each recipient
 * - Role-based access control for administrative functions
 * - Configurable start time for each airdrop
 * - Claim tracking per user
 * - Upgradeable contract architecture
 * - SafeERC20 implementation for secure token transfers
 * - Reentrancy protection
 * - Cleanup mechanism for completed airdrops
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

    /**
     * @dev Role definitions for access control
     */
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");

    /**
     * @dev Struct to store all data related to a single airdrop
     */
    struct AirdropData {
        IERC20 token; // Token being airdropped
        uint256 totalAllocated; // Total tokens allocated for this airdrop
        uint256 startTime; // Timestamp when claiming can begin
        uint256 airdropId; // Unique identifier for this airdrop
        bool isDeleted; // Flag to mark if airdrop is deleted after full claim
        address[] investors; // List of eligible investors
        uint256[] currentAllocations; // Current claimable amounts
        uint256[] claimed; // Amount claimed by each investor
        mapping(address => uint256) investorIndex; // Mapping of investor address to array index
        mapping(address => uint256) allocations; // Initial allocation for each investor
    }

    /**
     * @dev State variables for tracking airdrops
     */
    AirdropData[] public airdrops;
    uint256 public totalInvestors;

    /**
     * @dev Event emitted when a new airdrop is created
     */
    event AirdropCreated(
        address indexed creator,
        address tokenAddress,
        uint256 indexed airdropIndex,
        uint256 startTime,
        address[] investors,
        uint256[] amounts
    );

    /**
     * @dev Event emitted when tokens are claimed
     */
    event TokenClaimed(
        address indexed user,
        uint256 indexed airdropId,
        uint256 amount,
        uint256 claimedAmount,
        uint256 remainingAllocation
    );

    /**
     * @dev Event emitted when an airdrop is deleted after full claim
     */
    event AirdropDeleted(
        uint256 indexed airdropId,
        address tokenAddress,
        uint256 timestamp
    );

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @dev Initializes the contract setting the deployer as the initial admin
     */
    function initialize() public initializer {
        __AccessControl_init();
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ADMIN_ROLE, msg.sender);
        _grantRole(OPERATOR_ROLE, msg.sender);
    }

    /**
     * @dev Creates a new airdrop with specified allocations
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
    ) public onlyRole(OPERATOR_ROLE) {
        require(_tokenAddress != address(0), "Invalid token address");
        require(
            _addresses.length == _amounts.length,
            "Addresses and amounts length mismatch"
        );
        require(_startTime >= block.timestamp, "Start Time can't be in past");
        require(_addresses.length > 0, "Empty airdrop not allowed");

        uint256 totalTokensRequired = 0;
        for (uint256 i = 0; i < _amounts.length; i++) {
            require(_amounts[i] > 0, "Amount must be greater than 0");
            require(_addresses[i] != address(0), "Invalid address");
            totalTokensRequired += _amounts[i];
        }

        IERC20 token = IERC20(_tokenAddress);
        require(
            token.allowance(msg.sender, address(this)) >= totalTokensRequired,
            "Insufficient allowance"
        );

        // Transfer tokens first using SafeERC20
        token.safeTransferFrom(msg.sender, address(this), totalTokensRequired);

        // Then update state
        airdrops.push();
        AirdropData storage newAirdrop = airdrops[airdrops.length - 1];
        newAirdrop.token = token;
        newAirdrop.totalAllocated = totalTokensRequired;
        newAirdrop.startTime = _startTime;
        newAirdrop.airdropId = airdrops.length;
        newAirdrop.isDeleted = false;

        for (uint256 i = 0; i < _addresses.length; i++) {
            newAirdrop.investors.push(_addresses[i]);
            newAirdrop.currentAllocations.push(_amounts[i]);
            newAirdrop.claimed.push(0);
            newAirdrop.investorIndex[_addresses[i]] = i;
            newAirdrop.allocations[_addresses[i]] = _amounts[i];
        }

        totalInvestors += _addresses.length;

        emit AirdropCreated(
            msg.sender,
            _tokenAddress,
            airdrops.length - 1,
            _startTime,
            _addresses,
            _amounts
        );
    }

    /**
     * @dev Allows users to claim their allocated tokens
     * @param _airdropId ID of the airdrop to claim from
     * @param _amount Amount of tokens to claim
     */
    function claim(uint256 _airdropId, uint256 _amount) public nonReentrant {
        require(_airdropId < airdrops.length, "Invalid airdrop ID");

        AirdropData storage airdrop = airdrops[_airdropId];
        require(!airdrop.isDeleted, "Airdrop has been deleted");
        require(block.timestamp >= airdrop.startTime, "Airdrop not started");

        uint256 investorIndex = airdrop.investorIndex[msg.sender];
        require(
            airdrop.currentAllocations[investorIndex] > 0,
            "Nothing to claim"
        );

        require(_amount > 0, "Amount must be greater than 0");
        require(
            _amount <= airdrop.currentAllocations[investorIndex],
            "Amount exceeds allocation"
        );

        // Update state before transfer (Check-Effects-Interactions pattern)
        airdrop.claimed[investorIndex] += _amount;
        airdrop.currentAllocations[investorIndex] -= _amount;

        // Check if airdrop can be deleted (all tokens claimed)
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

        // Perform transfer after state updates
        airdrop.token.safeTransfer(msg.sender, _amount);

        emit TokenClaimed(
            msg.sender,
            _airdropId,
            _amount,
            airdrop.claimed[investorIndex],
            airdrop.currentAllocations[investorIndex]
        );
    }

    /**
     * @dev Returns whether an airdrop has been deleted
     * @param _airdropId The ID of the airdrop to check
     * @return bool Whether the airdrop has been deleted
     */
    function isAirdropDeleted(uint256 _airdropId) public view returns (bool) {
        require(_airdropId < airdrops.length, "Invalid airdrop ID");
        return airdrops[_airdropId].isDeleted;
    }

    /**
     * @dev Function that authorizes an upgrade to a new implementation
     * @param newImplementation Address of the new implementation
     */
    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyRole(ADMIN_ROLE) {}

    /**
     * @dev Grants OPERATOR_ROLE to an account
     * @param operator Address to grant the role to
     */
    function grantOperatorRole(address operator) external onlyRole(ADMIN_ROLE) {
        _grantRole(OPERATOR_ROLE, operator);
    }

    /**
     * @dev Revokes OPERATOR_ROLE from an account
     * @param operator Address to revoke the role from
     */
    function revokeOperatorRole(
        address operator
    ) external onlyRole(ADMIN_ROLE) {
        _revokeRole(OPERATOR_ROLE, operator);
    }
}