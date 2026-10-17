// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {NightShiftImd} from "../src/NightShiftImd.sol";

/// @dev Local factory fixture only; it is not a launch application or a production deployment script.
contract TokenFactoryFixture {
    function deploy(bytes32 salt) external returns (NightShiftImd) {
        return new NightShiftImd{salt: salt}();
    }

    function move(NightShiftImd token, address to, uint256 amount) external {
        require(token.transfer(to, amount), "transfer failed");
    }
}

contract NightShiftImdLaunchTest is Test {
    uint256 private constant SUPPLY = 1_000_000_000 * 1e18;

    function testFuzz_create2MintsEntireSupplyToFactory(bytes32 salt) public {
        TokenFactoryFixture factory = new TokenFactoryFixture();
        address expected = computeCreate2Address(salt, keccak256(type(NightShiftImd).creationCode), address(factory));
        NightShiftImd token = factory.deploy(salt);
        assertEq(address(token), expected);
        assertEq(token.balanceOf(address(factory)), SUPPLY);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(address(token)), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    /// @dev Exercises exact token movements. The independent launch harness tests the actual v4 pool.
    function test_factoryDistributionClaimAndPoolTransfersArriveWhole() public {
        TokenFactoryFixture factory = new TokenFactoryFixture();
        NightShiftImd token = factory.deploy(keccak256("launch flow"));
        address distributor = makeAddr("distributor");
        address poolManager = makeAddr("pool manager");
        address remainderRecipient = makeAddr("remainder recipient");
        address claimant = makeAddr("claimant");
        address trader = makeAddr("trader");

        uint256 swarmShare = SUPPLY / 10;
        uint256 poolShare = SUPPLY * 8 / 10;
        uint256 remainder = SUPPLY - swarmShare - poolShare;
        factory.move(token, distributor, swarmShare);
        factory.move(token, poolManager, poolShare);
        factory.move(token, remainderRecipient, remainder);
        assertEq(token.balanceOf(address(factory)), 0);
        assertEq(token.balanceOf(distributor), swarmShare);
        assertEq(token.balanceOf(poolManager), poolShare);
        assertEq(token.balanceOf(remainderRecipient), remainder);

        vm.prank(distributor);
        assertTrue(token.transfer(claimant, swarmShare));
        assertEq(token.balanceOf(distributor), 0);
        assertEq(token.balanceOf(claimant), swarmShare);

        vm.prank(poolManager);
        assertTrue(token.transfer(trader, 1_000 ether));
        assertEq(token.balanceOf(trader), 1_000 ether);
        assertEq(token.balanceOf(poolManager), poolShare - 1_000 ether);
        vm.prank(trader);
        assertTrue(token.transfer(poolManager, 1_000 ether));
        assertEq(token.balanceOf(trader), 0);
        assertEq(token.balanceOf(poolManager), poolShare);
        assertEq(token.totalSupply(), SUPPLY);
    }
}
