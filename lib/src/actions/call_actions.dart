part of '../../variance_dart.dart';

mixin _callActions on SmartWalletBase {
  /// The safe plugin
  ///  if this is a safe wallet, it must be set
  late final _SafeModule? _safe;

  /// Encodes a function call to execute a batch of operations in a smart wallet.
  ///
  /// Parameters:
  ///   - `walletAddress`: The [EthereumAddress] of the smart wallet.
  ///   - `recipients`: A list of [EthereumAddress] instances representing the recipients for each operation.
  ///   - `amounts`: Optional list of [EtherAmount] instances representing the amounts to transfer for each operation.
  ///   - `innerCalls`: Optional list of [Uint8List] instances containing inner call data for each operation.
  ///   - `isSafe`: An optional flag indicating whether the operation is a GnosisSafeOperation or not. defaults to false.
  ///
  /// Returns:
  ///   A [Uint8List] containing the ABI-encoded data for the 'executeBatch' function call.
  ///
  /// Example:
  /// ```dart
  /// var encodedCall = executeBatch(
  ///   walletAddress: EthereumAddress.fromHex('0x9876543210abcdef9876543210abcdef98765432'),
  ///   recipients: [
  ///     EthereumAddress.fromHex('0x1234567890abcdef1234567890abcdef12345678'),
  ///     EthereumAddress.fromHex('0xabcdef1234567890abcdef1234567890abcdef12'),
  ///   ],
  ///   amounts: [EtherAmount.zero(), EtherAmount.inWei(BigInt.from(1000000000000000000))],
  ///   innerCalls: [
  ///     Uint8List.fromList([...]),
  ///     Uint8List.fromList([]),
  ///   ],
  /// ); // first call contains call to 0x1234567890abcdef1234567890abcdef12345678 with 0 wei, second call contains call to 0xabcdef1234567890abcdef1234567890abcdef12 with 1000000000000000000 wei
  /// ```
  /// This method uses the 'executeBatch' function ABI to encode the smart wallet batch operation.
  Uint8List getExecuteBatchCalldata({
    required List<EthereumAddress> recipients,
    List<EtherAmount>? amounts,
    List<Uint8List>? innerCalls,
  }) {
    List params = [
      recipients,
      amounts?.map<BigInt>((e) => e.getInWei).toList() ??
          recipients.map<BigInt>((e) => BigInt.zero).toList(),
      innerCalls ?? Uint8List.fromList([]),
    ];

    if (innerCalls == null || innerCalls.isEmpty) {
      require(amounts != null && amounts.isNotEmpty, "malformed batch request");
    }

    String method = 'executeBatch';

    if (_safe != null) {
      method = 'executeUserOpWithErrorString';
      params = [
        [Addresses.safeMultiSendaddress],
        EtherAmount.zero().getInWei,
        _safe.getSafeMultisendCallData(recipients, amounts, innerCalls),
        BigInt.one
      ];
    }

    return Contract.encodeFunctionCall(
      method,
      address,
      ContractAbis.get(method),
      params,
    );
  }

  /// Encodes a function call to execute a user operation in a smart wallet.
  ///
  /// Parameters:
  ///   - `to`: The [EthereumAddress] of the target recipient for the operation.
  ///   - `amount`: The [EtherAmount] representing the amount to transfer, if applicable.
  ///   - `innerCallData`: The [Uint8List] containing inner call data, if applicable.
  ///
  /// Returns:
  ///   A [Uint8List] containing the ABI-encoded data for the 'execute' function call.
  ///
  /// Example:
  /// ```dart
  /// var encodedCall = execute(
  ///   to: EthereumAddress.fromHex('0x1234567890abcdef1234567890abcdef12345678'),
  ///   amount: EtherAmount.inWei(BigInt.from(1000000000000000000)),
  ///   innerCallData: Uint8List.fromList([]),
  /// ); // transfer to 0x1234567890abcdef1234567890abcdef12345678 with 1000000000000000000 wei
  /// ```
  /// This method uses the 'execute' function ABI to encode the smart wallet operation.
  Uint8List getExecuteCalldata({
    required EthereumAddress to,
    EtherAmount? amount,
    Uint8List? innerCallData,
  }) {
    final params = [
      to,
      amount?.getInWei ?? EtherAmount.zero().getInWei,
      innerCallData ?? Uint8List.fromList([]),
    ];

    String method = 'execute';

    if (_safe != null) {
      method = 'executeUserOpWithErrorString';
      params.add(BigInt.zero);
    }

    return Contract.encodeFunctionCall(
      method,
      address,
      ContractAbis.get(method),
      params,
    );
  }

  /// Generates a user operation for approving the transfer of an ERC-721 token.
  ///
  /// Parameters:
  ///   - `contractAddress`: The [EthereumAddress] of the ERC-721 token contract.
  ///   - `spender`: The [EthereumAddress] of the address to grant approval.
  ///   - `tokenId`: The [BigInt] representing the ID of the token to approve.
  ///
  /// Returns:
  ///   A [UserOperation] instance for the ERC-721 token approval operation.
  ///
  /// Example:
  /// ```dart
  /// var userOperation = nftApproveUserOperation(
  ///   EthereumAddress.fromHex('0x1234567890abcdef1234567890abcdef12345678'),
  ///   EthereumAddress.fromHex('0xabcdef1234567890abcdef1234567890abcdef12'),
  ///   BigInt.from(123),
  /// );
  /// ```
  /// This method combines the 'execute' function and 'encodeERC721ApproveCall' to create a user operation.
  UserOperation getNftApproveUserOperation(EthereumAddress contractAddress,
      EthereumAddress spender, BigInt tokenId) {
    final innerCallData = getExecuteCalldata(
        to: contractAddress,
        innerCallData: Contract.encodeERC721ApproveCall(
          contractAddress,
          spender,
          tokenId,
        ));
    return UserOperation.partial(callData: innerCallData);
  }

  /// Generates a user operation for transferring an ERC-721 token.
  ///
  /// Parameters:
  ///   - `contractAddress`: The [EthereumAddress] of the ERC-721 token contract.
  ///   - `recipient`: The [EthereumAddress] of the recipient to receive the token.
  ///   - `tokenId`: The [BigInt] representing the ID of the token to transfer.
  ///
  /// Returns:
  ///   A [UserOperation] instance for the ERC-721 token transfer operation.
  ///
  /// Example:
  /// ```dart
  /// var userOperation = nftTransferUserOperation(
  ///   EthereumAddress.fromHex('0x1234567890abcdef1234567890abcdef12345678'),
  ///   EthereumAddress.fromHex('0xabcdef1234567890abcdef1234567890abcdef12'),
  ///   BigInt.from(123),
  /// );
  /// ```
  /// This method combines the 'execute' function and 'encodeERC721SafeTransferCall' to create a user operation.
  UserOperation getNftTransferUserOperation(EthereumAddress contractAddress,
      EthereumAddress recipient, BigInt tokenId) {
    final innerCallData = getExecuteCalldata(
        to: contractAddress,
        innerCallData: Contract.encodeERC721SafeTransferFromCall(
          contractAddress,
          address,
          recipient,
          tokenId,
        ));
    return UserOperation.partial(callData: innerCallData);
  }

  /// Generates a user operation for approving the transfer of ERC-20 tokens.
  ///
  /// Parameters:
  ///   - `contractAddress`: The [EthereumAddress] of the ERC-20 token contract.
  ///   - `spender`: The [EthereumAddress] of the address to grant approval.
  ///   - `amount`: The [EtherAmount] representing the amount to approve.
  ///
  /// Returns:
  ///   A [UserOperation] instance for the ERC-20 token approval operation.
  ///
  /// Example:
  /// ```dart
  /// var userOperation = tokenApproveUserOperation(
  ///   EthereumAddress.fromHex('0x1234567890abcdef1234567890abcdef12345678'),
  ///   EthereumAddress.fromHex('0xabcdef1234567890abcdef1234567890abcdef12'),
  ///   EtherAmount.inWei(BigInt.from(1000000000000000000)),
  /// );
  /// ```
  /// This method combines the 'execute' function and 'encodeERC20ApproveCall' to create a user operation.
  UserOperation getTokenApproveUserOperation(
    EthereumAddress contractAddress,
    EthereumAddress spender,
    EtherAmount amount,
  ) {
    final callData = getExecuteCalldata(
        to: contractAddress,
        innerCallData:
            Contract.encodeERC20ApproveCall(contractAddress, spender, amount));
    return UserOperation.partial(callData: callData);
  }

  /// Generates a user operation for transferring ERC-20 tokens.
  ///
  /// Parameters:
  ///   - `contractAddress`: The [EthereumAddress] of the ERC-20 token contract.
  ///   - `recipient`: The [EthereumAddress] of the recipient to receive the tokens.
  ///   - `amount`: The [EtherAmount] representing the amount of tokens to transfer.
  ///
  /// Returns:
  ///   A [UserOperation] instance for the ERC-20 token transfer operation.
  ///
  /// Example:
  /// ```dart
  /// var userOperation = tokenTransferUserOperation(
  ///   EthereumAddress.fromHex('0x1234567890abcdef1234567890abcdef12345678'),
  ///   EthereumAddress.fromHex('0xabcdef1234567890abcdef1234567890abcdef12'),
  ///   EtherAmount.inWei(BigInt.from(1000000000000000000)),
  /// );
  /// ```
  /// This method combines the 'execute' function and 'encodeERC20TransferCall' to create a user operation.
  UserOperation getTokenTransferUserOperation(EthereumAddress contractAddress,
      EthereumAddress recipient, EtherAmount amount) {
    final callData = getExecuteCalldata(
        to: contractAddress,
        innerCallData: Contract.encodeERC20TransferCall(
            contractAddress, recipient, amount));
    return UserOperation.partial(callData: callData);
  }

  Future<Uint8List> getUserOperationHash(
      UserOperation op, BlockInformation blockInfo) async {
    return _safe != null
        ? _safe.getSafeOperationHash(op, blockInfo)
        : op.hash(chain);
  }

  Future<String Function(BlockInformation)> Function(
          Future<T> Function(T, {int? index}), int? index)
      _getUserOperationSignHandler<T extends Uint8List>(
          Future<T> Function() getHash) {
    return (Future<T> Function(T, {int? index}) sign, int? index) async {
      final hash = await getHash();
      final signature = await sign(hash);
      final signatureHex = hexlify(signature);
      return (BlockInformation blockInfo) => _safe != null
          ? _safe.getSafeSignature(signatureHex, blockInfo)
          : signatureHex;
    };
  }
}
