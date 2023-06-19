//SPDX-Licence-Identifier: GPL-3.0
pragma solidity ^0.8.0;
//////////////////////////////////////////////////////////////////////////////
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

contract Escrow is Ownable {
    using Strings for uint256;

    enum EscrowState { InProgress, Completed, Refunded, Disputed }

    struct Transaction {
        address payable buyer;
        address payable seller;
        uint256 amount;
        EscrowState state;
        bool exists;
        string encryptedItemMetadata;
        bytes32 itemHash;
        bool disputeResolved;
    }

    mapping(uint256 => Transaction) public transactions;
    uint256 public transactionCount;

    uint256 public escrowDuration; // Duration in seconds
    uint256 public escrowFee; // Fee in wei

    event EscrowCreated(uint256 indexed transactionId, address indexed buyer, address indexed seller, uint256 amount);
    event EscrowCompleted(uint256 indexed transactionId);
    event EscrowRefunded(uint256 indexed transactionId);
    event EscrowDisputed(uint256 indexed transactionId, bytes32 itemHash);
    event EscrowDisputeResolved(uint256 indexed transactionId);

    modifier onlyTransactionParticipant(uint256 transactionId) {
        require(
            transactions[transactionId].exists &&
            (msg.sender == transactions[transactionId].buyer || msg.sender == transactions[transactionId].seller),
            "Only transaction participants can perform this action"
        );
        _;
    }

    constructor(uint256 duration, uint256 fee) {
        escrowDuration = duration;
        escrowFee = fee;
    }

    function createEscrow(
        address payable seller,
        string calldata encryptedItemMetadata,
        bytes32 itemHash
    ) external payable returns (uint256) {
        require(msg.value > escrowFee, "Amount should be greater than the escrow fee");

        transactionCount++;
        Transaction storage transaction = transactions[transactionCount];
        transaction.buyer = payable(msg.sender);
        transaction.seller = seller;
        transaction.amount = msg.value - escrowFee;
        transaction.state = EscrowState.InProgress;
        transaction.exists = true;
        transaction.encryptedItemMetadata = encryptedItemMetadata;
        transaction.itemHash = itemHash;

        emit EscrowCreated(transactionCount, msg.sender, seller, transaction.amount);

        return transactionCount;
    }

    function completeEscrow(uint256 transactionId) external onlyTransactionParticipant(transactionId) {
        Transaction storage transaction = transactions[transactionId];
        require(transaction.state == EscrowState.InProgress, "Escrow is not in progress");

        transaction.state = EscrowState.Completed;

        emit EscrowCompleted(transactionId);

        payable(transaction.seller).transfer(transaction.amount);
    }

    function refundEscrow(uint256 transactionId) external onlyTransactionParticipant(transactionId) {
        Transaction storage transaction = transactions[transactionId];
        require(transaction.state == EscrowState.InProgress, "Escrow is not in progress");

        transaction.state = EscrowState.Refunded;

        emit EscrowRefunded(transactionId);

        payable(transaction.buyer).transfer(transaction.amount);
    }

    function disputeEscrow(uint256 transactionId) external onlyTransactionParticipant(transactionId) {
        Transaction storage transaction = transactions[transactionId];
        require(transaction.state == EscrowState.InProgress, "Escrow is not in progress");

        transaction.state = EscrowState.Disputed;

        emit EscrowDisputed(transactionId, transaction.itemHash);
    }

    function resolveDispute(uint256 transactionId, bool isResolved) external onlyOwner {
        Transaction storage transaction = transactions[transactionId];
        require(transaction.state == EscrowState.Disputed, "Escrow is not disputed");

        transaction.disputeResolved = isResolved;

        if (isResolved) {
            transaction.state = EscrowState.Completed;

            emit EscrowDisputeResolved(transactionId);

            payable(transaction.seller).transfer(transaction.amount);
        } else {
            transaction.state = EscrowState.Refunded;

            emit EscrowDisputeResolved(transactionId);

            payable(transaction.buyer).transfer(transaction.amount);
        }
    }

    function setEscrowDuration(uint256 duration) external onlyOwner {
        escrowDuration = duration;
    }

    function setEscrowFee(uint256 fee) external onlyOwner {
        escrowFee = fee;
    }

    function getTransactionMetadata(uint256 transactionId) external view returns (string memory) {
        return transactions[transactionId].encryptedItemMetadata;
    }

    function getItemHash(uint256 transactionId) external view returns (bytes32) {
        return transactions[transactionId].itemHash;
    }

    function withdrawBalance() external {
        uint256 balance = address(this).balance;
        require(balance > 0, "No balance to withdraw");

        payable(owner()).transfer(balance);
    }
}
