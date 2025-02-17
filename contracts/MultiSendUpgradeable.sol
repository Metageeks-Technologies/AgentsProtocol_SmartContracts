// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/**
 * @title MultiSendUpgradeable
 * @dev A contract for batch sending ERC20 tokens and native currency
 * @notice This contract supports both ERC20 token and native currency batch transfers
 * @custom Supports all EVM chains except SKALE chains for native transfers
 * 
 * Features:
 * - Batch send ERC20 tokens
 * - Batch send native currency (except on SKALE chains)
 * - Role-based access control for administrative functions
 * - Upgradeable contract architecture
 * - Emergency withdrawal functions for accidentally sent tokens/currency
 */

import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract MultiSendUpgradeable is
    Initializable,
    AccessControlUpgradeable,
    UUPSUpgradeable
{
    using SafeERC20 for IERC20;

    /**
     * @dev Counter for tracking multisend operations
     */
    uint256 private multiSendCounter;

    /**
     * @dev Role definitions for access control
     */
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");
    bytes32 public constant WITHDRAWER_ROLE = keccak256("WITHDRAWER_ROLE");

    /**
     * @dev SKALE Chain IDs for testnet environments
     */
    uint256 private constant SKALE_TITAN_TESTNET = 0x3CCFA93C;      // 1020352220
    uint256 private constant SKALE_EUROPA_TESTNET = 0x56057A8B;     // 1444673419
    uint256 private constant SKALE_NEBULA_TESTNET = 0x0235F410;     // 37084624
    uint256 private constant SKALE_CALYPSO_TESTNET = 0x3A0E468B;    // 974399131

    /**
     * @dev SKALE Chain IDs for mainnet environments
     */
    uint256 private constant SKALE_TITAN_MAINNET = 0x507aaa2a;
    uint256 private constant SKALE_EUROPA_MAINNET = 0x79f99296;
    uint256 private constant SKALE_NEBULA_MAINNET = 0x585eb4b1;
    uint256 private constant SKALE_CALYPSO_MAINNET = 0x5d456c62;

    /**
     * @dev Event emitted when a multisend operation is completed
     * @param creator Address that initiated the multisend
     * @param tokenAddress Address of the token sent (zero address for native currency)
     * @param multiSendIndex Unique identifier for this multisend operation
     * @param totalAmount Total amount of tokens/currency sent
     */
    event MultiSendCreated(
        address indexed creator,
        address tokenAddress,
        uint256 indexed multiSendIndex,
        uint256 totalAmount
    );

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @dev Initializes the contract setting the deployer as the initial admin
     * @notice Sets up all required roles and assigns them to the deployer
     */
    function initialize() public initializer {
        __AccessControl_init();
        __UUPSUpgradeable_init();

        // Setup roles
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ADMIN_ROLE, msg.sender);
        _grantRole(UPGRADER_ROLE, msg.sender);
        _grantRole(WITHDRAWER_ROLE, msg.sender);
    }

    /**
     * @dev Prevents accidental sending of native currency to contract
     */
    receive() external payable {
        revert("Direct deposits not allowed");
    }

    /**
     * @dev Internal function to check if current chain is a SKALE chain
     * @param chainId The chain ID to check
     * @return bool True if the chain is a SKALE chain, false otherwise
     */
    function _isSkaleChain(uint256 chainId) internal pure returns (bool) {
        return (
            chainId == SKALE_TITAN_TESTNET ||
            chainId == SKALE_EUROPA_TESTNET ||
            chainId == SKALE_NEBULA_TESTNET ||
            chainId == SKALE_CALYPSO_TESTNET ||
            chainId == SKALE_TITAN_MAINNET ||
            chainId == SKALE_EUROPA_MAINNET ||
            chainId == SKALE_NEBULA_MAINNET ||
            chainId == SKALE_CALYPSO_MAINNET
        );
    }

    /**
     * @dev Sends multiple ERC20 tokens to multiple addresses in a single transaction
     * @param token Address of the ERC20 token to send
     * @param ensureExactAmount If true, validates exact amount was transferred
     * @param targets Array of recipient addresses
     * @param amounts Array of amounts to send to each recipient
     * @param expectedTotal Expected total amount to be sent
     * @notice Requires approval for contract to spend tokens
     */
    function multisendToken(
        address token,
        bool ensureExactAmount,
        address[] calldata targets,
        uint256[] calldata amounts,
        uint256 expectedTotal
    ) external {
        require(token != address(0), "Invalid token address");
        require(targets.length == amounts.length, "Length mismatched");
        require(targets.length > 0, "Empty arrays");

        multiSendCounter++;
        IERC20 erc20 = IERC20(token);
        uint256 total = 0;

        // Calculate total first
        for (uint256 i = 0; i < amounts.length; i++) {
            require(amounts[i] > 0, "Amount must be greater than 0");
            require(targets[i] != address(0), "Invalid target address");
            total += amounts[i];
        }

        // Validate total matches expected
        require(total == expectedTotal, "Total amount mismatch");

        // Check if sender has sufficient balance
        require(erc20.balanceOf(msg.sender) >= total, "Insufficient balance");

        // Check if contract has sufficient allowance
        require(
            erc20.allowance(msg.sender, address(this)) >= total,
            "Insufficient allowance"
        );

        function(IERC20, address, address, uint256) transfer = ensureExactAmount
            ? _safeTransferFromEnsureExactAmount
            : _safeTransferFrom;

        // Perform transfers
        for (uint256 i = 0; i < targets.length; i++) {
            transfer(erc20, msg.sender, targets[i], amounts[i]);
        }

        emit MultiSendCreated(msg.sender, token, multiSendCounter, total);
    }

    /**
     * @dev Sends native currency to multiple addresses in a single transaction
     * @param targets Array of recipient addresses
     * @param amounts Array of amounts to send to each recipient
     * @notice Not available on SKALE chains due to gas token restrictions
     */
    function multisendNative(
        address[] calldata targets,
        uint256[] calldata amounts
    ) public payable {
        // Get current chain ID
        uint256 chainId;
        assembly {
            chainId := chainid()
        }

        // Check if current chain is a SKALE chain
        require(
            !_isSkaleChain(chainId),
            "Function not supported on SKALE chains"
        );

        require(targets.length == amounts.length, "Length mismatched");
        require(targets.length > 0, "Empty arrays");

        uint256 total = 0;
        for (uint256 i = 0; i < amounts.length; i++) {
            require(amounts[i] > 0, "Amount must be greater than 0");
            require(targets[i] != address(0), "Invalid target address");
            total += amounts[i];
        }

        require(total == msg.value, "Total mismatched");

        for (uint256 i = 0; i < targets.length; i++) {
            (bool success, ) = payable(targets[i]).call{value: amounts[i]}("");
            require(success, "Native transfer failed");
        }
    }

    /**
     * @dev Internal function for safe token transfer with amount validation
     * @param token The ERC20 token to transfer
     * @param from Address to transfer from
     * @param to Address to transfer to
     * @param amount Amount of tokens to transfer
     */
    function _safeTransferFromEnsureExactAmount(
        IERC20 token,
        address from,
        address to,
        uint256 amount
    ) private {
        uint256 balanceBefore = token.balanceOf(to);
        token.safeTransferFrom(from, to, amount);
        require(
            token.balanceOf(to) - balanceBefore == (from != to ? amount : 0),
            "Not enough tokens were transferred"
        );
    }

    /**
     * @dev Internal function for safe token transfer
     * @param token The ERC20 token to transfer
     * @param from Address to transfer from
     * @param to Address to transfer to
     * @param amount Amount of tokens to transfer
     */
    function _safeTransferFrom(
        IERC20 token,
        address from,
        address to,
        uint256 amount
    ) private {
        token.safeTransferFrom(from, to, amount);
    }

    /**
     * @dev Withdraws accidentally sent native currency
     * @param to Address to send the native currency to
     * @notice Only callable by addresses with WITHDRAWER_ROLE
     */
    function withdrawWronglySentNative(address to) external onlyRole(WITHDRAWER_ROLE) {
        require(to != address(0), "Invalid address");
        require(address(this).balance > 0, "No native currency to withdraw");
        (bool success, ) = payable(to).call{value: address(this).balance}("");
        require(success, "Native transfer failed");
    }

    /**
     * @dev Withdraws accidentally sent ERC20 tokens
     * @param token Address of the token to withdraw
     * @param to Address to send the tokens to
     * @notice Only callable by addresses with WITHDRAWER_ROLE
     */
    function withdrawWronglySentToken(
        address token,
        address to
    ) external onlyRole(WITHDRAWER_ROLE) {
        require(token != address(0), "Invalid token address");
        require(to != address(0), "Invalid address");
        uint256 balance = IERC20(token).balanceOf(address(this));
        require(balance > 0, "No tokens to withdraw");
        IERC20(token).safeTransfer(to, balance);
    }

    /**
     * @dev Function that authorizes an upgrade to a new implementation
     * @param newImplementation Address of the new implementation
     * @notice Only callable by addresses with UPGRADER_ROLE
     */
    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyRole(UPGRADER_ROLE) {}

    /**
     * @dev Grants WITHDRAWER_ROLE to an account
     * @param account Address to grant the role to
     * @notice Only callable by addresses with ADMIN_ROLE
     */
    function grantWithdrawerRole(address account) external onlyRole(ADMIN_ROLE) {
        grantRole(WITHDRAWER_ROLE, account);
    }

    /**
     * @dev Revokes WITHDRAWER_ROLE from an account
     * @param account Address to revoke the role from
     * @notice Only callable by addresses with ADMIN_ROLE
     */
    function revokeWithdrawerRole(address account) external onlyRole(ADMIN_ROLE) {
        revokeRole(WITHDRAWER_ROLE, account);
    }

    /**
     * @dev Grants UPGRADER_ROLE to an account
     * @param account Address to grant the role to
     * @notice Only callable by addresses with ADMIN_ROLE
     */
    function grantUpgraderRole(address account) external onlyRole(ADMIN_ROLE) {
        grantRole(UPGRADER_ROLE, account);
    }

    /**
     * @dev Revokes UPGRADER_ROLE from an account
     * @param account Address to revoke the role from
     * @notice Only callable by addresses with ADMIN_ROLE
     */
    function revokeUpgraderRole(address account) external onlyRole(ADMIN_ROLE) {
        revokeRole(UPGRADER_ROLE, account);
    }
}