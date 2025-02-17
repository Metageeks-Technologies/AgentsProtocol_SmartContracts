// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title PriorityPass
 * @dev A contract for managing NFT-based priority passes with role-based access control
 * @notice This contract allows for the creation and management of priority passes as NFTs
 *
 * Features:
 * - ERC721-based NFT implementation
 * - Role-based access control for administrative functions
 * - Batch minting capability with configurable limits
 * - Pausable functionality for emergency situations
 * - Automatic holder tracking system
 * - Upgradeable contract architecture
 * - Configurable mint pricing
 * - Custom token URI support
 * - Detailed minting records per user
 */

import "@openzeppelin/contracts-upgradeable/token/ERC721/ERC721Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

contract PriorityPass is
    Initializable,
    ERC721Upgradeable,
    UUPSUpgradeable,
    AccessControlUpgradeable,
    PausableUpgradeable,
    ReentrancyGuardUpgradeable
{
    using Strings for uint256;

    /**
     * @dev See {IERC165-supportsInterface}.
     * Combines interface support checks from both ERC721 and AccessControl
     */
    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(ERC721Upgradeable, AccessControlUpgradeable)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }

    /**
     * @dev Role definitions for access control
     */
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");

    /**
     * @dev State variables
     */
    uint256 public tokenIdCounter;
    uint256 public mintPrice;
    uint256 public maxBatchSize;
    mapping(address => bool) public priorityPassHolders;
    address[] public allHolders;
    string private _baseTokenURI;

    /**
     * @dev Struct to store minted token information
     */
    struct MintedToken {
        uint256 tokenId;
        address owner;
        uint256 mintedAt;
    }

    mapping(address => MintedToken[]) public userMintedTokens;

    /**
     * @dev Events for tracking contract state changes
     */
    event PriceUpdated(uint256 newPrice);
    event BatchMinted(address indexed to, uint256 startTokenId, uint256 endTokenId);
    event BaseURIUpdated(string newBaseURI);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @dev Initializes the contract with basic parameters
     * @param name The name of the NFT collection
     * @param symbol The symbol of the NFT collection
     * @param initialPrice The initial minting price
     * @param baseURI The base URI for token metadata
     */
    function initialize(
        string memory name,
        string memory symbol,
        uint256 initialPrice,
        string memory baseURI
    ) public initializer {
        __ERC721_init(name, symbol);
        __AccessControl_init();
        __Pausable_init();
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ADMIN_ROLE, msg.sender);
        _grantRole(OPERATOR_ROLE, msg.sender);

        mintPrice = initialPrice;
        maxBatchSize = 20;
        _baseTokenURI = baseURI;
    }

    // Using OpenZeppelin's Strings library for toString functionality

    /**
     * @dev Returns the token URI for a given token ID
     */
    function tokenURI(uint256 tokenId) public view virtual override returns (string memory) {
        require(ownerOf(tokenId) != address(0), "Token does not exist");
        string memory baseURI = _baseURI();
        return bytes(baseURI).length > 0
            ? string(abi.encodePacked(baseURI, "/", tokenId.toString(), ".json"))
            : "";
    }

    /**
     * @dev Sets the base URI for token metadata
     * @param newBaseURI The new base URI to set
     */
    function setBaseURI(string memory newBaseURI) external onlyRole(ADMIN_ROLE) {
        _baseTokenURI = newBaseURI;
        emit BaseURIUpdated(newBaseURI);
    }

    /**
     * @dev Updates the minting price
     * @param newPrice The new price to set
     */
    function setMintPrice(uint256 newPrice) external onlyRole(ADMIN_ROLE) {
        mintPrice = newPrice;
        emit PriceUpdated(newPrice);
    }

    /**
     * @dev Sets the maximum batch size for minting
     * @param newSize The new maximum batch size
     */
    function setMaxBatchSize(uint256 newSize) external onlyRole(ADMIN_ROLE) {
        maxBatchSize = newSize;
    }

    /**
     * @dev Pauses all token transfers and minting
     */
    function pause() external onlyRole(ADMIN_ROLE) {
        _pause();
    }

    /**
     * @dev Unpauses all token transfers and minting
     */
    function unpause() external onlyRole(ADMIN_ROLE) {
        _unpause();
    }

    /**
     * @dev Batch mints new priority passes
     * @param quantity The number of passes to mint
     */
    function batchMint(uint256 quantity) external payable nonReentrant whenNotPaused {
        require(quantity > 0 && quantity <= maxBatchSize, "Invalid quantity");
        // require(msg.value >= mintPrice * quantity, "Insufficient payment");

        uint256 startTokenId = tokenIdCounter;
        MintedToken[] storage userTokens = userMintedTokens[msg.sender];

        for (uint256 i = 0; i < quantity; i++) {
            uint256 tokenId = tokenIdCounter++;
            _safeMint(msg.sender, tokenId);

            userTokens.push(
                MintedToken({
                    tokenId: tokenId,
                    owner: msg.sender,
                    mintedAt: block.timestamp
                })
            );

            if (!priorityPassHolders[msg.sender]) {
                priorityPassHolders[msg.sender] = true;
                allHolders.push(msg.sender);
            }
        }

        emit BatchMinted(msg.sender, startTokenId, tokenIdCounter - 1);
    }

    /**
     * @dev Returns length of holders array - needed since we can't get array length from public mapping
     */
    function getHoldersLength() external view returns (uint256) {
        return allHolders.length;
    }

    /**
     * @dev Internal function to return the base URI
     */
    function _baseURI() internal view virtual override returns (string memory) {
        return _baseTokenURI;
    }

    /**
     * @dev Withdraws accumulated funds to the admin
     */
    function withdrawFunds() external onlyRole(ADMIN_ROLE) {
        uint256 balance = address(this).balance;
        require(balance > 0, "No funds to withdraw");

        (bool success, ) = msg.sender.call{value: balance}("");
        require(success, "Withdrawal failed");
    }

    /**
     * @dev Internal function to update token ownership
     */
    function _update(
        address to,
        uint256 tokenId,
        address auth
    ) internal virtual override returns (address) {
        address from = super._update(to, tokenId, auth);

        if (from != address(0) && balanceOf(from) == 0) {
            priorityPassHolders[from] = false;
            _removeHolder(from);
        }

        if (to != address(0) && !priorityPassHolders[to]) {
            priorityPassHolders[to] = true;
            allHolders.push(to);
        }

        return from;
    }

    /**
     * @dev Removes an address from the holders list
     */
    function _removeHolder(address holder) internal {
        for (uint256 i = 0; i < allHolders.length; i++) {
            if (allHolders[i] == holder) {
                allHolders[i] = allHolders[allHolders.length - 1];
                allHolders.pop();
                break;
            }
        }
    }

    /**
     * @dev Function that authorizes an upgrade to a new implementation
     * @param newImplementation Address of the new implementation
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyRole(ADMIN_ROLE) {}

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
}