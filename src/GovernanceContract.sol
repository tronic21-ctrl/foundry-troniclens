// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title  GovernanceContract
 * @author Riko Tronic (github: tronic21-ctrl)
 * @notice Contract governance on-chain yang memungkinkan pembuatan proposal,
 *         voting, antrian timelock, dan eksekusi — membentuk siklus governance
 *         lengkap yang transparan di blockchain.
 * @dev    Governance flow:
 *         1. `createProposal` → proposal dibuat, voting dibuka selama `votingDuration`
 *         2. `vote`           → voter memberikan yes/no vote sebelum deadline
 *         3. `queueProposal`  → jika lolos quorum, proposal masuk antrian timelock
 *         4. `executeProposal`→ setelah timelock habis, proposal dieksekusi
 *
 *         Dibangun sebagai bagian dari TronicLens —
 *         DeFi Staking Intelligence Cockpit untuk ETHOnline 2026.
 */
contract GovernanceContract is ReentrancyGuard {
    // ─────────────────────────────────────────────
    //  State Variables
    // ─────────────────────────────────────────────

    /// @notice Alamat owner contract (deployer)
    address public owner;

    /// @notice Total jumlah proposal yang pernah dibuat (juga digunakan sebagai ID counter)
    uint256 public proposalCount;

    /// @notice Durasi voting setelah proposal dibuat (dalam detik)
    /// @dev    Default: 300 detik (5 menit) untuk keperluan testing
    uint256 public votingDuration = 300;

    /// @notice Persentase minimum yes votes dari total votes agar proposal lolos
    /// @dev    Default: 51% — mayoritas sederhana
    uint256 public quorumPercentage = 51;

    /// @notice Durasi timelock sebelum proposal yang lolos bisa dieksekusi (dalam detik)
    /// @dev    Default: 120 detik (2 menit) untuk keperluan testing.
    ///         Timelock memberi waktu komunitas untuk bereaksi sebelum eksekusi.
    uint256 public timelockDuration = 120;

    /// @notice Timestamp kapan proposal di-queue ke timelock
    /// @dev    0 berarti proposal belum di-queue. mapping(proposalId => timestamp)
    mapping(uint256 => uint256) public queuedAt;

    // ─────────────────────────────────────────────
    //  Structs
    // ─────────────────────────────────────────────

    /**
     * @notice Struktur data yang merepresentasikan satu proposal governance
     * @param id          ID unik proposal (dimulai dari 1)
     * @param proposer    Alamat yang membuat proposal
     * @param description Deskripsi proposal dalam bentuk string
     * @param yesVotes    Jumlah vote setuju yang diterima
     * @param noVotes     Jumlah vote tidak setuju yang diterima
     * @param deadline    Unix timestamp batas akhir periode voting
     * @param executed    true jika proposal sudah dieksekusi
     * @param passed      true jika proposal lolos quorum dan dieksekusi dengan hasil positif
     */
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

    // ─────────────────────────────────────────────
    //  Mappings
    // ─────────────────────────────────────────────

    /// @notice Menyimpan semua proposal berdasarkan ID
    mapping(uint256 => Proposal) public proposals;

    /// @notice Mencatat apakah seorang user sudah vote pada proposal tertentu
    /// @dev    mapping(proposalId => mapping(voterAddress => hasVoted))
    ///         Mencegah double voting tanpa perlu loop atau array.
    mapping(uint256 => mapping(address => bool)) public hasVoted;

    // ─────────────────────────────────────────────
    //  Events
    // ─────────────────────────────────────────────

    /// @notice Emitted ketika proposal baru berhasil dibuat
    /// @param id          ID proposal yang baru dibuat
    /// @param proposer    Alamat pembuat proposal
    /// @param description Deskripsi proposal
    event ProposalCreated(uint256 id, address proposer, string description);

    /// @notice Emitted ketika seorang voter memberikan suara pada proposal
    /// @param proposalId ID proposal yang di-vote
    /// @param voter      Alamat voter
    /// @param support    true = yes vote, false = no vote
    event Voted(uint256 proposalId, address voter, bool support);

    /// @notice Emitted ketika proposal berhasil dieksekusi
    /// @param proposalId ID proposal yang dieksekusi
    /// @param passed     true jika proposal lolos, false jika tidak
    event ProposalExecuted(uint256 proposalId, bool passed);

    /// @notice Emitted ketika proposal berhasil masuk antrian timelock
    /// @param proposalId  ID proposal yang di-queue
    /// @param executeAfter Unix timestamp kapan proposal bisa dieksekusi
    event ProposalQueued(uint256 proposalId, uint256 executeAfter);

    // ─────────────────────────────────────────────
    //  Constructor
    // ─────────────────────────────────────────────

    /// @notice Menginisialisasi contract, menetapkan deployer sebagai owner dan proposalCount ke 0
    constructor() {
        owner = msg.sender;
        proposalCount = 1; // ← mulai dari 1, bukan 0
    }

    // ─────────────────────────────────────────────
    //  External / Public Functions
    // ─────────────────────────────────────────────

    /**
     * @notice Membuat proposal governance baru
     * @dev    ID proposal di-increment dari `proposalCount` — dimulai dari 1.
     *         Deadline voting dihitung dari `block.timestamp + votingDuration`.
     * @param  description Deskripsi proposal yang ingin diajukan
     * @return             ID proposal yang baru dibuat
     *
     * Emits: {ProposalCreated}
     */
    function createProposal(string memory description) public returns (uint256) {
        require(bytes(description).length > 0, "Description tidak boleh kosong");

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

    /**
     * @notice Memberikan vote pada proposal yang sedang aktif
     * @dev    Setiap address hanya bisa vote satu kali per proposal.
     *         Vote dicatat via `hasVoted` mapping untuk mencegah double voting.
     * @param  proposalId ID proposal yang ingin di-vote
     * @param  support    true untuk yes vote, false untuk no vote
     *
     * Requirements:
     * - Voting period harus masih aktif (`block.timestamp < deadline`)
     * - Caller belum pernah vote pada proposal ini
     * - Proposal harus ada (id != 0)
     *
     * Emits: {Voted}
     */
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

    /**
     * @notice Memasukkan proposal yang lolos voting ke antrian timelock
     * @dev    Proposal harus memenuhi `quorumPercentage` untuk bisa di-queue.
     *         Setelah di-queue, proposal harus menunggu `timelockDuration` detik
     *         sebelum bisa dieksekusi via `executeProposal`.
     *         Formula quorum: (yesVotes * 100) / totalVotes >= quorumPercentage
     * @param  proposalId ID proposal yang ingin di-queue
     *
     * Requirements:
     * - Proposal harus ada
     * - Voting period harus sudah berakhir
     * - Proposal belum dieksekusi
     * - Proposal belum di-queue sebelumnya
     * - Total votes > 0
     * - Yes percentage >= quorumPercentage
     *
     * Emits: {ProposalQueued}
     */
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

    /**
     * @notice Mengeksekusi proposal yang sudah melewati masa timelock
     * @dev    Eksekusi hanya mengubah state `executed` dan `passed` di contract ini.
     *         Untuk action on-chain yang lebih kompleks (transfer dana, ubah parameter),
     *         diperlukan integrasi dengan contract target — ini scope pengembangan berikutnya.
     * @param  proposalId ID proposal yang ingin dieksekusi
     *
     * Requirements:
     * - Proposal harus ada
     * - Proposal belum dieksekusi sebelumnya
     * - Proposal sudah di-queue via `queueProposal`
     * - Timelock sudah habis (`block.timestamp >= queuedAt + timelockDuration`)
     *
     * Emits: {ProposalExecuted}
     */
    function executeProposal(uint256 proposalId) public nonReentrant {
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

    /**
     * @notice Mengambil informasi lengkap sebuah proposal
     * @dev    Mengembalikan semua field dari struct Proposal secara terpisah
     *         karena Solidity tidak bisa return struct langsung ke external caller
     *         pada versi ABI encoding lama. Kompatibel dengan IGovernance interface.
     * @param  proposalId  ID proposal yang ingin dicek
     * @return id          ID proposal
     * @return proposer    Alamat pembuat proposal
     * @return description Deskripsi proposal
     * @return yesVotes    Total yes votes yang diterima
     * @return noVotes     Total no votes yang diterima
     * @return deadline    Unix timestamp batas waktu voting
     * @return executed    true jika proposal sudah dieksekusi
     * @return passed      true jika proposal lolos voting dan dieksekusi
     */
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
}
