// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract AirdropUpgradeable is Initializable, UUPSUpgradeable, OwnableUpgradeable {
    struct AirdropData {
        ERC20 token;
        uint256 totalAllocated;
        uint256 startTime;
        uint256 airdropId;
        bool isVesting;
        uint256 firstReleasePercentage;
        uint256 vestingPeriodInDays;
        uint256 cycleReleasePercentage;
        address[] investors;
        uint256[] currentAllocations;
        uint256[] claimed;
        mapping(address => uint256) investorIndex;
        mapping(address => uint256) allocations;
    }

    uint256 private airdropCounter;
    AirdropData[] private airdrops;
    uint256 public totalInvestors;
    mapping(address => uint256[]) private userAirdrops;
    mapping(address => uint256[]) private userInvested;

    event AirdropCreated(
        address indexed creator,
        address tokenAddress,
        uint256 indexed airdropIndex,
        uint256 startTime
    );

    event TokenClaimed(
        address indexed user,
        uint256 indexed amount,
        uint256 claimedAmount,
        uint256 indexed remainingAllocation
    );

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize() public initializer {
        __Ownable_init(msg.sender);
        __UUPSUpgradeable_init();
        airdropCounter = 0;
        totalInvestors = 0;
    }

    function returnLength() external view returns (uint256) {
        return airdrops.length;
    }

    function getAirdropInvestors(
        uint256 _airdropId
    ) external view returns (address[] memory, uint256[] memory) {
        AirdropData storage airdrop = airdrops[_airdropId];
        return (airdrop.investors, airdrop.currentAllocations);
    }

    function getTotalInvestors() external view returns (uint256) {
        return totalInvestors;
    }

    function getUserAirdops(
        address _user
    ) external view returns (uint256[] memory) {
        return userAirdrops[_user];
    }

    function getUserInvested(
        address _user
    ) external view returns (uint256[] memory) {
        return userInvested[_user];
    }

    function getAllocation(
        uint256 _airdropId,
        address _user
    ) external view returns (uint256) {
        AirdropData storage airdrop = airdrops[_airdropId];
        return airdrop.allocations[_user];
    }

    function getClaimed(
        uint256 _airdropId,
        address _user
    ) external view returns (uint256) {
        AirdropData storage airdrop = airdrops[_airdropId];
        uint256 investorIndex = airdrop.investorIndex[_user];
        return airdrop.claimed[investorIndex];
    }

    function createAirdrop(
        address _tokenAddress,
        address[] memory _addresses,
        uint256[] memory _amounts,
        uint256 _startTime,
        bool _isVesting,
        uint256 _firstReleasePercentage,
        uint256 _vestingPeriodInDays,
        uint256 _cycleReleasePercentage
    ) public {
        require(
            _addresses.length == _amounts.length,
            "Addresses and amounts length mismatch"
        );
        require(_startTime >= block.timestamp, "Start Time can't be in past");
        require(
            _firstReleasePercentage + _cycleReleasePercentage <= 100,
            "Invalid Release %"
        );

        airdropCounter++;
        uint256 totalTokensRequired = 0;
        for (uint256 i = 0; i < _amounts.length; i++) {
            totalTokensRequired += _amounts[i];
        }
        
        ERC20 token = ERC20(_tokenAddress);
        require(
            token.allowance(msg.sender, address(this)) >= totalTokensRequired,
            "Check the token allowance"
        );

        token.transferFrom(msg.sender, address(this), totalTokensRequired);

        airdrops.push();
        AirdropData storage newAirdrop = airdrops[airdrops.length - 1];
        newAirdrop.token = token;
        newAirdrop.totalAllocated = totalTokensRequired;
        newAirdrop.startTime = _startTime;
        newAirdrop.isVesting = _isVesting;
        newAirdrop.airdropId = airdropCounter;
        newAirdrop.firstReleasePercentage = _firstReleasePercentage;
        newAirdrop.vestingPeriodInDays = _vestingPeriodInDays;
        newAirdrop.cycleReleasePercentage = _cycleReleasePercentage;

        for (uint256 i = 0; i < _addresses.length; i++) {
            newAirdrop.investors.push(_addresses[i]);
            newAirdrop.currentAllocations.push(_amounts[i]);
            newAirdrop.claimed.push(0);
            newAirdrop.investorIndex[_addresses[i]] = i;
            newAirdrop.allocations[_addresses[i]] = _amounts[i];
            userInvested[_addresses[i]].push(airdrops.length - 1);
        }

        totalInvestors += _addresses.length;
        userAirdrops[msg.sender].push(airdrops.length - 1);

        emit AirdropCreated(
            msg.sender,
            _tokenAddress,
            airdropCounter,
            _startTime
        );
    }

    function claim(uint256 _airdropId, uint256 _amount) public {
        AirdropData storage airdrop = airdrops[_airdropId];
        require(block.timestamp >= airdrop.startTime, "Airdrop not started");
        uint256 investorIndex = airdrop.investorIndex[msg.sender];
        require(
            airdrop.currentAllocations[investorIndex] > 0,
            "Nothing to claim"
        );

        uint256 maxClaimable;
        if (airdrop.isVesting) {
            if (airdrop.claimed[investorIndex] == 0) {
                maxClaimable =
                    (airdrop.currentAllocations[investorIndex] *
                        airdrop.firstReleasePercentage) /
                    100;
            } else {
                uint256 daysSinceStart = (block.timestamp - airdrop.startTime) /
                    60 /
                    60 /
                    24;
                uint256 cyclesSinceStart = daysSinceStart /
                    airdrop.vestingPeriodInDays;
                maxClaimable =
                    (airdrop.currentAllocations[investorIndex] *
                        airdrop.cycleReleasePercentage *
                        cyclesSinceStart) /
                    100 -
                    airdrop.claimed[investorIndex];
            }
        } else {
            maxClaimable = airdrop.currentAllocations[investorIndex];
        }

        require(maxClaimable > 0, "No tokens available to claim");
        require(_amount > 0, "Amount must be greater than 0");
        require(_amount <= maxClaimable, "Amount exceeds claimable tokens");
        require(
            _amount <= airdrop.currentAllocations[investorIndex],
            "Amount exceeds allocation"
        );

        airdrop.token.transfer(msg.sender, _amount);
        airdrop.claimed[investorIndex] += _amount;
        airdrop.currentAllocations[investorIndex] -= _amount;
        
        emit TokenClaimed(
            msg.sender,
            _amount,
            airdrop.claimed[investorIndex],
            airdrop.currentAllocations[investorIndex]
        );
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}
}