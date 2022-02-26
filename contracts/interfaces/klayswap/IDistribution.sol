// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IDistribution {
    function estimateEndBlock() external view returns (uint256);

    function token() external view returns (address);

    function userLastIndex(address lp, address user) external view returns (uint256);

    function distributionIndex(address lp) external view returns (uint256);

    function userRewardSum(address lp, address user) external view returns (uint256);

    function distributionRate(address lp) external view returns (uint256);

    function blockAmount() external view returns (uint256);
}
