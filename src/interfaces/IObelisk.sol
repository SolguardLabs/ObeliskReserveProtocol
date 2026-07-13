// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

interface IERC20 {
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function allowance(address owner, address spender) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
    function approve(address spender, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}

interface IERC20Metadata is IERC20 {
    function name() external view returns (string memory);
    function symbol() external view returns (string memory);
    function decimals() external view returns (uint8);
}

interface IObeliskUSD is IERC20Metadata {
    function mint(address account, uint256 amount) external;
    function burn(uint256 amount) external;
    function burnFrom(address account, uint256 amount) external;
}

interface IReserveOracle {
    function getPrice(bytes32 oracleId) external view returns (uint256 price);
    function peekPrice(bytes32 oracleId)
        external
        view
        returns (uint256 price, uint48 updatedAt, bool valid);
}

interface IRedemptionSettlement {
    function fulfillRedemption(
        address asset,
        uint256 stableAmount,
        address receiver,
        uint256 minOut
    ) external returns (uint256 assetOut);
}

interface IBackstopProvider {
    function provide(address asset, uint256 amount, address receiver) external returns (uint256);
}
