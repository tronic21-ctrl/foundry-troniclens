// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract GovernanceContract {
    address public owner;
    uint256 public proposalCount;
    uint256 public votingDuration = 300; // 5 menit untuk testing
    uint256 public quorumPercentage = 51; // minimal 51% untuk lolos
    uint256 public timelockDuration = 120; // 2 menit untuk testing
    mapping(uint256 => uint256) public queuedAt; // kapan proposal di-queue

    struct Proposal {
        uint256 id;
        address proposer;
        string description;
        uint256 yesVotes;
        uint256 noVotes;
        uint256 deadline;
        bool executed;
        bool passed;
    }

    mapping(uint256 => Proposal) public proposals;
    mapping(uint256 => mapping(address => bool)) public hasVoted;

    event ProposalCreated(uint256 id, address proposer, string description);
    event Voted(uint256 proposalId, address voter, bool support);
    event ProposalExecuted(uint256 proposalId, bool passed);
    event ProposalQueued(uint256 proposalId, uint256 executeAfter);

    function createProposal(string memory description) public returns (uint256) {
        proposalCount++;

        proposals[proposalCount] = Proposal({
            id: proposalCount,
            proposer: msg.sender,
            description: description,
            yesVotes: 0,
            noVotes: 0,
            deadline: block.timestamp + votingDuration,
            executed: false,
            passed: false
        });

        emit ProposalCreated(proposalCount, msg.sender, description);
        return proposalCount;
    }

    function vote(uint256 proposalId, bool support) public {
        Proposal storage proposal = proposals[proposalId];

        require(block.timestamp < proposal.deadline, "Voting sudah berakhir");
        require(!hasVoted[proposalId][msg.sender], "Sudah pernah vote");
        require(proposal.id != 0, "Proposal tidak ada");

        hasVoted[proposalId][msg.sender] = true;

        if (support) {
            proposal.yesVotes++;
        } else {
            proposal.noVotes++;
        }

        emit Voted(proposalId, msg.sender, support);
    }

    function queueProposal(uint256 proposalId) public {
        Proposal storage proposal = proposals[proposalId];

        require(proposal.id != 0, "Proposal tidak ada");
        require(block.timestamp >= proposal.deadline, "Voting belum berakhir");
        require(!proposal.executed, "Sudah dieksekusi");
        require(queuedAt[proposalId] == 0, "Sudah di-queue");

        uint256 totalVotes = proposal.yesVotes + proposal.noVotes;
        require(totalVotes > 0, "Tidak ada yang vote");

        uint256 yesPercentage = (proposal.yesVotes * 100) / totalVotes;
        require(yesPercentage >= quorumPercentage, "Proposal tidak lolos vote");

        queuedAt[proposalId] = block.timestamp;

        emit ProposalQueued(proposalId, block.timestamp + timelockDuration);
    }

    function executeProposal(uint256 proposalId) public {
        Proposal storage proposal = proposals[proposalId];

        require(proposal.id != 0, "Proposal tidak ada");
        require(!proposal.executed, "Sudah dieksekusi");
        require(queuedAt[proposalId] != 0, "Proposal belum di-queue");
        require(block.timestamp >= queuedAt[proposalId] + timelockDuration, "Timelock belum selesai");

        uint256 totalVotes = proposal.yesVotes + proposal.noVotes;
        uint256 yesPercentage = (proposal.yesVotes * 100) / totalVotes;

        proposal.executed = true;
        proposal.passed = yesPercentage >= quorumPercentage;

        emit ProposalExecuted(proposalId, proposal.passed);
    }

    function getProposal(uint256 proposalId)
        public
        view
        returns (
            uint256 id,
            address proposer,
            string memory description,
            uint256 yesVotes,
            uint256 noVotes,
            uint256 deadline,
            bool executed,
            bool passed
        )
    {
        Proposal storage proposal = proposals[proposalId];
        return (
            proposal.id,
            proposal.proposer,
            proposal.description,
            proposal.yesVotes,
            proposal.noVotes,
            proposal.deadline,
            proposal.executed,
            proposal.passed
        );
    }

    constructor() {
        owner = msg.sender;
        proposalCount = 0;
    }
}
