// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "../src/GovernanceContract.sol";

contract GovernanceContractTest is Test {
    GovernanceContract public governance;
    address public proposer = makeAddr("proposer");
    address public voter1 = makeAddr("voter1");
    address public voter2 = makeAddr("voter2");

    function setUp() public {
        governance = new GovernanceContract();
    }

    // ─── Happy Path ───

    function test_CreateProposalSuccess() public {
        vm.prank(proposer);
        uint256 id = governance.createProposal("Naikkan reward rate");

        (uint256 propId, address propProposer,,,,, bool executed,) = governance.getProposal(id);
        assertEq(propId, 1); // ← ubah dari 0 ke 1
        assertEq(propProposer, proposer);
        assertEq(executed, false);
    }

    function test_VoteSuccess() public {
        vm.prank(proposer);
        uint256 id = governance.createProposal("Naikkan reward rate");

        vm.prank(voter1);
        governance.vote(id, true);

        (,,, uint256 yesVotes, uint256 noVotes,,,) = governance.getProposal(id);
        assertEq(yesVotes, 1);
        assertEq(noVotes, 0);
    }

    function test_FullGovernanceFlow() public {
        // 1. Create proposal
        vm.prank(proposer);
        uint256 id = governance.createProposal("Naikkan reward rate");

        // 2. Vote — butuh majority (51%)
        vm.prank(voter1);
        governance.vote(id, true);

        // 3. Fast-forward melewati voting deadline (300 detik)
        vm.warp(block.timestamp + 301);

        // 4. Queue proposal
        vm.prank(proposer);
        governance.queueProposal(id);

        // 5. Fast-forward melewati timelock (120 detik)
        vm.warp(block.timestamp + 121);

        // 6. Execute
        vm.prank(proposer);
        governance.executeProposal(id);

        (,,,,,, bool executed, bool passed) = governance.getProposal(id);
        assertEq(executed, true);
        assertEq(passed, true);
    }

    // ─── Sad Path ───

    function test_RevertIf_DoubleVote() public {
        vm.prank(proposer);
        uint256 id = governance.createProposal("Test proposal");

        vm.prank(voter1);
        governance.vote(id, true);

        vm.prank(voter1);
        vm.expectRevert("Sudah pernah vote");
        governance.vote(id, true);
    }

    function test_RevertIf_VoteAfterDeadline() public {
        vm.prank(proposer);
        uint256 id = governance.createProposal("Test proposal");

        vm.warp(block.timestamp + 301);

        vm.prank(voter1);
        vm.expectRevert("Voting sudah berakhir");
        governance.vote(id, true);
    }

    function test_RevertIf_QueueBeforeDeadline() public {
        vm.prank(proposer);
        uint256 id = governance.createProposal("Test proposal");

        vm.prank(voter1);
        governance.vote(id, true);

        vm.prank(proposer);
        vm.expectRevert("Voting belum berakhir");
        governance.queueProposal(id);
    }

    function test_RevertIf_ExecuteWithoutQueue() public {
        vm.prank(proposer);
        uint256 id = governance.createProposal("Test proposal");

        vm.prank(voter1);
        governance.vote(id, true);

        vm.warp(block.timestamp + 301);

        vm.prank(proposer);
        vm.expectRevert("Proposal belum di-queue");
        governance.executeProposal(id);
    }

    function test_RevertIf_ExecuteBeforeTimelock() public {
        vm.prank(proposer);
        uint256 id = governance.createProposal("Test proposal");

        vm.prank(voter1);
        governance.vote(id, true);

        vm.warp(block.timestamp + 301);
        governance.queueProposal(id);

        vm.prank(proposer);
        vm.expectRevert("Timelock belum selesai");
        governance.executeProposal(id);
    }

    function test_RevertIf_EmptyDescription() public {
        vm.prank(proposer);
        vm.expectRevert("Description tidak boleh kosong");
        governance.createProposal("");
    }
}
