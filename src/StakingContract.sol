// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title  StakingContract
 * @author Riko Tronic (github: tronic21-ctrl)
 * @notice Contract ini memungkinkan user untuk stake ETH dan mendapatkan reward
 *         berdasarkan durasi staking. Dibangun sebagai bagian dari TronicLens —
 *         DeFi Staking Intelligence Cockpit untuk ETHOnline 2026.
 * @dev    Menggunakan ETH native (bukan ERC-20) untuk simplisitas.
 *         Reward dihitung secara linear berdasarkan waktu (rewardRatePerSecond).
 *         Contract harus memiliki cukup ETH untuk membayar reward saat unstake.
 */
contract StakingContract is ReentrancyGuard {
    // ─────────────────────────────────────────────
    //  State Variables
    // ─────────────────────────────────────────────

    /// @notice Alamat owner contract (deployer)
    address public owner;

    /// @notice Jumlah ETH yang sedang di-stake oleh setiap user (dalam wei)
    mapping(address => uint256) public stakedAmount;

    /// @notice Timestamp (Unix) saat user mulai melakukan stake
    mapping(address => uint256) public stakeTimestamp;

    uint256 public constant MIN_STAKE_AMOUNT = 0.001 ether;
    uint256 public constant MAX_REWARD_RATE = 1000; // wei per detik

    /// @notice Reward yang diberikan per detik kepada staker (dalam wei)
    /// @dev    Nilai default: 1 wei/detik — bisa diubah oleh owner di versi berikutnya
    uint256 public rewardRatePerSecond = 1;

    /// @notice Minimum durasi staking sebelum user diizinkan unstake (dalam detik)
    /// @dev    Default: 60 detik. Mencegah flash staking untuk drain reward.
    uint256 public minimumStakePeriod = 60;

    // ─────────────────────────────────────────────
    //  Events
    // ─────────────────────────────────────────────

    /// @notice Emitted ketika user berhasil melakukan stake ETH
    /// @param user   Alamat user yang melakukan stake
    /// @param amount Jumlah ETH yang di-stake (dalam wei)
    event Staked(address indexed user, uint256 amount);

    /// @notice Emitted ketika user berhasil melakukan unstake ETH beserta reward
    /// @param user   Alamat user yang melakukan unstake
    /// @param amount Jumlah ETH pokok yang dikembalikan (dalam wei)
    /// @param reward Jumlah reward yang diterima user (dalam wei)
    event Unstaked(address indexed user, uint256 amount, uint256 reward);

    // ─────────────────────────────────────────────
    //  Constructor
    // ─────────────────────────────────────────────

    /// @notice Menginisialisasi contract dan menetapkan deployer sebagai owner
    constructor() {
        owner = msg.sender;
    }

    // ─────────────────────────────────────────────
    //  Modifiers
    // ─────────────────────────────────────────────

    /// @notice Membatasi akses function hanya untuk owner contract
    modifier onlyOwner() {
        require(msg.sender == owner, "Bukan owner");
        _;
    }

    // ─────────────────────────────────────────────
    //  External / Public Functions
    // ─────────────────────────────────────────────

    /**
     * @notice Melakukan stake ETH ke dalam contract
     * @dev    User hanya boleh memiliki satu posisi stake aktif pada satu waktu.
     *         ETH yang dikirim menjadi `stakedAmount[msg.sender]`.
     *         Timestamp dicatat untuk kalkulasi reward dan minimum period.
     *
     * Requirements:
     * - `msg.value` harus lebih dari 0
     * - User tidak boleh memiliki stake aktif sebelumnya
     *
     * Emits: {Staked}
     */

    function stake() public payable {
        require(msg.value > 0, "Harus stake lebih dari 0 ETH");
        require(stakedAmount[msg.sender] == 0, "Sudah ada stake aktif");
        require(msg.value >= MIN_STAKE_AMOUNT, "Stake minimum 0.001 ETH");

        stakedAmount[msg.sender] = msg.value;
        stakeTimestamp[msg.sender] = block.timestamp;

        emit Staked(msg.sender, msg.value);
    }

    /**
     * @notice Menghitung reward yang telah terakumulasi untuk seorang user
     * @dev    Formula: reward = durasi (detik) × rewardRatePerSecond
     *         Reward bersifat linear — tidak ada compounding.
     *         Mengembalikan 0 jika user tidak memiliki stake aktif.
     * @param  user Alamat user yang ingin dicek reward-nya
     * @return      Total reward yang terakumulasi (dalam wei)
     */
    function calculateReward(address user) public view returns (uint256) {
        if (stakedAmount[user] == 0) return 0;

        uint256 duration = block.timestamp - stakeTimestamp[user];
        return duration * rewardRatePerSecond;
    }

    /**
     * @notice Menarik kembali ETH yang di-stake beserta reward yang terakumulasi
     * @dev    State diubah SEBELUM transfer (Checks-Effects-Interactions pattern)
     *         untuk mencegah reentrancy attack.
     *         Transfer menggunakan `.call{value: ...}` bukan `.transfer()` untuk
     *         kompatibilitas gas yang lebih baik.
     *
     * Requirements:
     * - User harus memiliki stake aktif (`stakedAmount > 0`)
     * - Minimum staking period harus sudah terpenuhi
     * - Contract harus memiliki saldo cukup untuk membayar pokok + reward
     *
     * Emits: {Unstaked}
     */
    function unstake() public nonReentrant {
        require(stakedAmount[msg.sender] > 0, "Tidak ada stake aktif");
        require(
            block.timestamp >= stakeTimestamp[msg.sender] + minimumStakePeriod, "Minimum stake period belum tercapai"
        );

        uint256 amount = stakedAmount[msg.sender];
        uint256 reward = calculateReward(msg.sender);
        uint256 total = amount + reward;

        // Checks
        require(address(this).balance >= total, "Saldo kontrak tidak cukup");

        // Effects — ubah state dulu sebelum transfer (CEI pattern)
        stakedAmount[msg.sender] = 0;
        stakeTimestamp[msg.sender] = 0;

        // Interactions — baru transfer ETH
        (bool success,) = payable(msg.sender).call{value: amount + reward}("");
        require(success, "Transfer gagal");

        emit Unstaked(msg.sender, amount, reward);
    }

    /**
     * @notice Mengubah reward rate per detik (hanya owner)
     * @dev    Perubahan berlaku instan — mempengaruhi semua staker aktif
     * @param  newRate Reward baru dalam wei per detik
     */
    function setRewardRate(uint256 newRate) public onlyOwner {
        require(newRate <= MAX_REWARD_RATE, "Rate melebihi batas maksimal");
        rewardRatePerSecond = newRate;
    }

    /**
     * @notice Mengubah minimum periode staking (hanya owner)
     * @param  newPeriod Periode baru dalam detik
     */
    function setMinimumStakePeriod(uint256 newPeriod) public onlyOwner {
        minimumStakePeriod = newPeriod;
    }

    /**
     * @notice Mengambil informasi lengkap posisi staking seorang user
     * @dev    Convenience function — menggabungkan data dari beberapa mapping
     *         dan kalkulasi reward dalam satu call untuk efisiensi frontend.
     * @param  user      Alamat user yang ingin dicek
     * @return amount    Jumlah ETH yang sedang di-stake (dalam wei)
     * @return timestamp Unix timestamp saat user mulai stake
     * @return duration  Durasi staking hingga saat ini (dalam detik)
     * @return reward    Total reward yang terakumulasi (dalam wei)
     */
    function getStakeInfo(address user)
        public
        view
        returns (uint256 amount, uint256 timestamp, uint256 duration, uint256 reward)
    {
        amount = stakedAmount[user];
        timestamp = stakeTimestamp[user];
        duration = timestamp > 0 ? block.timestamp - timestamp : 0;
        reward = calculateReward(user);
    }

    // ─────────────────────────────────────────────
    //  Fallback
    // ─────────────────────────────────────────────

    /// @notice Menerima ETH langsung (digunakan untuk mengisi saldo reward contract)
    receive() external payable {}
}
