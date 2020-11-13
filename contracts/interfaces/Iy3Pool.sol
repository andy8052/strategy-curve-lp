// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

// NOTE: Basically an alias for Vaults
interface Iy3Pool {
    function deposit(uint256 _amount) external;

    function withdraw(uint256 _amount) external;

    function withdraw() external;

    function balanceOf(address _user) external view returns (uint256);

    function getPricePerFullShare() external view returns (uint256);

    function earn() external;
}