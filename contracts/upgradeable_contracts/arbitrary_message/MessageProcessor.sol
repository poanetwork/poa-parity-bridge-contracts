pragma solidity 0.4.24;

import "../../upgradeability/EternalStorage.sol";
import "../../libraries/Bytes.sol";

contract MessageProcessor is EternalStorage {
    bytes32 internal constant MESSAGE_SENDER = 0x7b58b2a669d8e0992eae9eaef641092c0f686fd31070e7236865557fa1571b5b; // keccak256(abi.encodePacked("messageSender"))
    bytes32 internal constant MESSAGE_ID = 0xe34bb2103dc34f2c144cc216c132d6ffb55dac57575c22e089161bbe65083304; // keccak256(abi.encodePacked("messageId"))

    function messageCallStatus(bytes32 _messageId) external view returns (bool) {
        return boolStorage[keccak256(abi.encodePacked("messageCallStatus", _messageId))];
    }

    function setMessageCallStatus(bytes32 _messageId, bool _status) internal {
        boolStorage[keccak256(abi.encodePacked("messageCallStatus", _messageId))] = _status;
    }

    function failedMessageDataHash(bytes32 _messageId) external view returns (bytes32) {
        bytes32 id = keccak256(abi.encodePacked("failedMessageDataHash", _messageId));
        uint256 dataHash = uintStorage[id];
        if (dataHash > 0) {
            return bytes32(dataHash);
        }
        // previous version of the contract used bytesStorage for storing bytes32
        // this is needed for backwards compatibility with already saved data hashes
        return Bytes.bytesToBytes32(bytesStorage[id]);
    }

    function setFailedMessageDataHash(bytes32 _messageId, bytes data) internal {
        uintStorage[keccak256(abi.encodePacked("failedMessageDataHash", _messageId))] = uint256(keccak256(data));
    }

    function failedMessageReceiver(bytes32 _messageId) external view returns (address) {
        return addressStorage[keccak256(abi.encodePacked("failedMessageReceiver", _messageId))];
    }

    function setFailedMessageReceiver(bytes32 _messageId, address _receiver) internal {
        addressStorage[keccak256(abi.encodePacked("failedMessageReceiver", _messageId))] = _receiver;
    }

    function failedMessageSender(bytes32 _messageId) external view returns (address) {
        return addressStorage[keccak256(abi.encodePacked("failedMessageSender", _messageId))];
    }

    function setFailedMessageSender(bytes32 _messageId, address _sender) internal {
        addressStorage[keccak256(abi.encodePacked("failedMessageSender", _messageId))] = _sender;
    }

    function messageSender() external view returns (address) {
        return addressStorage[MESSAGE_SENDER];
    }

    function setMessageSender(address _sender) internal {
        addressStorage[MESSAGE_SENDER] = _sender;
    }

    function messageId() public view returns (bytes32) {
        return bytes32(uintStorage[MESSAGE_ID]);
    }

    function transactionHash() external view returns (bytes32) {
        return messageId();
    }

    function setMessageId(bytes32 _messageId) internal {
        uintStorage[MESSAGE_ID] = uint256(_messageId);
    }

    function processMessage(
        address _sender,
        address _executor,
        bytes32 _messageId,
        uint256 _gasLimit,
        bytes1, /* dataType */
        uint256, /* gasPrice */
        bytes memory _data
    ) internal {
        bool status = _passMessage(_sender, _executor, _data, _gasLimit, _messageId);

        setMessageCallStatus(_messageId, status);
        if (!status) {
            setFailedMessageDataHash(_messageId, _data);
            setFailedMessageReceiver(_messageId, _executor);
            setFailedMessageSender(_messageId, _sender);
        }
        emitEventOnMessageProcessed(_sender, _executor, _messageId, status);
    }

    function _passMessage(address _sender, address _contract, bytes _data, uint256 _gas, bytes32 _messageId)
        internal
        returns (bool)
    {
        setMessageSender(_sender);
        setMessageId(_messageId);
        bool status = _contract.call.gas(_gas)(_data);
        setMessageSender(address(0));
        setMessageId(bytes32(0));
        return status;
    }

    /* solcov ignore next */
    function emitEventOnMessageProcessed(address sender, address executor, bytes32 messageId, bool status) internal;
}
