const HomeAMBErc677ToErc677 = artifacts.require('HomeAMBErc677ToErc677.sol')
const ForeignAMBErc677ToErc677 = artifacts.require('ForeignAMBErc677ToErc677.sol')
const ERC677BridgeToken = artifacts.require('ERC677BridgeToken.sol')
const HomeAMB = artifacts.require('HomeAMB.sol')
const AMBMock = artifacts.require('AMBMock.sol')
const BridgeValidators = artifacts.require('BridgeValidators.sol')

const { expect } = require('chai')
const { shouldBehaveLikeBasicAMBErc677ToErc677 } = require('./AMBErc677ToErc677Behavior.test')

const { ether } = require('../helpers/helpers')
const { getEvents, expectEventInLogs } = require('../helpers/helpers')
const { ERROR_MSG, toBN } = require('../setup')

const ZERO = toBN(0)
const oneEther = ether('1')
const twoEthers = ether('2')
const maxGasPerTx = oneEther
const dailyLimit = twoEthers
const maxPerTx = oneEther
const minPerTx = ether('0.01')
const executionDailyLimit = dailyLimit
const executionMaxPerTx = maxPerTx

contract('HomeAMBErc677ToErc677', async accounts => {
  const owner = accounts[0]
  const user = accounts[1]
  let ambBridgeContract
  let mediatorContract
  let erc677Token
  let homeBridge
  beforeEach(async function() {
    this.bridge = await HomeAMBErc677ToErc677.new()
  })
  shouldBehaveLikeBasicAMBErc677ToErc677(ForeignAMBErc677ToErc677, accounts)
  describe('onTokenTransfer', () => {
    beforeEach(async () => {
      const validatorContract = await BridgeValidators.new()
      const authorities = [accounts[1], accounts[2]]
      await validatorContract.initialize(1, authorities, owner)
      ambBridgeContract = await HomeAMB.new()
      await ambBridgeContract.initialize(validatorContract.address, maxGasPerTx, '1', '1', owner)
      mediatorContract = await ForeignAMBErc677ToErc677.new()
      erc677Token = await ERC677BridgeToken.new('test', 'TST', 18)
      await erc677Token.mint(user, twoEthers, { from: owner }).should.be.fulfilled

      homeBridge = await HomeAMBErc677ToErc677.new()
      await homeBridge.initialize(
        ambBridgeContract.address,
        mediatorContract.address,
        erc677Token.address,
        dailyLimit,
        maxPerTx,
        minPerTx,
        executionDailyLimit,
        executionMaxPerTx,
        maxGasPerTx,
        owner
      ).should.be.fulfilled
    })
    it('should emit UserRequestForSignature in AMB bridge and burn transferred tokens', async () => {
      // Given
      const currentDay = await homeBridge.getCurrentDay()
      expect(await homeBridge.totalSpentPerDay(currentDay)).to.be.bignumber.equal(ZERO)
      const initialEvents = await getEvents(ambBridgeContract, { event: 'UserRequestForSignature' })
      expect(initialEvents.length).to.be.equal(0)
      expect(await erc677Token.totalSupply()).to.be.bignumber.equal(twoEthers)

      // only token address can call it
      await homeBridge.onTokenTransfer(user, oneEther, '0x00', { from: owner }).should.be.rejectedWith(ERROR_MSG)

      // must be within limits
      await erc677Token
        .transferAndCall(homeBridge.address, twoEthers, '0x00', { from: user })
        .should.be.rejectedWith(ERROR_MSG)

      // When
      const { logs } = await erc677Token.transferAndCall(homeBridge.address, oneEther, '0x00', { from: user }).should.be
        .fulfilled

      // Then
      const events = await getEvents(ambBridgeContract, { event: 'UserRequestForSignature' })
      expect(events.length).to.be.equal(1)
      expect(await homeBridge.totalSpentPerDay(currentDay)).to.be.bignumber.equal(oneEther)
      expect(await erc677Token.totalSupply()).to.be.bignumber.equal(oneEther)
      expectEventInLogs(logs, 'Burn', {
        burner: homeBridge.address,
        value: oneEther
      })
    })
  })
  describe('handleBridgedTokens', () => {
    beforeEach(async () => {
      ambBridgeContract = await AMBMock.new()
      await ambBridgeContract.setMaxGasPerTx(maxGasPerTx)
      mediatorContract = await ForeignAMBErc677ToErc677.new()
      erc677Token = await ERC677BridgeToken.new('test', 'TST', 18)

      homeBridge = await HomeAMBErc677ToErc677.new()
      await homeBridge.initialize(
        ambBridgeContract.address,
        mediatorContract.address,
        erc677Token.address,
        dailyLimit,
        maxPerTx,
        minPerTx,
        executionDailyLimit,
        executionMaxPerTx,
        maxGasPerTx,
        owner
      ).should.be.fulfilled
      await erc677Token.transferOwnership(homeBridge.address)
    })
    it('should mint tokens on message from amb', async () => {
      // Given
      const currentDay = await homeBridge.getCurrentDay()
      expect(await homeBridge.totalExecutedPerDay(currentDay)).to.be.bignumber.equal(ZERO)
      const initialEvents = await getEvents(erc677Token, { event: 'Mint' })
      expect(initialEvents.length).to.be.equal(0)
      expect(await erc677Token.totalSupply()).to.be.bignumber.equal(ZERO)

      // can't be called by user
      await homeBridge.handleBridgedTokens(user, oneEther, { from: user }).should.be.rejectedWith(ERROR_MSG)
      // can't be called by owner
      await homeBridge.handleBridgedTokens(user, oneEther, { from: owner }).should.be.rejectedWith(ERROR_MSG)

      const data = await homeBridge.contract.methods.handleBridgedTokens(user, oneEther.toString()).encodeABI()
      const outOfLimitValueData = await homeBridge.contract.methods
        .handleBridgedTokens(user, twoEthers.toString())
        .encodeABI()

      // message must be generated by mediator contract on the other network
      await ambBridgeContract.executeMessageCall(homeBridge.address, owner, data).should.be.rejectedWith(ERROR_MSG)

      // out of limit value
      await ambBridgeContract
        .executeMessageCall(homeBridge.address, mediatorContract.address, outOfLimitValueData)
        .should.be.rejectedWith(ERROR_MSG)

      await ambBridgeContract.executeMessageCall(homeBridge.address, mediatorContract.address, data).should.be.fulfilled

      // Then
      expect(await homeBridge.totalExecutedPerDay(currentDay)).to.be.bignumber.equal(oneEther)
      const events = await getEvents(erc677Token, { event: 'Mint' })
      expect(events.length).to.be.equal(1)
      expect(events[0].returnValues.to).to.be.equal(user)
      expect(events[0].returnValues.amount).to.be.equal(oneEther.toString())
      expect(await erc677Token.totalSupply()).to.be.bignumber.equal(oneEther)
      expect(await erc677Token.balanceOf(user)).to.be.bignumber.equal(oneEther)
    })
  })
})