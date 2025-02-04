// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IMintableToken {
    function mint(address to, uint256 amount) external returns (bool);

    function mintNFT(address to, uint256 tokenId) external returns (bool);

    function batchMint(uint256 quantity) external payable;

    function mintPrice() external view returns (uint256);

    function isNFT() external view returns (bool);
}

interface IERC20Mintable is IMintableToken {
    function totalSupply() external view returns (uint256);

    function balanceOf(address account) external view returns (uint256);

    function transfer(address to, uint256 amount) external returns (bool);

    function allowance(
        address owner,
        address spender
    ) external view returns (uint256);

    function approve(address spender, uint256 amount) external returns (bool);

    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) external returns (bool);
}

interface IERC721Mintable is IMintableToken {
    function balanceOf(address owner) external view returns (uint256);

    function ownerOf(uint256 tokenId) external view returns (address);

    function safeTransferFrom(
        address from,
        address to,
        uint256 tokenId
    ) external;

    function transferFrom(address from, address to, uint256 tokenId) external;

    function approve(address to, uint256 tokenId) external;

    function getApproved(uint256 tokenId) external view returns (address);

    function setApprovalForAll(address operator, bool approved) external;

    function isApprovedForAll(
        address owner,
        address operator
    ) external view returns (bool);
}
