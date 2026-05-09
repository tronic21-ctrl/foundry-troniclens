// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "../src/StakingContract.sol";

contract StakingContractTest is Test {
    StakingContract public staking;
    address public user = makeAddr("user");

    function setUp() public {
        staking = new StakingContract();
        // Isi contract dengan ETH untuk bayar reward
        vm.deal(address(staking), 10 ether);
        // Beri user 1 ETH untuk testing
        vm.deal(user, 1 ether);
    }

    // ─── Happy Path ───

    function test_StakeSuccess() public {
        vm.prank(user);
        staking.stake{value: 0.1 ether}();

        (uint256 amount,,,) = staking.getStakeInfo(user);
        assertEq(amount, 0.1 ether);
    }

    function test_UnstakeSuccess() public {
        vm.prank(user);
        staking.stake{value: 0.1 ether}();

        // Fast-forward waktu 61 detik (lewati minimumStakePeriod = 60)
        vm.warp(block.timestamp + 61);

        uint256 balanceBefore = user.balance;

        vm.prank(user);
        staking.unstake();

        // Balance user harus bertambah (pokok + reward)
        assertGt(user.balance, balanceBefore);
    }

    function test_CalculateReward() public {
        vm.prank(user);
        staking.stake{value: 0.1 ether}();

        vm.warp(block.timestamp + 100);

        uint256 reward = staking.calculateReward(user);
        // reward = 100 detik × 1 wei/detik = 100 wei
        assertEq(reward, 100);
    }

    // ─── Sad Path ───

    function test_RevertIf_StakeBelowMinimum() public {
        vm.prank(user);
        vm.expectRevert("Stake minimum 0.001 ETH");
        staking.stake{value: 0.0001 ether}();
    }

    function test_RevertIf_DoubleStake() public {
        vm.prank(user);
        staking.stake{value: 0.1 ether}();

        vm.prank(user);
        vm.expectRevert("Sudah ada stake aktif");
        staking.stake{value: 0.1 ether}();
    }

    function test_RevertIf_UnstakeBeforeMinimumPeriod() public {
        vm.prank(user);
        staking.stake{value: 0.1 ether}();

        vm.prank(user);
        vm.expectRevert("Minimum stake period belum tercapai");
        staking.unstake();
    }

    function test_RevertIf_UnstakeWithNoStake() public {
        vm.prank(user);
        vm.expectRevert("Tidak ada stake aktif");
        staking.unstake();
    }
}