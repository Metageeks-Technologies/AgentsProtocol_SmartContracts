// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title SmartAccountFactoryUpgradeable
 * @dev A factory contract for creating and managing upgradeable smart accounts with token permissions
 * @notice This contract manages the deployment and tracking of smart account proxies
 *
 * Features:
 * - Upgradeable contract architecture
 * - Proxy-based smart account deployment
 * - Token registry integration
 * - Account tracking system
 * - Permission management
 * - Role-based access control
 * - ETH receiving capability
 */

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "./SmartAccountUpgradeable.sol";
import "./interface/IMintableToken.sol";
import "./MintableTokenRegistry.sol";

contract SmartAccountFactoryUpgradeable is
    Initializable,
    UUPSUpgradeable,
    AccessControlUpgradeable
{
    /**
     * @dev Role definitions for access control
     */
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");

    /**
     * @dev State variables for account management
     */
    address payable public implementation;
    mapping(address => address) public accounts;
    mapping(address => bool) public isValidSmartAccount;

    /**
     * @dev Reference to the token registry for permission management
     */
    IMintableTokenRegistry public tokenRegistry;

    /**
     * @dev Events for tracking factory operations
     */
    event AccountCreated(address indexed owner, address indexed account);
    event ImplementationUpdated(address indexed newImplementation);
    event TokenRegistryUpdated(address indexed newRegistry);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @dev Initializes the factory with implementation and registry addresses
     * @param _implementation Address of the smart account implementation
     * @param _tokenRegistryAddress Address of the token registry contract
     */
    function initialize(
        address _implementation,
        address _tokenRegistryAddress
    ) public initializer {
        __AccessControl_init();
        __UUPSUpgradeable_init();

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ADMIN_ROLE, msg.sender);
        _grantRole(OPERATOR_ROLE, msg.sender);

        implementation = payable(_implementation);
        tokenRegistry = IMintableTokenRegistry(_tokenRegistryAddress);
    }

    /**
     * @dev Creates a new smart account for the specified owner
     * @param owner Address that will own the new smart account
     * @return address The address of the newly created smart account
     */
    function createAccount(address owner) external returns (address) {
        require(owner != address(0), "Invalid owner");
        require(accounts[owner] == address(0), "Account already exists");

        bytes memory initData = abi.encodeWithSelector(
            SmartAccountUpgradeable(implementation).initialize.selector,
            owner,
            address(tokenRegistry)
        );

        ERC1967Proxy proxy = new ERC1967Proxy(
            address(implementation),
            initData
        );

        address account = address(proxy);
        accounts[owner] = account;
        isValidSmartAccount[account] = true;

        tokenRegistry.batchSetPermissions(account);

        emit AccountCreated(owner, account);
        return account;
    }

    /**
     * @dev Updates the implementation contract address
     * @param _newImplementation Address of the new implementation
     */
    function updateImplementation(
        address _newImplementation
    ) external onlyRole(ADMIN_ROLE) {
        require(_newImplementation != address(0), "Invalid implementation");
        implementation = payable(_newImplementation);
        emit ImplementationUpdated(_newImplementation);
    }

    /**
     * @dev Updates the token registry contract address
     * @param _newRegistry Address of the new token registry
     */
    function updateTokenRegistry(address _newRegistry) external onlyRole(ADMIN_ROLE) {
        require(_newRegistry != address(0), "Invalid registry address");
        tokenRegistry = IMintableTokenRegistry(_newRegistry);
        emit TokenRegistryUpdated(_newRegistry);
    }

    /**
     * @dev Retrieves the smart account address for a given owner
     * @param owner Address of the account owner
     * @return address The smart account address associated with the owner
     */
    function getAccount(address owner) external view returns (address) {
        return accounts[owner];
    }

    /**
     * @dev Internal function to authorize contract upgrades
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
    function revokeOperatorRole(address operator) external onlyRole(ADMIN_ROLE) {
        _revokeRole(OPERATOR_ROLE, operator);
    }

    /**
     * @dev Fallback function to receive ETH transfers
     */
    receive() external payable {}
}