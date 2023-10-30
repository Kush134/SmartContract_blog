// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.7.6;
pragma abicoder v2;

// Lite Interface for IERC20Metadata
interface IERC20MetadataLite {
  function decimals() external view returns (uint8);
  function balanceOf(address account) external view returns (uint256);
}