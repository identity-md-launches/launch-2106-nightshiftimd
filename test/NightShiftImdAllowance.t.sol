// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {NightShiftImd} from "src/NightShiftImd.sol";

/// @notice Allowance lifecycle and rollback properties, complementing the basic ERC-20 tests.
/// forge-config: default.fuzz.runs = 1024
contract NightShiftImdAllowanceTest is Test {
    uint256 private constant SUPPLY = 1_000_000_000 * 1e18;

    NightShiftImd private token;
    address private holder;
    address private spender;
    address private otherSpender;
    address private recipient;

    function setUp() public {
        token = new NightShiftImd();
        holder = makeAddr("allowance holder");
        spender = makeAddr("first spender");
        otherSpender = makeAddr("second spender");
        recipient = makeAddr("allowance recipient");
    }

    function test_oneBaseUnitCanBeApprovedSpentAndReturned() public {
        assertTrue(token.transfer(holder, 1));
        _approve(holder, spender, 1);
        _spend(spender, holder, recipient, 1);
        assertEq(token.balanceOf(holder), 0);
        assertEq(token.balanceOf(recipient), 1);
        assertEq(token.allowance(holder, spender), 0);

        vm.prank(recipient);
        assertTrue(token.transfer(holder, 1));
        _expectAllowanceFailure(spender, holder, recipient, 0, 1);
        assertEq(token.balanceOf(holder), 1);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_maxMinusOneAllowanceIsFinite() public {
        assertTrue(token.transfer(holder, SUPPLY));
        _approve(holder, spender, type(uint256).max - 1);
        _spend(spender, holder, recipient, 1);
        assertEq(token.allowance(holder, spender), type(uint256).max - 2);
        _spend(spender, holder, recipient, SUPPLY - 1);
        assertEq(token.allowance(holder, spender), type(uint256).max - 1 - SUPPLY);
        assertEq(token.balanceOf(holder), 0);
        assertEq(token.balanceOf(recipient), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_unlimitedApprovalCanBeReducedAndRevokedAfterSpending() public {
        assertTrue(token.transfer(holder, 10));
        _approve(holder, spender, type(uint256).max);
        _spend(spender, holder, recipient, 1);
        assertEq(token.allowance(holder, spender), type(uint256).max);

        _approve(holder, spender, 2);
        _expectAllowanceFailure(spender, holder, recipient, 2, 3);
        _spend(spender, holder, recipient, 1);
        assertEq(token.allowance(holder, spender), 1);

        _approve(holder, spender, 0);
        _expectAllowanceFailure(spender, holder, recipient, 0, 1);
        assertEq(token.balanceOf(holder), 8);
        assertEq(token.balanceOf(recipient), 2);
        assertEq(token.allowance(holder, spender), 0);
    }

    function test_spenderCannotPassItsAuthorityToAnotherSpender() public {
        assertTrue(token.transfer(holder, 10));
        _approve(holder, spender, 10);
        _approve(spender, otherSpender, type(uint256).max);

        _expectAllowanceFailure(otherSpender, holder, recipient, 0, 1);
        assertEq(token.allowance(holder, spender), 10);
        assertEq(token.allowance(spender, otherSpender), type(uint256).max);
        assertEq(token.balanceOf(holder), 10);
        _spend(spender, holder, recipient, 10);
        assertEq(token.balanceOf(recipient), 10);
    }

    function test_selfApprovalDoesNotAuthorizeAnotherCaller() public {
        assertTrue(token.transfer(holder, 10));
        _approve(holder, holder, 10);
        _expectAllowanceFailure(spender, holder, recipient, 0, 1);

        _spend(holder, holder, holder, 10);
        assertEq(token.balanceOf(holder), 10);
        assertEq(token.allowance(holder, holder), 0);
        _expectAllowanceFailure(holder, holder, recipient, 0, 1);
        vm.prank(holder);
        assertTrue(token.transfer(recipient, 10));
        assertEq(token.balanceOf(recipient), 10);
    }

    function test_zeroTransferFromStillRejectsZeroEndpoints() public {
        // A zero-value delegated call is permissionless, but zero endpoints remain invalid.
        vm.expectRevert();
        vm.prank(spender);
        token.transferFrom(address(0), recipient, 0);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(spender);
        token.transferFrom(holder, address(0), 0);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.balanceOf(recipient), 0);
        assertEq(token.allowance(holder, spender), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_refundingTokensDoesNotRestoreSpentAllowance(uint256 rawAmount, uint256 rawFirst) public {
        uint256 amount = bound(rawAmount, 1, SUPPLY);
        uint256 first = bound(rawFirst, 0, amount);
        assertTrue(token.transfer(holder, amount));
        _approve(holder, spender, amount);

        _spend(spender, holder, recipient, first);
        assertEq(token.allowance(holder, spender), amount - first);
        _spend(spender, holder, recipient, amount - first);
        assertEq(token.allowance(holder, spender), 0);
        assertEq(token.balanceOf(recipient), amount);

        vm.prank(recipient);
        assertTrue(token.transfer(holder, amount));
        _expectAllowanceFailure(spender, holder, recipient, 0, 1);
        assertEq(token.balanceOf(holder), amount);
        assertEq(token.balanceOf(recipient), 0);
        assertEq(token.allowance(holder, spender), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_competingSpendersCannotSpendTheSameBalance(uint256 rawBalance, uint256 rawFirst) public {
        uint256 balance = bound(rawBalance, 1, SUPPLY);
        uint256 first = bound(rawFirst, 1, balance);
        assertTrue(token.transfer(holder, balance));
        _approve(holder, spender, balance);
        _approve(holder, otherSpender, balance);

        _spend(spender, holder, recipient, first);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, holder, balance - first, balance)
        );
        vm.prank(otherSpender);
        token.transferFrom(holder, otherSpender, balance);
        assertEq(token.balanceOf(holder), balance - first);
        assertEq(token.balanceOf(otherSpender), 0);
        assertEq(token.allowance(holder, otherSpender), balance, "failed spend consumed authorization");
        assertEq(token.allowance(holder, spender), balance - first);

        vm.prank(recipient);
        assertTrue(token.transfer(holder, first));
        _spend(otherSpender, holder, otherSpender, balance);
        assertEq(token.balanceOf(holder), 0);
        assertEq(token.balanceOf(recipient), 0);
        assertEq(token.balanceOf(otherSpender), balance);
        assertEq(token.allowance(holder, otherSpender), 0);
        assertEq(token.allowance(holder, spender), balance - first);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_failedSpendCanSucceedAfterFunding(uint256 rawBalance, uint256 rawAmount, uint256 rawAllowance)
        public
    {
        uint256 balance = bound(rawBalance, 0, SUPPLY - 1);
        uint256 amount = bound(rawAmount, balance + 1, SUPPLY);
        uint256 allowance = bound(rawAllowance, amount, type(uint256).max);
        assertTrue(token.transfer(holder, balance));
        _approve(holder, spender, allowance);

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, holder, balance, amount));
        vm.prank(spender);
        token.transferFrom(holder, recipient, amount);
        assertEq(token.balanceOf(holder), balance);
        assertEq(token.balanceOf(recipient), 0);
        assertEq(token.allowance(holder, spender), allowance);

        assertTrue(token.transfer(holder, amount - balance));
        _spend(spender, holder, recipient, amount);
        assertEq(token.balanceOf(holder), 0);
        assertEq(token.balanceOf(recipient), amount);
        assertEq(token.balanceOf(address(this)), SUPPLY - amount);
        assertEq(token.allowance(holder, spender), allowance == type(uint256).max ? allowance : allowance - amount);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_invalidRecipientDoesNotConsumeAuthorization(uint256 rawAmount, uint256 rawAllowance) public {
        uint256 amount = bound(rawAmount, 0, SUPPLY);
        uint256 allowance = bound(rawAllowance, amount, type(uint256).max);
        assertTrue(token.transfer(holder, SUPPLY));
        _approve(holder, spender, allowance);

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(spender);
        token.transferFrom(holder, address(0), amount);
        assertEq(token.allowance(holder, spender), allowance);
        assertEq(token.balanceOf(holder), SUPPLY);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.totalSupply(), SUPPLY);

        _spend(spender, holder, recipient, amount);
        assertEq(token.balanceOf(recipient), amount);
        assertEq(token.balanceOf(holder), SUPPLY - amount);
        assertEq(token.allowance(holder, spender), allowance == type(uint256).max ? allowance : allowance - amount);
    }

    function testFuzz_splitDelegatedTransfersEqualSingleTransfer(
        uint256 rawAmount,
        uint256 rawFirst,
        uint256 rawAllowance,
        bool selfTransfer
    ) public {
        // An algebraic oracle: splitting a payment must not change fees, balances, or authorization spent.
        NightShiftImd single = new NightShiftImd();
        uint256 amount = bound(rawAmount, 0, SUPPLY);
        uint256 first = bound(rawFirst, 0, amount);
        uint256 allowance = bound(rawAllowance, amount, type(uint256).max);
        address to = selfTransfer ? holder : recipient;
        assertTrue(token.transfer(holder, SUPPLY));
        assertTrue(single.transfer(holder, SUPPLY));
        _approve(holder, spender, allowance);
        vm.prank(holder);
        assertTrue(single.approve(spender, allowance));

        _spend(spender, holder, to, first);
        _spend(spender, holder, to, amount - first);
        vm.prank(spender);
        assertTrue(single.transferFrom(holder, to, amount));

        assertEq(token.balanceOf(holder), single.balanceOf(holder));
        assertEq(token.balanceOf(recipient), single.balanceOf(recipient));
        assertEq(token.balanceOf(spender), 0);
        assertEq(token.allowance(holder, spender), single.allowance(holder, spender));
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(single.totalSupply(), SUPPLY);
    }

    function testFuzz_directTransferDoesNotChangeAnyApproval(uint256 allowance, uint256 rawAmount) public {
        uint256 amount = bound(rawAmount, 0, SUPPLY);
        assertTrue(token.transfer(holder, SUPPLY));
        _approve(holder, holder, allowance);
        _approve(holder, spender, allowance);
        _approve(recipient, spender, type(uint256).max);

        vm.prank(holder);
        assertTrue(token.transfer(recipient, amount));
        assertEq(token.allowance(holder, holder), allowance);
        assertEq(token.allowance(holder, spender), allowance);
        assertEq(token.allowance(recipient, spender), type(uint256).max);
        assertEq(token.allowance(recipient, holder), 0);
        vm.prank(recipient);
        assertTrue(token.transfer(holder, amount));
        assertEq(token.balanceOf(holder), SUPPLY);
        assertEq(token.balanceOf(recipient), 0);
        assertEq(token.allowance(holder, holder), allowance);
        assertEq(token.allowance(holder, spender), allowance);
        assertEq(token.allowance(recipient, spender), type(uint256).max);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function _approve(address owner, address approved, uint256 amount) private {
        vm.prank(owner);
        assertTrue(token.approve(approved, amount));
        assertEq(token.allowance(owner, approved), amount);
    }

    function _spend(address caller, address from, address to, uint256 amount) private {
        vm.prank(caller);
        assertTrue(token.transferFrom(from, to, amount));
    }

    function _expectAllowanceFailure(address caller, address from, address to, uint256 allowance, uint256 amount)
        private
    {
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, caller, allowance, amount)
        );
        vm.prank(caller);
        token.transferFrom(from, to, amount);
        assertEq(token.allowance(from, caller), allowance);
    }
}
