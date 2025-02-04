// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";
import "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "./interface/IMintableToken.sol";
import "./MintableTokenRegistryUpgradeable.sol";

// import "@openzeppelin/contracts/token/ERC20/presets/ERC20PresetMinterPauser.sol";
interface IMintableTokenRegistry {
    struct TokenConfig {
        bool isActive;
        bool requiresPayment;
        uint256 mintPrice;
        bool isNFT;
        address paymentToken;
        uint256 maxSupply;
        uint256 currentSupply;
    }

    function getTokenConfig(
        address token
    ) external view returns (TokenConfig memory);

    function canMint(
        address account,
        address token
    ) external view returns (bool);

    function batchSetPermissions(address account) external;
}

/**
 * @title SmartAccountUpgradeable
 * @dev Upgradeable smart contract wallet with social recovery and token minting
 */

contract SmartAccountUpgradeable is
    Initializable,
    ReentrancyGuardUpgradeable,
    UUPSUpgradeable,
    OwnableUpgradeable
{
    IMintableTokenRegistry public tokenRegistry;

    // Guardian Struct
    struct Guardian {
        address addr;
        string socialType; // "google", "twitter", "linkedin"
        bool isActive;
    }

    // Token Minting Permission Struct
    struct TokenMintPermission {
        address tokenContract;
        uint256 maxMintAmount;
        bool isAllowed;
    }

    struct TokenConfig {
        bool isActive;
        bool requiresPayment;
        uint256 mintPrice;
        bool isNFT;
        address paymentToken;
        uint256 maxSupply;
        uint256 currentSupply;
    }

    // Mappings
    mapping(address => Guardian) public guardians;
    address[] public guardianList;
    mapping(address => TokenMintPermission) public mintPermissions;

    // State Variables
    uint256 public nonce;
    uint256 public required; // Required number of guardians for recovery

    // Events
    event Received(address indexed sender, uint256 amount);
    event TransactionExecuted(address indexed to, uint256 value, bytes data);
    event GuardianAdded(address indexed guardian, string socialType);
    event GuardianRemoved(address indexed guardian);
    event TokenMinted(
        address indexed token,
        address indexed recipient,
        uint256 amount
    );
    event MintPermissionAdded(address indexed token, uint256 maxMintAmount);
    event MintPermissionRemoved(address indexed token);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address initialOwner,
        address _tokenRegistry
    ) public initializer {
        __ReentrancyGuard_init();
        __Ownable_init(initialOwner);
        __UUPSUpgradeable_init();

        tokenRegistry = IMintableTokenRegistry(_tokenRegistry);
        required = 2;
    }

    receive() external payable {
        emit Received(msg.sender, msg.value);
    }

    /**
     * @dev Execute a transaction
     */
    function execute(
        address to,
        uint256 value,
        bytes calldata data
    ) external onlyOwner nonReentrant {
        require(to != address(0), "Invalid address");

        (bool success, ) = to.call{value: value}(data);
        require(success, "Transaction failed");

        emit TransactionExecuted(to, value, data);
    }

    /**
     * @dev Add a social guardian
     */
    function addGuardian(
        address _guardian,
        string memory _socialType
    ) external onlyOwner {
        require(_guardian != address(0), "Invalid guardian");
        require(!guardians[_guardian].isActive, "Already guardian");

        guardians[_guardian] = Guardian({
            addr: _guardian,
            socialType: _socialType,
            isActive: true
        });
        guardianList.push(_guardian);

        emit GuardianAdded(_guardian, _socialType);
    }

    /**
     * @dev Remove a guardian
     */
    function removeGuardian(address _guardian) external onlyOwner {
        require(guardians[_guardian].isActive, "Not a guardian");
        guardians[_guardian].isActive = false;

        // Remove from list
        for (uint i = 0; i < guardianList.length; i++) {
            if (guardianList[i] == _guardian) {
                guardianList[i] = guardianList[guardianList.length - 1];
                guardianList.pop();
                break;
            }
        }

        emit GuardianRemoved(_guardian);
    }

    /**
     * @dev Recover account ownership
     */
    function recoverAccount(
        address newOwner,
        bytes[] calldata signatures
    ) external {
        require(signatures.length >= required, "Not enough signatures");
        require(newOwner != address(0), "Invalid new owner");

        // Create message hash using MessageHashUtils
        bytes32 message = keccak256(abi.encodePacked(newOwner, nonce++));
        bytes32 messageHash = MessageHashUtils.toEthSignedMessageHash(message);

        address[] memory recoveredGuardians = new address[](signatures.length);
        uint256 validSignatures = 0;

        for (uint i = 0; i < signatures.length; i++) {
            address recovered = recoverSigner(messageHash, signatures[i]);
            require(guardians[recovered].isActive, "Invalid guardian");

            for (uint j = 0; j < validSignatures; j++) {
                require(
                    recovered != recoveredGuardians[j],
                    "Duplicate signature"
                );
            }

            recoveredGuardians[validSignatures] = recovered;
            validSignatures++;
        }

        require(validSignatures >= required, "Not enough valid signatures");
        _transferOwnership(newOwner);
    }

    /**
     * @dev Helper function to recover signer from signature
     */
    function recoverSigner(
        bytes32 hash,
        bytes memory signature
    ) internal pure returns (address) {
        bytes32 r;
        bytes32 s;
        uint8 v;

        if (signature.length != 65) {
            revert("Invalid signature length");
        }

        assembly {
            r := mload(add(signature, 32))
            s := mload(add(signature, 64))
            v := byte(0, mload(add(signature, 96)))
        }

        if (v < 27) {
            v += 27;
        }

        if (v != 27 && v != 28) {
            revert("Invalid signature 'v' value");
        }

        // Use ecrecover
        address recovered = ecrecover(hash, v, r, s);
        require(recovered != address(0), "Invalid signature");

        return recovered;
    }

    /**
     * @dev Transfer ERC20 tokens
     */
    function transferERC20(
        address token,
        address to,
        uint256 amount
    ) external onlyOwner {
        require(IERC20(token).transfer(to, amount), "Transfer failed");
    }

    /**
     * @dev Get all active guardians
     */
    function getGuardians()
        external
        view
        returns (address[] memory, string[] memory)
    {
        uint256 count = 0;
        for (uint i = 0; i < guardianList.length; i++) {
            if (guardians[guardianList[i]].isActive) {
                count++;
            }
        }

        address[] memory addresses = new address[](count);
        string[] memory types = new string[](count);
        uint256 index = 0;

        for (uint i = 0; i < guardianList.length; i++) {
            if (guardians[guardianList[i]].isActive) {
                addresses[index] = guardianList[i];
                types[index] = guardians[guardianList[i]].socialType;
                index++;
            }
        }

        return (addresses, types);
    }

    /**
     * @dev Mint tokens for a specific token contract
     */
    function mintTokens(
        address _token,
        uint256 _amount,
        address _recipient
    ) external onlyOwner nonReentrant {
        // Retrieve mint permission
        TokenMintPermission memory permission = mintPermissions[_token];

        // Validate mint permission
        require(permission.isAllowed, "Minting not allowed for this token");
        require(
            _amount <= permission.maxMintAmount,
            "Mint amount exceeds allowed limit"
        );

        // Attempt to mint tokens
        try IMintableToken(_token).mint(_recipient, _amount) {
            emit TokenMinted(_token, _recipient, _amount);
        } catch {
            revert("Token minting failed");
        }
    }

    /**
     * @dev Remove mint permission for a token
     */
    function removeMintPermission(address _token) external onlyOwner {
        delete mintPermissions[_token];
        emit MintPermissionRemoved(_token);
    }

    /**
     * @dev Get current mint permission for a token
     */
    function getMintPermission(
        address _token
    ) external view returns (TokenMintPermission memory) {
        return mintPermissions[_token];
    }

    // Add this function to validate if a token is mintable
    function validateMintableToken(
        address _token
    ) internal view returns (bool) {
        try IERC20Metadata(_token).totalSupply() returns (uint256) {
            return true;
        } catch {
            return false;
        }
    }

    /**
     * @dev Add mint permission for a specific token
     */
    function addMintPermission(
        address _token,
        uint256 _maxMintAmount
    ) external onlyOwner {
        require(_token != address(0), "Invalid token address");
        require(validateMintableToken(_token), "Not a valid ERC20 token");

        mintPermissions[_token] = TokenMintPermission({
            tokenContract: _token,
            maxMintAmount: _maxMintAmount,
            isAllowed: true
        });

        emit MintPermissionAdded(_token, _maxMintAmount);
    }

    /**
     * @dev Mint tokens or NFTs based on registry configuration
     */
    function mint(
        address token,
        uint256 amount,
        uint256 tokenId
    ) external payable onlyOwner nonReentrant {
        IMintableTokenRegistry.TokenConfig memory config = tokenRegistry
            .getTokenConfig(token);
        require(config.isActive, "Token not active");
        require(
            tokenRegistry.canMint(address(this), token),
            "Minting not allowed"
        );

        if (config.requiresPayment) {
            if (config.paymentToken == address(0)) {
                // Native token payment
                require(
                    address(this).balance >= config.mintPrice,
                    "Insufficient balance"
                );
                (bool success, ) = token.call{value: config.mintPrice}("");
                require(success, "Payment failed");
            } else {
                // ERC20 payment
                IERC20(config.paymentToken).transfer(token, config.mintPrice);
            }
        }

        if (config.isNFT) {
            require(
                IERC721Mintable(token).mintNFT(msg.sender, tokenId),
                "NFT mint failed"
            );
        } else {
            require(
                IERC20Mintable(token).mint(msg.sender, amount),
                "Token mint failed"
            );
        }
    }

    /**
     * @dev Batch mint NFTs
     */

    function batchMintNFT(
        address token,
        uint256 quantity // Changed from tokenIds array to quantity
    ) external payable onlyOwner nonReentrant {
        IMintableTokenRegistry.TokenConfig memory config = tokenRegistry
            .getTokenConfig(token);
        require(config.isActive && config.isNFT, "Invalid NFT token");
        require(
            tokenRegistry.canMint(address(this), token),
            "Minting not allowed"
        );

        // Handle payment if required
        if (config.requiresPayment) {
            uint256 totalCost = config.mintPrice * quantity;
            if (config.paymentToken == address(0)) {
                require(
                    msg.value >= totalCost, // Check msg.value instead of balance
                    "Insufficient payment"
                );
            } else {
                IERC20(config.paymentToken).transferFrom(
                    msg.sender,
                    token,
                    totalCost
                ); // Use transferFrom
            }
        }

        // Call the batchMint function with quantity
        IMintableToken(token).batchMint(quantity);
    }

    function mintNFT(
        address token,
        uint256[] calldata tokenIds
    ) external payable onlyOwner nonReentrant {
        IMintableTokenRegistry.TokenConfig memory config = tokenRegistry
            .getTokenConfig(token);
        require(config.isActive && config.isNFT, "Invalid NFT token");
        require(
            tokenRegistry.canMint(address(this), token),
            "Minting not allowed"
        );

        if (config.requiresPayment) {
            uint256 totalCost = config.mintPrice * tokenIds.length;
            if (config.paymentToken == address(0)) {
                require(
                    address(this).balance >= totalCost,
                    "Insufficient balance"
                );
                (bool success, ) = token.call{value: totalCost}("");
                require(success, "Payment failed");
            } else {
                IERC20(config.paymentToken).transfer(token, totalCost);
            }
        }

        // Mint each token individually using mintNFT
        for (uint256 i = 0; i < tokenIds.length; i++) {
            require(
                IMintableToken(token).mintNFT(msg.sender, tokenIds[i]),
                "NFT mint failed"
            );
        }
    }

    /**
     * @dev Required override for UUPSUpgradeable
     */
    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyOwner {}
}
