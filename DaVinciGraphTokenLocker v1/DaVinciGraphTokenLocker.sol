// SPDX-License-Identifier: MIT
// Specifies the license under which the code is distributed (MIT License).

// Website: davincigraph.io
// The website associated with this contract.

// Specifies the version of Solidity compiler to use.
pragma solidity ^0.8.0;

// Imports the SafeHTS library, which provides methods for safely interacting with Hedera Token Service (HTS).
import "./SafeHTS.sol";

// Imports the ReentrancyGuard contract from the OpenZeppelin Contracts package, which helps protect against reentrancy attacks.
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

// TokenLocker contract inherits ReentrancyGuard to prevent reentrancy attacks
contract DaVinciGraphTokenLocker is ReentrancyGuard {
    // Declares a public variable to store the fee for locking and withdrawing tokens.
    uint256 public fee;

    // Declares a public variable to store the contract owner's address.
    address public owner;

    // a public variable to hold a flag to wether owner can associate tokens to the contract or everybody else
    bool public onlyOwnerCanAssociate = true;

    // Declares a constant to represent the maximum allowed fee for the contract.
    uint256 public constant MAX_FEE = 10000000000; // 10_000_000_000 Tinybar = 100 HBAR

    // Declares a constant to represent the minimum balance required for contract for auto-renewal.
    uint256 public constant AUTO_RENEW_CONTRACT_BALANCE = 10000000000; // 10_000_000_000 Tinybar = 100 HBAR. HOLD 100 HBAR in The contract for AUTO_RENEW

    // Creates a modifier to restrict function access to the contract owner.
    modifier onlyOwner() {
        // Ensures that the function caller is the contract owner.
        require( msg.sender == owner, "Only the contract owner can perform this action." );
        _;
    }

    constructor() {
        // Sets the initial fee value.
        fee = 10000000000;
        // Sets the contract deployer as the initial owner.
        owner = msg.sender;
    }

    // Declares a receive function that accepts incoming Ether transfers.
    receive() external payable {}

    // Declares a fallback function that accepts incoming Ether transfers with non-empty data.
    fallback() external payable {}

    // Struct to store information about locked tokens
    struct LockedToken {
        int64 amount;// The amount of locked tokens.
        uint256 lockTimestamp;// The timestamp when tokens were locked.
        uint256 lockDuration;// The duration of the lock (in seconds).
    }

    // Creates a mapping to store LockedToken structs indexed by user and token addresses.
    mapping(address => mapping(address => LockedToken)) public _lockedTokens;

    // Function to associate a token with the contract
    function associateToken(address token) external {
        // Ensures that the token address is not zero.
        require(token != address(0), "Token address must be provided");

        // limit the association if only the owner is spouse to do so
        if( onlyOwnerCanAssociate == true){
            require( msg.sender == owner, "Currently only the contract owner can associate tokens to the contract." );
        }

        // Ensures that the token type is Fungible
        require( SafeHTS.safeGetTokenType(token) == 0, "Only fungible tokens are supported" );

        // Gets The Token Info
        IHederaTokenService.TokenInfo memory tokenInfo = SafeHTS.safeGetTokenInfo(token);

        // Ensures the token has no fixed fees
        require( tokenInfo.fixedFees.length == 0, "Tokens with custom fixed fees are not supported" );

        // Ensures the token has no fractional fees.
        require( tokenInfo.fractionalFees.length == 0, "Tokens with custom fractional fees are not supported" );

        // checks if fee schedule key is set or not
        for (uint i = 0; i < tokenInfo.token.tokenKeys.length; i++) {
            uint mask = 1 << 5; // Shift 1 to left by 5 places to create a mask for the 5th bit (the fee schedule key bit)
            if (tokenInfo.token.tokenKeys[i].keyType == mask) {
                // If the key is the feeScheduleKey, then check it's not set
                revertOnExistingKey(tokenInfo.token.tokenKeys[i].key);
            }
        }        

        // Calls the safeAssociateToken function from SafeHTS library to associate the token with the contract.
        SafeHTS.safeAssociateToken(token, address(this));

        // emit token association event
        emit TokenAssociated(token);
    }

    // Function to lock tokens for a specified duration (in seconds)
    function lockToken( address token, int64 amount, uint256 lockDurationInSeconds ) external payable {
        // Ensures that the HBAR sent with the transaction is greater than or equal to the required fee.
        require(msg.value >= fee, "Insufficient payment");

        // Ensures that the token address is not zero.
        require(token != address(0), "Token address must be provided");

        // Ensures that the lock amount is greater than zero.
        require(amount > 0, "Lock amount should be greater than 0");

        // Ensures that the lock duration is greater than zero.
        require( lockDurationInSeconds > 0, "Lock duration should be greater than 0" );

        // Ensures that the user has not already locked tokens of the same type.
        require( _lockedTokens[msg.sender][token].amount == 0, "You have already locked this token" );

        // Calls the safeTransferToken function from SafeHTS library to transfer the tokens from the user to the contract.
        SafeHTS.safeTransferToken(token, msg.sender, address(this), amount);

        // Stores the locked token information in the _lockedTokens mapping.
        _lockedTokens[msg.sender][token] = LockedToken( amount, block.timestamp, lockDurationInSeconds );

        // Emits a TokensLocked event with the user's address, token address, lock amount, and lock duration.
        emit TokenLocked(msg.sender, token, amount, lockDurationInSeconds);
    }

    // Function to increase the locked amount for a token
    function increaseLockAmount( address token, int64 additionalAmount ) external payable {
        // Ensures that the HBAR sent with the transaction is greater than or equal to the required fee.
        require(msg.value >= fee, "Insufficient payment");

        // Ensures that the token address is not zero.
        require(token != address(0), "Token address must be provided");

        // Ensures that the additional lock amount is greater than zero.
        require( additionalAmount > 0, "Increasing amount should be greater than 0" );

        // Ensures that the user has locked tokens of the same type.
        require( _lockedTokens[msg.sender][token].amount > 0, "You have not locked this token" );

        // Calls the safeTransferToken function from SafeHTS library to transfer the additional tokens from the user to the contract.
        SafeHTS.safeTransferToken( token, msg.sender, address(this), additionalAmount );

        // Updates the locked token amount for the user and token by adding the additional amount.
        _lockedTokens[msg.sender][token].amount = _lockedTokens[msg.sender][token].amount + additionalAmount;

        // Emits a LockedAmountIncreased event with the user's address, token address, and the additional lock amount.
        emit LockedAmountIncreased(msg.sender, token, additionalAmount);
    }

    // Function to increase the lock duration for a token (in seconds)
    function increaseLockDuration( address token, uint256 additionalDurationInSeconds ) external payable {
        // Ensures that the HBAR sent with the transaction is greater than or equal to the required fee.
        require(msg.value >= fee, "Insufficient payment");

        // Ensures that the token address is not zero.
        require(token != address(0), "Token address cannot be zero");

        // Ensures that the additional lock duration is greater than zero.
        require( additionalDurationInSeconds > 0, "Increasing Duration should be greater than 0" );

        // Ensures that the user has locked tokens of the same type.
        require( _lockedTokens[msg.sender][token].amount > 0, "You have not locked this token" );

        // Updates the locked token duration for the user and token by adding the additional duration.
        _lockedTokens[msg.sender][token].lockDuration = _lockedTokens[msg.sender][token].lockDuration + additionalDurationInSeconds;

        // Emits a LockDurationIncreased event with the user's address, token address, and the additional lock duration.
        emit LockDurationIncreased(msg.sender, token, additionalDurationInSeconds);
    }

    // Function to withdraw tokens after the lock duration has passed
    function withdrawToken(address token) external payable {
        // Ensures that the HBAR sent with the transaction is greater than or equal to the required fee.
        require(msg.value >= fee, "Insufficient payment");

        // Ensures that the token address is not zero.
        require(token != address(0), "Token address must be provided");

        // Ensures that the user has locked tokens of the same type.
        require( _lockedTokens[msg.sender][token].amount > 0, "You have not locked this token" );

        // Ensures that the lock duration has passed.
        require( block.timestamp >= _lockedTokens[msg.sender][token].lockTimestamp + _lockedTokens[msg.sender][token].lockDuration, "Lock duration is not over" );

        // Gets The Token Info
        (IHederaTokenService.FixedFee[] memory fixedFees, IHederaTokenService.FractionalFee[] memory fractionalFees,) = SafeHTS.safeGetTokenCustomFees(token);

        // Ensures the token has no fixed fees
        require( fixedFees.length == 0, "Tokens with custom fixed fees cannot be withdrawn" );

        // Ensures the token has no fractional fees.
        require( fractionalFees.length == 0, "Tokens with custom fractional fees cannot be withdrawn" );

        // Stores the locked token amount in a variable.
        int64 amount = _lockedTokens[msg.sender][token].amount;

        // Resets the locked token information for the user and token.
        delete _lockedTokens[msg.sender][token];

        // Calls the safeTransferToken function from SafeHTS library to transfer the tokens from the contract back to the user.
        SafeHTS.safeTransferToken(token, address(this), msg.sender, amount);

        // Emits a TokensWithdrawn event with the user's address, token address, and the withdrawn amount.
        emit TokenWithdrawn(msg.sender, token, amount);
    }

    // Function to get the locked amount and remaining lock duration for a user and token
    function getLockedDetails( address token ) external view returns (int64 lockedAmount, uint256 remainingLockDuration) {
        // Ensures that the token address is not zero.
        require(token != address(0), "Token address must be provided");

        // Retrieves the locked token amount for the user and token.
        LockedToken memory lockedToken = _lockedTokens[msg.sender][token];

        lockedAmount = lockedToken.amount;
        // Calculates the remaining lock duration if the lock duration has not passed.
        if ( block.timestamp < lockedToken.lockTimestamp + lockedToken.lockDuration ) {
            remainingLockDuration = lockedToken.lockDuration + lockedToken.lockTimestamp - block.timestamp;
            // Sets the remaining lock duration to 0 if the lock duration has passed.
        } else {
            remainingLockDuration = 0;
        }

        // Returns the locked amount and remaining lock duration.
        return (lockedAmount, remainingLockDuration);
    }

    function changeOnlyOwnerCanAssociate(bool _onlyOwnerCanAssociate) public onlyOwner {
        if( _onlyOwnerCanAssociate != onlyOwnerCanAssociate ){
            // change the state with new value
            onlyOwnerCanAssociate = _onlyOwnerCanAssociate;

            // emit the association actor changed event with new state
            emit AssociationActorChanged(onlyOwnerCanAssociate);
        }
    }

    // Updates the fee and emits a FeeUpdated event.
    function updateFee(uint256 _fee) public onlyOwner {
        // Require that the fee does not exceed the maximum allowed.
        require(_fee <= MAX_FEE, "Fee exceeds maximum allowed.");

        // Set the fee to the new value.
        fee = _fee;

        // Emit the FeeUpdated event with the new fee value.
        emit FeeUpdated(_fee);
    }

    // Change the owner of contract
    function changeOwner(address _newOwner) public onlyOwner {
        // Require that the new owner address is not zero.
        require(_newOwner != address(0), "Invalid new owner address.");

        if( _newOwner != owner ){
            // Emit the OwnerChanged event with the current owner and new owner addresses.
            emit OwnerChanged(owner, _newOwner);

            // Set the owner to the new owner address.
            owner = _newOwner;
        }
    }

    // WithdrawFees
    function withdrawFees() public onlyOwner nonReentrant {
        // Calculate the amount of fees available for withdrawal.
        uint256 withdrawalAmount = address(this).balance - AUTO_RENEW_CONTRACT_BALANCE;

        // Require that the withdrawal amount is greater than zero.
        require(withdrawalAmount > 0, "No balance to withdraw.");

        // Call the owner's address with the withdrawal amount and handle any errors.
        (bool success, ) = owner.call{value: withdrawalAmount}("");

        // Require that the withdrawal was successful.
        require(success, "Withdrawal failed.");

        // Emit the WithdrawnFees event with the owner's address and withdrawal amount.
        emit FeeWithdrawn(owner, withdrawalAmount);
    }

    function revertOnExistingKey(IHederaTokenService.KeyValue memory key) internal pure {
        require(key.contractId == address(0), "Tokens with fee schedule key are not supported");
        require(key.ed25519.length == 0, "Tokens with fee schedule key are not supported");
        require(key.ECDSA_secp256k1.length == 0, "Tokens with fee schedule key are not supported");
        require(key.delegatableContractId == address(0), "Tokens with fee schedule key are not supported");
    }

    // Defines events for logging actions performed by the contract
    event TokenAssociated(address indexed token);
    event TokenLocked(address indexed user, address indexed token, int64 amount, uint256 lockDuration);
    event LockedAmountIncreased(address indexed user, address indexed token, int64 additionalAmount);
    event LockDurationIncreased(address indexed user, address indexed token, uint256 additionalDuration);
    event TokenWithdrawn(address indexed user, address indexed token, int64 amount);
    event AssociationActorChanged(bool canOnlyOwnerAssociate);
    event FeeUpdated(uint256 newFee);
    event OwnerChanged(address indexed oldOwner, address indexed newOwner);
    event FeeWithdrawn(address indexed receiver, uint256 amount);
}
