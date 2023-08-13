// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.19;

import "./utils/Base64.sol";
import "./interfaces/IPasskeys.sol";
import "./library/Secp256r1.sol";
import "./interfaces/IGnosisSafe.sol";

/// NOTE::::: PLEASE NOTE
/// this is a proof of concept. adding and removing passkeys is disabled

contract PassKeysModule is IPassKeys {
    string public constant NAME = "Passkeys Module";
    string public constant VERSION = "0.1.0";

    bytes32 public constant DOMAIN_SEPARATOR_TYPEHASH =
        0x47e79534a245952e8b16893a336b85a3d9ea9fa8c573f3d803afb92a79469218;
    // keccak256(
    //     "EIP712Domain(uint256 chainId,address verifyingContract)"
    // );

    bytes32 public constant PASSKEYS_EXECUTE_TYPEHASH =
        0x4b1aafe0f3026a7149870f449a15e610283b3a1335f158999d91f0e0a8199900;
    // keccak256(
    //     "PasskeysExecute(address safe,address to,uint240 value,uint16 nonce,bytes calldata data)"
    // );

    // other storages
    mapping(bytes32 => PassKeyId) private authorisedKeys;
    bytes32[] private knownKeyHashes;

    // nonce... everyone is free to check.
    mapping(uint16 => bool) public usedNonces;

    constructor(string memory _keyId, uint256 _pubKeyX, uint256 _pubKeyY) {
        _addPassKey(keccak256(abi.encodePacked(_keyId)), _pubKeyX, _pubKeyY, _keyId);
    }

    /// @dev Allows to execute a transaction with biometrics.
    /// @param safe The Safe whose funds should be used.
    /// @param to destination contract address.
    /// @param value Amount that passed with the call.
    /// @param nonce unique for every passkeys execute.
    /// @param data tx calldata.
    /// @param signature Signature generated by webauthn.
    function executeWithPasskeys(
        address safe,
        address payable to,
        uint240 value,
        uint16 nonce,
        bytes calldata data,
        bytes calldata signature
    ) external {
        // check if the nonce is used
        require(!usedNonces[nonce], "invalid nonce");
        usedNonces[nonce] = true;

        // recover the signature
        bytes32 execHashData = keccak256(generateExecHashData(address(safe), to, value, nonce));
        validateSignature(signature, execHashData);

        // execute the transaction
        execTransaction(IGnosisSafe(safe), to, value, data);
    }

    /// @dev Returns the chain id used by this contract.
    function getChainId() public view returns (uint256) {
        uint256 id;
        // solium-disable-next-line security/no-inline-assembly
        assembly {
            id := chainid()
        }
        return id;
    }

    /// @dev Generates the data for the transfer hash (required for signing)
    function generateExecHashData(
        address safe,
        address to,
        uint240 value,
        uint16 nonce
    ) private view returns (bytes memory) {
        uint256 chainId = getChainId();
        bytes32 domainSeparator = keccak256(abi.encode(DOMAIN_SEPARATOR_TYPEHASH, chainId, this));
        bytes32 execHash = keccak256(abi.encode(PASSKEYS_EXECUTE_TYPEHASH, safe, to, value, nonce));
        return abi.encodePacked(bytes1(0x19), bytes1(0x01), domainSeparator, execHash);
    }

    /// @dev Generates the transfer hash that should be signed to authorize a transfer
    function generateExecHash(address safe, address to, uint240 value, uint16 nonce) external view returns (bytes32) {
        return keccak256(generateExecHashData(safe, to, value, nonce));
    }

    function validateSignature(bytes memory signature, bytes32 execHash) private view {
        (
            bytes32 keyHash,
            uint256 sigx,
            uint256 sigy,
            bytes memory authenticatorData,
            string memory clientDataJSONPre,
            string memory clientDataJSONPost
        ) = abi.decode(signature, (bytes32, uint256, uint256, bytes, string, string));

        string memory execHashBase64 = Base64.encode(bytes.concat(execHash));
        string memory clientDataJSON = string.concat(clientDataJSONPre, execHashBase64, clientDataJSONPost);
        bytes32 clientHash = sha256(bytes(clientDataJSON));
        bytes32 sigHash = sha256(bytes.concat(authenticatorData, clientHash));

        PassKeyId memory passKey = authorisedKeys[keyHash];
        require(passKey.pubKeyY != 0 && passKey.pubKeyY != 0, "Key not found");
        require(Secp256r1.Verify(passKey, sigx, sigy, uint256(sigHash)), "Invalid signature");
    }

    //execute transaction from gnosis safe
    function execTransaction(IGnosisSafe safe, address payable to, uint256 value, bytes calldata data) private {
        require(safe.execTransactionFromModule(to, value, data, Operation.Call), "execute from module failed");
    }

    function _addPassKey(bytes32 _keyHash, uint256 _pubKeyX, uint256 _pubKeyY, string memory _keyId) private {
        emit PublicKeyAdded(_keyHash, _pubKeyX, _pubKeyY, _keyId);
        authorisedKeys[_keyHash] = PassKeyId(_pubKeyX, _pubKeyY, _keyId);
        knownKeyHashes.push(_keyHash);
    }

    /**
     * Allows the owner to add a passkey key.
     * @param _keyId the id of the key
     * @param _pubKeyX public key X val from a passkey that will have a full ownership and control of this account.
     * @param _pubKeyY public key X val from a passkey that will have a full ownership and control of this account.
     */
    function addPassKey(string memory _keyId, uint256 _pubKeyX, uint256 _pubKeyY) external {
        require(false == true, "disabled"); // disabling this function for now
        _addPassKey(keccak256(abi.encodePacked(_keyId)), _pubKeyX, _pubKeyY, _keyId);
    }

    function removePassKey(string calldata _keyId) external {
        require(false == true, "disabled"); // disabling this function for now
        require(knownKeyHashes.length > 1, "Cannot remove the last key");
        bytes32 keyHash = keccak256(abi.encodePacked(_keyId));
        PassKeyId memory passKey = authorisedKeys[keyHash];
        if (passKey.pubKeyX == 0 && passKey.pubKeyY == 0) {
            return;
        }
        delete authorisedKeys[keyHash];
        for (uint256 i = 0; i < knownKeyHashes.length; i++) {
            if (knownKeyHashes[i] == keyHash) {
                knownKeyHashes[i] = knownKeyHashes[knownKeyHashes.length - 1];
                knownKeyHashes.pop();
                break;
            }
        }
        emit PublicKeyRemoved(keyHash, passKey.pubKeyX, passKey.pubKeyY, passKey.keyId);
    }

    /// @inheritdoc IPassKeys
    function getAuthorisedKeys() external view override returns (PassKeyId[] memory knownKeys) {
        knownKeys = new PassKeyId[](knownKeyHashes.length);
        for (uint256 i = 0; i < knownKeyHashes.length; i++) {
            knownKeys[i] = authorisedKeys[knownKeyHashes[i]];
        }
        return knownKeys;
    }
}
