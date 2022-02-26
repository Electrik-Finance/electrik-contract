// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface ITreasury {
    function distributionEntries(address lp, uint256 index) external view returns (address);

    function distributionCount(address lp) external view returns (uint256);

    function claim(address user, address lp) external;
}
