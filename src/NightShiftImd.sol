// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title NightShiftImd
/// @notice Fixed-supply ERC-20. The deployer receives all one billion SHIFT at construction.
/// @dev The deployer is msg.sender (the launch factory when deployed through that factory).
/// There are no administrative roles or externally callable mint or burn functions.
contract NightShiftImd is ERC20 {
    /// @notice The entire supply in the token's 18-decimal base units.
    uint256 public constant INITIAL_SUPPLY = 1_000_000_000 * 10 ** 18;

    constructor() ERC20("NightShiftImd", "SHIFT") {
        _mint(msg.sender, INITIAL_SUPPLY);
    }
}
