// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "./SmartAccountUpgradeable.sol";
import "./interface/IMintableToken.sol";
import "./MintableTokenRegistryUpgradeable.sol";

contract SmartAccountFactoryUpgradeable is
    Initializable,
    UUPSUpgradeable,
    OwnableUpgradeable
{
    address payable public implementation;
    mapping(address => address) public accounts;
    mapping(address => bool) public isValidSmartAccount;

    // Reference to the token registry
    IMintableTokenRegistry public tokenRegistry;

    event AccountCreated(address indexed owner, address indexed account);
    event ImplementationUpdated(address indexed newImplementation);
    event TokenRegistryUpdated(address indexed newRegistry);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address _implementation,
        address _tokenRegistryAddress
    ) public initializer {
        __Ownable_init(msg.sender);
        __UUPSUpgradeable_init();

        implementation = payable(_implementation);
        tokenRegistry = IMintableTokenRegistry(_tokenRegistryAddress);
    }

    function createAccount(address owner) external returns (address) {
        require(owner != address(0), "Invalid owner");
        require(accounts[owner] == address(0), "Account already exists");

        bytes memory initData = abi.encodeWithSelector(
            SmartAccountUpgradeable(implementation).initialize.selector,
            owner,
            address(tokenRegistry) // Add token registry address
        );

        ERC1967Proxy proxy = new ERC1967Proxy(
            address(implementation),
            initData
        );

        address account = address(proxy);
        accounts[owner] = account;
        isValidSmartAccount[account] = true;

        // Batch set permissions in registry
        tokenRegistry.batchSetPermissions(account);

        emit AccountCreated(owner, account);
        return account;
    }

    /**
     * @dev Update the implementation contract
     */
    function updateImplementation(
        address _newImplementation
    ) external onlyOwner {
        require(_newImplementation != address(0), "Invalid implementation");
        implementation = payable(_newImplementation);
        emit ImplementationUpdated(_newImplementation);
    }

    /**
     * @dev Update the token registry address
     */
    function updateTokenRegistry(address _newRegistry) external onlyOwner {
        require(_newRegistry != address(0), "Invalid registry address");
        tokenRegistry = IMintableTokenRegistry(_newRegistry);
        emit TokenRegistryUpdated(_newRegistry);
    }

    /**
     * @dev Get account for a specific owner
     */
    function getAccount(address owner) external view returns (address) {
        return accounts[owner];
    }

    /**
     * @dev Authorize contract upgrade
     */
    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyOwner {}

    /**
     * @dev Fallback to receive ETH
     */
    receive() external payable {}
}
