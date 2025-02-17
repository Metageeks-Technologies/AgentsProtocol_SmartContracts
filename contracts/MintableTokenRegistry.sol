// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title MintableTokenRegistry
 * @dev A registry contract for managing mintable tokens with role-based access control
 * @notice This contract manages token configurations and minting permissions
 *
 * Features:
 * - Register and manage token configurations
 * - Role-based access control for administrative functions
 * - Manage minting permissions per account and token
 * - Track token supply limits
 * - Support for both ERC20 and NFT tokens
 * - Upgradeable contract architecture
 */

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

interface ISmartAccountFactory {
    function isValidSmartAccount(address account) external view returns (bool);
}

contract MintableTokenRegistry is
    Initializable,
    AccessControlUpgradeable,
    UUPSUpgradeable
{
    /**
     * @dev Role definitions for access control
     */
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");

    /**
     * @dev Struct to store token configuration data
     */
    struct TokenConfig {
        bool isActive;                // Whether the token is currently active
        bool requiresPayment;         // Whether minting requires payment
        uint256 mintPrice;           // Price to mint the token
        bool isNFT;                  // Whether the token is an NFT
        address paymentToken;        // Payment token address (address(0) for native)
        uint256 maxSupply;          // Maximum supply allowed
        uint256 currentSupply;      // Current supply
    }

    /**
     * @dev State variables
     */
    mapping(address => TokenConfig) public tokenConfigs;
    mapping(address => mapping(address => bool)) public accountMintPermissions;
    address[] public registeredTokens;

    /**
     * @dev Events
     */
    event TokenRegistered(
        address indexed token,
        bool isNFT,
        uint256 mintPrice
    );
    event TokenDeregistered(
        address indexed token
    );
    event MintPermissionUpdated(
        address indexed account,
        address indexed token,
        bool allowed
    );
    event MintPriceUpdated(
        address indexed token,
        uint256 newPrice
    );
    event BatchPermissionsSet(
        address indexed account
    );

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @dev Initializes the contract with role-based access control
     */
    function initialize() public initializer {
        __AccessControl_init();
        __UUPSUpgradeable_init();

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ADMIN_ROLE, msg.sender);
        _grantRole(OPERATOR_ROLE, msg.sender);
    }

    /**
     * @dev Registers a new token in the registry
     * @param token Address of the token contract
     * @param isNFT Whether the token is an NFT
     * @param requiresPayment Whether minting requires payment
     * @param mintPrice Price for minting
     * @param paymentToken Token used for payment
     * @param maxSupply Maximum supply allowed
     */
    function registerToken(
        address token,
        bool isNFT,
        bool requiresPayment,
        uint256 mintPrice,
        address paymentToken,
        uint256 maxSupply
    ) external onlyRole(ADMIN_ROLE) {
        require(token != address(0), "Invalid token address");
        require(!tokenConfigs[token].isActive, "Token already registered");

        tokenConfigs[token] = TokenConfig({
            isActive: true,
            requiresPayment: requiresPayment,
            mintPrice: mintPrice,
            isNFT: isNFT,
            paymentToken: paymentToken,
            maxSupply: maxSupply,
            currentSupply: 0
        });

        registeredTokens.push(token);
        emit TokenRegistered(token, isNFT, mintPrice);
    }

    /**
     * @dev Deregisters a token from the registry
     * @param token Address of the token to deregister
     */
    function deregisterToken(
        address token
    ) external onlyRole(ADMIN_ROLE) {
        require(tokenConfigs[token].isActive, "Token not registered");
        tokenConfigs[token].isActive = false;
        emit TokenDeregistered(token);
    }

    /**
     * @dev Updates the mint price for a token
     * @param token Address of the token
     * @param newPrice New mint price
     */
    function updateMintPrice(
        address token,
        uint256 newPrice
    ) external onlyRole(ADMIN_ROLE) {
        require(tokenConfigs[token].isActive, "Token not registered");
        tokenConfigs[token].mintPrice = newPrice;
        emit MintPriceUpdated(token, newPrice);
    }

    /**
     * @dev Sets minting permission for an account for a specific token
     * @param account Address of the account
     * @param token Address of the token
     * @param allowed Whether minting is allowed
     */
    function setAccountMintPermission(
        address account,
        address token,
        bool allowed
    ) external onlyRole(ADMIN_ROLE) {
        require(account != address(0), "Invalid account");
        require(token != address(0), "Invalid token");
        accountMintPermissions[account][token] = allowed;
        emit MintPermissionUpdated(account, token, allowed);
    }

    /**
     * @dev Increments the supply counter for a token
     * @param token Address of the token
     * @param amount Amount to increment
     */
    function incrementSupply(
        address token,
        uint256 amount
    ) external {
        require(
            msg.sender == token,
            "Only token contract can increment supply"
        );
        tokenConfigs[token].currentSupply += amount;
        require(
            tokenConfigs[token].currentSupply <= tokenConfigs[token].maxSupply,
            "Max supply exceeded"
        );
    }

    /**
     * @dev Checks if an account can mint a specific token
     * @param account Address of the account
     * @param token Address of the token
     * @return bool Whether the account can mint
     */
    function canMint(
        address account,
        address token
    ) public view returns (bool) {
        TokenConfig memory config = tokenConfigs[token];
        return config.isActive && accountMintPermissions[account][token];
    }

    /**
     * @dev Sets batch permissions for a smart account
     * @param account Address of the smart account
     */
    function batchSetPermissions(address account) external {
        require(
            ISmartAccountFactory(msg.sender).isValidSmartAccount(account),
            "Invalid account"
        );

        for (uint i = 0; i < registeredTokens.length; i++) {
            accountMintPermissions[account][registeredTokens[i]] = true;
        }
        emit BatchPermissionsSet(account);
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
    function grantOperatorRole(
        address operator
    ) external onlyRole(ADMIN_ROLE) {
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