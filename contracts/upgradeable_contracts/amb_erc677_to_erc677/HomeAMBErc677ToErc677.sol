pragma solidity 0.4.24;

import "./BasicAMBErc677ToErc677.sol";
import "../ERC677BridgeForBurnableMintableToken.sol";
import "openzeppelin-solidity/contracts/AddressUtils.sol";

contract HomeAMBErc677ToErc677 is BasicAMBErc677ToErc677, ERC677BridgeForBurnableMintableToken {
    function executeActionOnBridgedTokens(address _recipient, uint256 _value) internal {
        IBurnableMintableERC677Token(erc677token()).mint(_recipient, _value);
    }
}
