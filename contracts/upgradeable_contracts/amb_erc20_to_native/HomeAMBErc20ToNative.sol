pragma solidity 0.4.24;

import "./BasicAMBErc20ToNative.sol";
import "../BlockRewardBridge.sol";

/**
* @title HomeAMBErc20ToNative
* @dev Home mediator implementation for erc20-to-native bridge intended to work on top of AMB bridge.
* It is design to be used as implementation contract of EternalStorageProxy contract.
*/
contract HomeAMBErc20ToNative is BasicAMBErc20ToNative, BlockRewardBridge {
    bytes32 internal constant TOTAL_BURNT_COINS = 0x17f187b2e5d1f8770602b32c1159b85c9600859277fae1eaa9982e9bcf63384c; // keccak256(abi.encodePacked("totalBurntCoins"))

    /**
    * @dev Stores the initial parameters of the mediator.
    * @param _bridgeContract the address of the AMB bridge contract.
    * @param _mediatorContract the address of the mediator contract on the other network.
    * @param _dailyLimitMaxPerTxMinPerTxArray array with limit values for the assets to be bridged to the other network.
    *   [ 0 = dailyLimit, 1 = maxPerTx, 2 = minPerTx ]
    * @param _executionDailyLimitExecutionMaxPerTxArray array with limit values for the assets bridged from the other network.
    *   [ 0 = executionDailyLimit, 1 = executionMaxPerTx ]
    * @param _requestGasLimit the gas limit for the message execution.
    * @param _decimalShift number of decimals shift required to adjust the amount of tokens bridged.
    * @param _owner address of the owner of the mediator contract
    */
    function initialize(
        address _bridgeContract,
        address _mediatorContract,
        uint256[] _dailyLimitMaxPerTxMinPerTxArray, // [ 0 = dailyLimit, 1 = maxPerTx, 2 = minPerTx ]
        uint256[] _executionDailyLimitExecutionMaxPerTxArray, // [ 0 = executionDailyLimit, 1 = executionMaxPerTx ]
        uint256 _requestGasLimit,
        uint256 _decimalShift,
        address _owner,
        address _blockReward
    ) external onlyRelevantSender returns (bool) {
        _initialize(
            _bridgeContract,
            _mediatorContract,
            _dailyLimitMaxPerTxMinPerTxArray,
            _executionDailyLimitExecutionMaxPerTxArray,
            _requestGasLimit,
            _decimalShift,
            _owner
        );
        _setBlockRewardContract(_blockReward);
        setInitialize();
        return isInitialized();
    }

    /**
    * @dev Fallback method to be called to initiate the bridge operation of the native tokens to an erc20 representation
    * that the user will receive in the same address on the other network.
    */
    function() public payable {
        require(msg.data.length == 0);
        nativeTransfer(msg.sender);
    }

    /**
    * @dev Method to be called to initiate the bridge operation of the native tokens to an erc20 representation
    * that the user will receive in the address specified by parameter on the other network.
    * @param _receiver address that will receive the erc20 tokens on the other network.
    */
    function relayTokens(address _receiver) external payable {
        nativeTransfer(_receiver);
    }

    /**
    * @dev Updates an address of the block reward contract that is used for minting native coins.
    * @param _blockReward address of new block reward contract.
    */
    function setBlockRewardContract(address _blockReward) external onlyOwner {
        _setBlockRewardContract(_blockReward);
    }

    /**
    * @dev Retrieves address of the currently used block reward contract.
    * @return address of block reward contract.
    */
    function blockRewardContract() public view returns (IBlockReward) {
        return _blockRewardContract();
    }

    /**
    * @dev Retrieves total amount of burnt coins by bridge that happened during the withdrawal procedure.
    * @return amount of burnt coins.
    */
    function totalBurntCoins() public view returns (uint256) {
        return uintStorage[TOTAL_BURNT_COINS];
    }

    /**
    * @dev Validates the received native tokens and makes the request to unlock the erc20 tokens on the other network.
    * @param _receiver address that will receive the erc20 tokens on the other network.
    */
    function nativeTransfer(address _receiver) internal {
        // this check also validates that msg.value is positive, since minPerTx() > 0
        require(withinLimit(msg.value));

        IBlockReward blockReward = blockRewardContract();
        uint256 totalMinted = blockReward.mintedTotallyByBridge(address(this));
        uint256 totalBurnt = totalBurntCoins();
        require(msg.value <= totalMinted.sub(totalBurnt));

        setTotalSpentPerDay(getCurrentDay(), totalSpentPerDay(getCurrentDay()).add(msg.value));
        passMessage(msg.sender, _receiver, msg.value);

        setTotalBurntCoins(totalBurnt.add(msg.value));
        address(0).transfer(msg.value);
    }

    /**
    * @dev Internal function for updating amount of burnt coins by this bridge.
    * @param _amount new amount of burnt coins.
    */
    function setTotalBurntCoins(uint256 _amount) internal {
        uintStorage[TOTAL_BURNT_COINS] = _amount;
    }

    /**
    * @dev Mints the amount of native tokens that were bridged from the other network.
    * @param _receiver address that will receive the native tokens
    * @param _value amount of native tokens to be received
    */
    function executeActionOnBridgedTokens(address _receiver, uint256 _value) internal {
        uint256 valueToMint = _value.mul(10**decimalShift());
        bytes32 _messageId = messageId();

        IBlockReward blockReward = blockRewardContract();
        blockReward.addExtraReceiver(valueToMint, _receiver);
        emit TokensBridged(_receiver, valueToMint, _messageId);
    }

    /**
    * @dev Mints back the amount of native tokens that were bridged to the other network but failed.
    * @param _receiver address that will receive the native tokens
    * @param _value amount of native tokens to be received
    */
    function executeActionOnFixedTokens(address _receiver, uint256 _value) internal {
        IBlockReward blockReward = blockRewardContract();
        blockReward.addExtraReceiver(_value, _receiver);
    }

    /**
    * @dev Allows to transfer any locked token on this contract that is not part of the bridge operations.
    * Native tokens are not allowed to be claimed.
    * @param _token address of the token.
    * @param _to address that will receive the locked tokens on this contract.
    */
    function claimTokens(address _token, address _to) external onlyIfUpgradeabilityOwner validAddress(_to) {
        require(_token != address(0));
        claimValues(_token, _to);
    }

    /**
    * @dev Allows to send to the other network the amount of locked native tokens that can be forced into the contract
    * without the invocation of the required methods.
    * @param _receiver the address that will receive the tokens on the other network
    */
    function fixMediatorBalance(address _receiver) external onlyIfUpgradeabilityOwner {
        uint256 balance = address(this).balance;
        require(balance > 0);
        setTotalSpentPerDay(getCurrentDay(), totalSpentPerDay(getCurrentDay()).add(balance));
        passMessage(_receiver, _receiver, balance);
        address(0).transfer(balance);
    }
}
