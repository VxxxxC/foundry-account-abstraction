// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IAccount} from "@era/contracts/interfaces/IAccount.sol";
import {Transaction} from "@era/contracts/libraries/MemoryTransactionHelper.sol";
import {SystemContractsCaller} from "@era/contracts/libraries/SystemContractsCaller.sol";
import {NONCE_HOLDER_SYSTEM_CONTRACT} from "@era/contracts/Constants.sol";
import {INonceHolder} from "@era/contracts/interfaces/INonceHolder.sol";

contract ZkMinimalAccount is IAccount {
    /**
     * INFO: Account Abstraction Transaction flow on zkSync
     *
     * Lifecycle of type 113 (0x71) transaction
     * NOTE: msg.sender is the zkSync Bootloader contract
     *
     * Phase 1 : Validation
     *  - a. User send the transaction to the zkSync API client
     *  - b. zkSync API client check the nonce is unique by querying the NonceHolder system contract
     *  - c. zkSync API client call validateTransaction, which must update the nonce
     *  - d. zkSync API client check the nonce updated
     *  - e. zkSync API client call payForTransaction, or prepareForPaymaster & validateAnyPayForPaymasterTransaction if a paymaster is used
     *
     * Phase 2 : Execution
     *  - f. zkSync API client pass validated transacion to main node / sequencer ( For now they are the same )
     *  - g. The main node / sequencer call executeTransaction
     *  - h. If paymaster used, the postTransaction handler of the paymaster is called
     *
     */
    // NOTE: ***EXTERNAL FUNCTIONS***/
    /**
     * @notice must increase the nonce
     * @notice must validate the tx (check owner signed the tx)
     */
    function validateTransaction(bytes32 _txHash, bytes32 _suggestedSignedHash, Transaction calldata _transaction)
        external
        payable
        returns (bytes4 magic)
    {
        // call nonce holder to increase the nonce
        // call (x, y, z) -> system contract
        SystemContractsCaller.systemCallWithPropagatedRevert(
            uint32(gasleft()),
            address(NONCE_HOLDER_SYSTEM_CONTRACT),
            0,
            abi.encodeCall(INonceHolder.incrementMinNonceIfEquals, (_transaction.nonce))
        );
    }

    function executeTransaction(bytes32 _txHash, bytes32 _suggestedSignedHash, Transaction calldata _transaction)
        external
        payable {}

    // There is no point in providing possible signed hash in the `executeTransactionFromOutside` method,
    // since it typically should not be trusted.
    function executeTransactionFromOutside(Transaction calldata _transaction) external payable {}

    function payForTransaction(bytes32 _txHash, bytes32 _suggestedSignedHash, Transaction calldata _transaction)
        external
        payable {}

    function prepareForPaymaster(bytes32 _txHash, bytes32 _possibleSignedHash, Transaction calldata _transaction)
        external
        payable {}
}
