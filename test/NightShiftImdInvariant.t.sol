// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {NightShiftImd} from "../src/NightShiftImd.sol";

/// @dev Independent ledger for randomized successful and failing ERC-20 operations.
contract TokenHandler is Test {
    uint256 private constant SUPPLY = 1_000_000_000 * 1e18;
    NightShiftImd private immutable token;
    address[4] private actors;
    mapping(address => uint256) public expectedBalance;
    mapping(address => mapping(address => uint256)) public expectedAllowance;

    constructor(NightShiftImd token_, address[4] memory actors_) {
        token = token_;
        actors = actors_;
        expectedBalance[actors_[0]] = SUPPLY;
    }

    function transfer(uint256 fromSeed, uint256 toSeed, uint256 amountSeed, bool validAmount) external {
        address from = actors[fromSeed % actors.length];
        address to = _recipient(toSeed);
        uint256 amount = bound(amountSeed, 0, validAmount ? expectedBalance[from] : SUPPLY + 1);
        bool expectedSuccess = to != address(0) && amount <= expectedBalance[from];

        vm.prank(from);
        (bool success, bytes memory result) = address(token).call(abi.encodeCall(token.transfer, (to, amount)));
        assertEq(success, expectedSuccess, "transfer authorization differs from ledger");
        if (success) {
            assertTrue(abi.decode(result, (bool)));
            expectedBalance[from] -= amount;
            expectedBalance[to] += amount;
        }
    }

    function approve(uint256 ownerSeed, uint256 spenderSeed, uint256 amountSeed, bool unlimited) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = _recipient(spenderSeed);
        uint256 amount = unlimited ? type(uint256).max : bound(amountSeed, 0, SUPPLY);

        vm.prank(owner);
        (bool success, bytes memory result) = address(token).call(abi.encodeCall(token.approve, (spender, amount)));
        assertEq(success, spender != address(0), "approval authorization differs from ledger");
        if (success) {
            assertTrue(abi.decode(result, (bool)));
            expectedAllowance[owner][spender] = amount;
        }
    }

    function transferFrom(uint256 spenderSeed, uint256 fromSeed, uint256 toSeed, uint256 amountSeed, bool validAmount)
        external
    {
        address spender = actors[spenderSeed % actors.length];
        address from = actors[fromSeed % actors.length];
        address to = _recipient(toSeed);
        uint256 allowance = expectedAllowance[from][spender];
        uint256 balance = expectedBalance[from];
        uint256 limit = allowance < balance ? allowance : balance;
        uint256 amount = bound(amountSeed, 0, validAmount ? limit : SUPPLY + 1);
        bool expectedSuccess = to != address(0) && amount <= balance && amount <= allowance;

        vm.prank(spender);
        (bool success, bytes memory result) =
            address(token).call(abi.encodeCall(token.transferFrom, (from, to, amount)));
        assertEq(success, expectedSuccess, "delegated transfer authorization differs from ledger");
        if (success) {
            assertTrue(abi.decode(result, (bool)));
            expectedBalance[from] -= amount;
            expectedBalance[to] += amount;
            if (allowance != type(uint256).max) {
                expectedAllowance[from][spender] -= amount;
            }
        }
    }

    function _recipient(uint256 seed) private view returns (address) {
        uint256 index = seed % (actors.length + 1);
        return index == actors.length ? address(0) : actors[index];
    }
}

contract NightShiftImdInvariantTest is Test {
    uint256 private constant SUPPLY = 1_000_000_000 * 1e18;
    NightShiftImd private token;
    TokenHandler private handler;
    address[4] private actors;

    function setUp() public {
        actors = [makeAddr("actor zero"), makeAddr("actor one"), makeAddr("actor two"), makeAddr("actor three")];
        vm.prank(actors[0]);
        token = new NightShiftImd();
        handler = new TokenHandler(token, actors);

        bytes4[] memory selectors = new bytes4[](3);
        selectors[0] = TokenHandler.transfer.selector;
        selectors[1] = TokenHandler.approve.selector;
        selectors[2] = TokenHandler.transferFrom.selector;
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
        targetContract(address(handler));
    }

    function invariant_supplyIsFixedAndFullyAccountedFor() public view {
        uint256 held;
        for (uint256 i; i < actors.length; ++i) {
            held += token.balanceOf(actors[i]);
        }
        assertEq(held, SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.balanceOf(address(token)), 0);
        assertEq(token.balanceOf(address(handler)), 0);
    }

    function invariant_balancesAndAllowancesMatchIndependentLedger() public view {
        for (uint256 i; i < actors.length; ++i) {
            address actor = actors[i];
            assertEq(token.balanceOf(actor), handler.expectedBalance(actor));
            assertEq(token.allowance(actor, address(0)), 0);
            for (uint256 j; j < actors.length; ++j) {
                assertEq(token.allowance(actor, actors[j]), handler.expectedAllowance(actor, actors[j]));
            }
        }
    }
}
