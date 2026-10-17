// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
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
        uint256 amount = validAmount ? bound(amountSeed, 0, expectedBalance[from]) : amountSeed;
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
        uint256 amount = unlimited ? type(uint256).max : amountSeed;

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
        uint256 amount = validAmount ? bound(amountSeed, 0, limit) : amountSeed;
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

    /// @dev Full-balance transitions deliberately empty and refill accounts during the campaign.
    function transferFullBalance(uint256 fromSeed, uint256 toSeed) external {
        address from = actors[fromSeed % actors.length];
        address to = _differentActor(fromSeed, toSeed);
        uint256 amount = expectedBalance[from];
        vm.prank(from);
        assertTrue(token.transfer(to, amount));
        expectedBalance[from] = 0;
        expectedBalance[to] += amount;
    }

    /// @dev Explicit revocation is exercised even when arbitrary uint256 approvals rarely equal zero.
    function revokeAndAttemptSpend(uint256 ownerSeed, uint256 spenderSeed) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        vm.prank(owner);
        assertTrue(token.approve(spender, 0));
        expectedAllowance[owner][spender] = 0;

        vm.prank(spender);
        (bool success, bytes memory result) =
            address(token).call(abi.encodeCall(token.transferFrom, (owner, spender, 1)));
        assertFalse(success, "revoked spender moved tokens");
        assertEq(result, abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
    }

    /// @dev Sufficient approval forces this failure past the allowance check and tests rollback.
    function spendAboveBalance(uint256 ownerSeed, uint256 spenderSeed, uint256 amountSeed) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        uint256 balance = expectedBalance[owner];
        uint256 amount = bound(amountSeed, balance + 1, type(uint256).max);
        vm.prank(owner);
        assertTrue(token.approve(spender, amount));
        expectedAllowance[owner][spender] = amount;

        vm.prank(spender);
        (bool success, bytes memory result) =
            address(token).call(abi.encodeCall(token.transferFrom, (owner, spender, amount)));
        assertFalse(success, "allowance bypassed the holder's balance");
        assertEq(result, abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, owner, balance, amount));
    }

    /// @dev An inverse-operation oracle: a round trip must restore balances without consuming approvals.
    function roundTrip(uint256 fromSeed, uint256 toSeed, uint256 amountSeed) external {
        address from = actors[fromSeed % actors.length];
        address to = _differentActor(fromSeed, toSeed);
        uint256 amount = bound(amountSeed, 0, expectedBalance[from]);

        vm.prank(from);
        assertTrue(token.transfer(to, amount));
        assertEq(token.balanceOf(from), expectedBalance[from] - amount);
        assertEq(token.balanceOf(to), expectedBalance[to] + amount);
        vm.prank(to);
        assertTrue(token.transfer(from, amount));
        // No ghost updates: the ledger and all allowances must be unchanged after the inverse.
        assertEq(token.balanceOf(from), expectedBalance[from]);
        assertEq(token.balanceOf(to), expectedBalance[to]);
    }

    function _differentActor(uint256 fromSeed, uint256 toSeed) private view returns (address) {
        return actors[(fromSeed % actors.length + 1 + toSeed % (actors.length - 1)) % actors.length];
    }

    function _recipient(uint256 seed) private view returns (address) {
        uint256 index = seed % (actors.length + 1);
        return index == actors.length ? address(0) : actors[index];
    }
}

/// forge-config: default.invariant.runs = 256
/// forge-config: default.invariant.depth = 128
/// forge-config: default.invariant.fail-on-revert = true
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

        // Give every actor value and a usable allowance through the real token API and ledger.
        // This avoids starting most generated delegated transfers with an empty holder or no approval.
        for (uint256 i = 1; i < actors.length; ++i) {
            handler.transfer(0, i, SUPPLY / actors.length, true);
        }
        for (uint256 i; i < actors.length; ++i) {
            handler.approve(i, (i + 1) % actors.length, SUPPLY / actors.length, false);
        }

        bytes4[] memory selectors = new bytes4[](7);
        selectors[0] = TokenHandler.transfer.selector;
        selectors[1] = TokenHandler.approve.selector;
        selectors[2] = TokenHandler.transferFrom.selector;
        selectors[3] = TokenHandler.transferFullBalance.selector;
        selectors[4] = TokenHandler.revokeAndAttemptSpend.selector;
        selectors[5] = TokenHandler.spendAboveBalance.selector;
        selectors[6] = TokenHandler.roundTrip.selector;
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
        assertEq(token.name(), "NightShiftImd");
        assertEq(token.symbol(), "SHIFT");
        assertEq(token.decimals(), 18);
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

    /// @dev After every random sequence, all circulating tokens must still be transferable.
    function afterInvariant() public {
        for (uint256 i; i < actors.length; ++i) {
            address actor = actors[i];
            uint256 balance = token.balanceOf(actor);
            vm.prank(actor);
            assertTrue(token.transfer(address(this), balance));
            assertEq(token.balanceOf(actor), 0);
            for (uint256 j; j < actors.length; ++j) {
                assertEq(token.allowance(actor, actors[j]), handler.expectedAllowance(actor, actors[j]));
            }
        }
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }
}
