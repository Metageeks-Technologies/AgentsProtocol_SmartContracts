// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

interface ISmartAccountFactory {
    function isValidSmartAccount(address account) external view returns (bool);
}

contract MintableTokenRegistry is
    Initializable,
    OwnableUpgradeable,
    UUPSUpgradeable
{
    struct TokenConfig {
        bool isActive;
        bool requiresPayment;
        uint256 mintPrice;
        bool isNFT;
        address paymentToken; // address(0) for native token
        uint256 maxSupply;
        uint256 currentSupply;
    }

    // Main storage
    mapping(address => TokenConfig) public tokenConfigs;
    mapping(address => mapping(address => bool)) public accountMintPermissions;
    address[] public registeredTokens;

    // Events
    event TokenRegistered(address indexed token, bool isNFT, uint256 mintPrice);
    event TokenDeregistered(address indexed token);
    event MintPermissionUpdated(
        address indexed account,
        address indexed token,
        bool allowed
    );
    event MintPriceUpdated(address indexed token, uint256 newPrice);
    event BatchPermissionsSet(address indexed account);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize() public initializer {
        __Ownable_init(msg.sender);
        __UUPSUpgradeable_init();
    }

    function registerToken(
        address token,
        bool isNFT,
        bool requiresPayment,
        uint256 mintPrice,
        address paymentToken,
        uint256 maxSupply
    ) external onlyOwner {
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

    function deregisterToken(address token) external onlyOwner {
        require(tokenConfigs[token].isActive, "Token not registered");
        tokenConfigs[token].isActive = false;
        emit TokenDeregistered(token);
    }

    function updateMintPrice(
        address token,
        uint256 newPrice
    ) external onlyOwner {
        require(tokenConfigs[token].isActive, "Token not registered");
        tokenConfigs[token].mintPrice = newPrice;
        emit MintPriceUpdated(token, newPrice);
    }

    function setAccountMintPermission(
        address account,
        address token,
        bool allowed
    ) external onlyOwner {
        require(account != address(0), "Invalid account");
        require(token != address(0), "Invalid token");
        accountMintPermissions[account][token] = allowed;
        emit MintPermissionUpdated(account, token, allowed);
    }

    function incrementSupply(address token, uint256 amount) external {
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

    function canMint(
        address account,
        address token
    ) public view returns (bool) {
        TokenConfig memory config = tokenConfigs[token];
        return config.isActive && accountMintPermissions[account][token];
    }

    function getTokenConfig(
        address token
    ) external view returns (TokenConfig memory) {
        return tokenConfigs[token];
    }

    function getAllRegisteredTokens() external view returns (address[] memory) {
        return registeredTokens;
    }

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

    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyOwner {}
}
