// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {NightShiftImd} from "../src/NightShiftImd.sol";

/// @dev A transfer to a contract must not invoke any recipient callback.
contract RejectingRecipient {
    fallback() external {
        revert("no callbacks");
    }
}

contract NightShiftImdTest is Test {
    uint256 private constant SUPPLY = 1_000_000_000_000_000_000_000_000_000;

    NightShiftImd private token;
    address private alice;
    address private bob;
    address private spender;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    function setUp() public {
        alice = makeAddr("alice");
        bob = makeAddr("bob");
        spender = makeAddr("spender");
        token = new NightShiftImd();
    }

    function test_metadataAndInitialSupply() public view {
        assertEq(token.name(), "NightShiftImd");
        assertEq(token.symbol(), "SHIFT");
        assertEq(token.decimals(), 18);
        assertEq(token.INITIAL_SUPPLY(), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(address(token)), 0);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.allowance(address(this), spender), 0);
    }

    function test_constructorEmitsExactlyOneMintToDeployer() public {
        vm.recordLogs();
        vm.prank(alice, bob);
        NightShiftImd deployed = new NightShiftImd();
        Vm.Log[] memory logs = vm.getRecordedLogs();

        assertEq(logs.length, 1);
        assertEq(logs[0].emitter, address(deployed));
        assertEq(logs[0].topics.length, 3);
        assertEq(logs[0].topics[0], keccak256("Transfer(address,address,uint256)"));
        assertEq(logs[0].topics[1], bytes32(0));
        assertEq(logs[0].topics[2], bytes32(uint256(uint160(alice))));
        assertEq(abi.decode(logs[0].data, (uint256)), SUPPLY);
        assertEq(deployed.balanceOf(alice), SUPPLY);
        assertEq(deployed.balanceOf(bob), 0, "tx.origin must not receive the supply");
    }

    function test_transferDeliversExactAmountAndEmitsEvent() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(address(this), alice, 123 ether);
        assertTrue(token.transfer(alice, 123 ether));

        assertEq(token.balanceOf(alice), 123 ether);
        assertEq(token.balanceOf(address(this)), SUPPLY - 123 ether);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_transferEntireSupply() public {
        assertTrue(token.transfer(alice, SUPPLY));
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(alice), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_zeroTransferFromEmptyAccountEmitsEvent() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(alice, bob, 0);
        vm.prank(alice);
        assertTrue(token.transfer(bob, 0));
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_selfTransferPreservesBalanceAndEmitsEvent() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(address(this), address(this), SUPPLY);
        assertTrue(token.transfer(address(this), SUPPLY));
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_transferToContractDoesNotCallRecipient() public {
        RejectingRecipient recipient = new RejectingRecipient();
        assertTrue(token.transfer(address(recipient), 1 ether));
        assertEq(token.balanceOf(address(recipient)), 1 ether);
    }

    function test_transferAboveBalanceRevertsWithoutChanges() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 0, 1));
        vm.prank(alice);
        token.transfer(bob, 1);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_transferMaximumUintReverts() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector, address(this), SUPPLY, type(uint256).max
            )
        );
        token.transfer(alice, type(uint256).max);
        assertEq(token.balanceOf(address(this)), SUPPLY);
    }

    function test_selfTransferStillRequiresBalance() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 0, 1));
        vm.prank(alice);
        token.transfer(alice, 1);
    }

    function test_transferToZeroRevertsIncludingZeroAmount() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        token.transfer(address(0), 1);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        token.transfer(address(0), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_approveEmitsEventWithoutMovingTokens() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Approval(address(this), spender, 10 ether);
        assertTrue(token.approve(spender, 10 ether));
        assertEq(token.allowance(address(this), spender), 10 ether);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(spender), 0);
    }

    function test_approveCanReplaceAndRevokeAllowance() public {
        assertTrue(token.approve(spender, 10 ether));
        assertTrue(token.approve(spender, 3 ether));
        assertEq(token.allowance(address(this), spender), 3 ether);
        vm.expectEmit(true, true, false, true, address(token));
        emit Approval(address(this), spender, 0);
        assertTrue(token.approve(spender, 0));
        assertEq(token.allowance(address(this), spender), 0);

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(address(this), bob, 1);
    }

    function test_approvalDoesNotRequireCurrentBalance() public {
        vm.prank(alice);
        assertTrue(token.approve(spender, 10 ether));
        assertTrue(token.transfer(alice, 10 ether));
        vm.prank(spender);
        assertTrue(token.transferFrom(alice, bob, 10 ether));
        assertEq(token.balanceOf(bob), 10 ether);
        assertEq(token.allowance(alice, spender), 0);
    }

    function test_approveZeroSpenderRevertsIncludingZeroAmount() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        token.approve(address(0), 1);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        token.approve(address(0), 0);
        assertEq(token.allowance(address(this), address(0)), 0);
    }

    function test_transferFromDeliversExactAmountAndSpendsAllowance() public {
        assertTrue(token.approve(spender, 10 ether));
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(address(this), alice, 4 ether);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, 4 ether));
        assertEq(token.allowance(address(this), spender), 6 ether);
        assertEq(token.balanceOf(address(this)), SUPPLY - 4 ether);
        assertEq(token.balanceOf(alice), 4 ether);
        assertEq(token.balanceOf(spender), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_transferFromCanExhaustAllowance() public {
        assertTrue(token.approve(spender, 10 ether));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, 10 ether));
        assertEq(token.allowance(address(this), spender), 0);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(address(this), alice, 1);
        assertEq(token.balanceOf(alice), 10 ether);
    }

    function test_transferFromMaximumAllowanceRemainsUnchanged() public {
        assertTrue(token.approve(spender, type(uint256).max));
        vm.startPrank(spender);
        assertTrue(token.transferFrom(address(this), alice, 10 ether));
        assertTrue(token.transferFrom(address(this), bob, 20 ether));
        vm.stopPrank();
        assertEq(token.allowance(address(this), spender), type(uint256).max);
        assertEq(token.balanceOf(alice), 10 ether);
        assertEq(token.balanceOf(bob), 20 ether);
    }

    function test_zeroTransferFromNeedsNoAllowance() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(alice, bob, 0);
        vm.prank(spender);
        assertTrue(token.transferFrom(alice, bob, 0));
        assertEq(token.allowance(alice, spender), 0);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 0);
    }

    function test_transferFromToSameHolderConsumesAllowanceOnly() public {
        assertTrue(token.approve(spender, 10 ether));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), address(this), 4 ether));
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.allowance(address(this), spender), 6 ether);
    }

    function test_transferFromRequiresAllowanceEvenForHolder() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(this), 0, 1));
        token.transferFrom(address(this), alice, 1);
    }

    function test_transferFromAboveAllowanceRevertsWithoutChanges() public {
        assertTrue(token.approve(spender, 3 ether));
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 3 ether, 4 ether)
        );
        vm.prank(spender);
        token.transferFrom(address(this), alice, 4 ether);
        assertEq(token.allowance(address(this), spender), 3 ether);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
    }

    function test_transferFromAboveBalanceRestoresAllowance() public {
        vm.prank(alice);
        assertTrue(token.approve(spender, 10 ether));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 0, 1 ether));
        vm.prank(spender);
        token.transferFrom(alice, bob, 1 ether);
        assertEq(token.allowance(alice, spender), 10 ether);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_maximumAllowanceCannotBypassBalanceCheck() public {
        vm.prank(alice);
        assertTrue(token.approve(spender, type(uint256).max));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 0, 1));
        vm.prank(spender);
        token.transferFrom(alice, bob, 1);
        assertEq(token.allowance(alice, spender), type(uint256).max);
    }

    function test_transferFromToZeroRevertsAndRestoresAllowance() public {
        assertTrue(token.approve(spender, 10 ether));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(spender);
        token.transferFrom(address(this), address(0), 1 ether);
        assertEq(token.allowance(address(this), spender), 10 ether);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_transferFromZeroCannotMint() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(address(0), alice, 1);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_deployerCannotSpendAnotherHoldersTokens() public {
        assertTrue(token.transfer(alice, 10 ether));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(this), 0, 1));
        token.transferFrom(alice, address(this), 1);
        assertEq(token.balanceOf(alice), 10 ether);
        vm.prank(alice);
        assertTrue(token.transfer(bob, 10 ether));
        assertEq(token.balanceOf(bob), 10 ether);
    }

    function test_approvalIsSpecificToHolderAndSpender() public {
        assertTrue(token.transfer(alice, 10 ether));
        assertTrue(token.approve(spender, 10 ether));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, bob, 0, 1));
        vm.prank(bob);
        token.transferFrom(address(this), alice, 1);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(alice, bob, 1);
        assertEq(token.allowance(address(this), spender), 10 ether);
    }

    function test_noMintBurnOrAdministrativeEntrypoints() public {
        assertTrue(token.transfer(alice, 10 ether));
        bytes[] memory calls = new bytes[](17);
        calls[0] = abi.encodeWithSignature("mint(address,uint256)", bob, 1 ether);
        calls[1] = abi.encodeWithSignature("mint(uint256)", 1 ether);
        calls[2] = abi.encodeWithSignature("mint()");
        calls[3] = abi.encodeWithSignature("issue(uint256)", 1 ether);
        calls[4] = abi.encodeWithSignature("burn(uint256)", 1 ether);
        calls[5] = abi.encodeWithSignature("burnFrom(address,uint256)", alice, 1 ether);
        calls[6] = abi.encodeWithSignature("pause()");
        calls[7] = abi.encodeWithSignature("unpause()");
        calls[8] = abi.encodeWithSignature("blacklist(address)", alice);
        calls[9] = abi.encodeWithSignature("freeze(address)", alice);
        calls[10] = abi.encodeWithSignature("seize(address)", alice);
        calls[11] = abi.encodeWithSignature("setOwner(address)", bob);
        calls[12] = abi.encodeWithSignature("transferOwnership(address)", bob);
        calls[13] = abi.encodeWithSignature("upgradeTo(address)", bob);
        calls[14] = abi.encodeWithSignature("initialize(address)", bob);
        calls[15] = abi.encodeWithSignature("setMinter(address)", bob);
        calls[16] = abi.encodeWithSignature("setTransfersEnabled(bool)", false);

        for (uint256 i; i < calls.length; ++i) {
            (bool deployerSucceeded,) = address(token).call(calls[i]);
            assertFalse(deployerSucceeded, "deployer reached an unexpected entrypoint");
            vm.prank(bob);
            (bool outsiderSucceeded,) = address(token).call(calls[i]);
            assertFalse(outsiderSucceeded, "outsider reached an unexpected entrypoint");
        }
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(alice), 10 ether);
        assertEq(token.balanceOf(bob), 0);
        vm.prank(alice);
        assertTrue(token.transfer(bob, 10 ether));
        assertEq(token.balanceOf(bob), 10 ether);
    }

    function test_rejectsNativeEther() public {
        vm.deal(address(this), 1 ether);
        (bool success,) = address(token).call{value: 1 ether}("");
        assertFalse(success);
        assertEq(address(token).balance, 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_runtimeHasNoForbiddenOpcodes() public view {
        bytes memory runtime = address(token).code;
        assertGt(runtime.length, 0);
        assertLe(runtime.length, 24_576);
        for (uint256 i; i < runtime.length; ++i) {
            uint8 opcode = uint8(runtime[i]);
            if (opcode >= 0x60 && opcode <= 0x7f) {
                i += opcode - 0x5f;
                continue;
            }
            assertTrue(opcode != 0xf4 && opcode != 0xf2 && opcode != 0xff);
        }
    }

    function testFuzz_transfersConserveSupply(uint256 rawAmount, address recipient) public {
        vm.assume(recipient != address(0) && recipient != address(this));
        uint256 amount = bound(rawAmount, 0, SUPPLY);
        assertTrue(token.transfer(recipient, amount));
        assertEq(token.balanceOf(address(this)), SUPPLY - amount);
        assertEq(token.balanceOf(recipient), amount);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_selfTransferPreservesSupply(uint256 rawAmount) public {
        uint256 amount = bound(rawAmount, 0, SUPPLY);
        assertTrue(token.transfer(address(this), amount));
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_transferAboveBalanceReverts(uint256 rawBalance, uint256 rawExcess) public {
        uint256 balance = bound(rawBalance, 0, SUPPLY);
        uint256 excess = bound(rawExcess, 1, type(uint256).max - balance);
        assertTrue(token.transfer(alice, balance));
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, balance, balance + excess)
        );
        vm.prank(alice);
        token.transfer(bob, balance + excess);
        assertEq(token.balanceOf(alice), balance);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_transferFromHonorsAllowance(uint256 allowance, uint256 rawAmount) public {
        uint256 limit = allowance < SUPPLY ? allowance : SUPPLY;
        uint256 amount = bound(rawAmount, 0, limit);
        assertTrue(token.approve(spender, allowance));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, amount));
        assertEq(token.balanceOf(address(this)), SUPPLY - amount);
        assertEq(token.balanceOf(alice), amount);
        assertEq(
            token.allowance(address(this), spender), allowance == type(uint256).max ? allowance : allowance - amount
        );
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_transferFromRejectsInsufficientAllowance(uint256 rawAllowance, uint256 rawAmount) public {
        uint256 allowance = bound(rawAllowance, 0, SUPPLY - 1);
        uint256 amount = bound(rawAmount, allowance + 1, SUPPLY);
        assertTrue(token.approve(spender, allowance));
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, allowance, amount)
        );
        vm.prank(spender);
        token.transferFrom(address(this), alice, amount);
        assertEq(token.allowance(address(this), spender), allowance);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
    }
}
