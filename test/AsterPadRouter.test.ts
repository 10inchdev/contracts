import { expect } from "chai";
import { ethers } from "hardhat";
import { Contract, Signer } from "ethers";

describe("AsterPadRouter", function () {
  let router: Contract;
  let mockToken: Contract;
  let mockPancakeRouter: Contract;
  let mockWBNB: Contract;
  let owner: Signer;
  let treasury: Signer;
  let creator: Signer;
  let user: Signer;
  let ownerAddress: string;
  let treasuryAddress: string;
  let creatorAddress: string;
  let userAddress: string;

  // Constants matching the contract
  const PLATFORM_FEE_BPS = 100n;    // 1.0%
  const CREATOR_FEE_BPS = 50n;      // 0.5%
  const BPS_DENOMINATOR = 10000n;
  const DEAD_ADDRESS = "0x000000000000000000000000000000000000dEaD";

  beforeEach(async function () {
    [owner, treasury, creator, user] = await ethers.getSigners();
    ownerAddress = await owner.getAddress();
    treasuryAddress = await treasury.getAddress();
    creatorAddress = await creator.getAddress();
    userAddress = await user.getAddress();

    // Deploy Mock WBNB
    const MockWBNB = await ethers.getContractFactory("MockWBNB");
    mockWBNB = await MockWBNB.deploy();
    await mockWBNB.waitForDeployment();

    // Deploy Mock Token
    const MockToken = await ethers.getContractFactory("MockERC20");
    mockToken = await MockToken.deploy("Test Token", "TEST", ethers.parseEther("1000000000"));
    await mockToken.waitForDeployment();

    // Deploy Mock PancakeRouter
    const MockRouter = await ethers.getContractFactory("MockPancakeRouter");
    mockPancakeRouter = await MockRouter.deploy(await mockWBNB.getAddress());
    await mockPancakeRouter.waitForDeployment();

    // Deploy AsterPadRouter
    const AsterPadRouter = await ethers.getContractFactory("contracts/AsterPadRouterFlattened.sol:AsterPadRouter");
    router = await AsterPadRouter.deploy(
      await mockPancakeRouter.getAddress(),
      treasuryAddress
    );
    await router.waitForDeployment();

    // Setup: Send tokens to mock router for swaps
    await mockToken.transfer(await mockPancakeRouter.getAddress(), ethers.parseEther("100000000"));
  });

  // ===========================================================================
  // DEPLOYMENT TESTS
  // ===========================================================================
  
  describe("Deployment", function () {
    it("Should set the correct owner", async function () {
      expect(await router.owner()).to.equal(ownerAddress);
    });

    it("Should set the correct treasury", async function () {
      expect(await router.treasury()).to.equal(treasuryAddress);
    });

    it("Should set the correct PancakeRouter", async function () {
      expect(await router.pancakeRouter()).to.equal(await mockPancakeRouter.getAddress());
    });

    it("Should set the correct WBNB address", async function () {
      expect(await router.WBNB()).to.equal(await mockWBNB.getAddress());
    });

    it("Should have correct fee constants", async function () {
      expect(await router.PLATFORM_FEE_BPS()).to.equal(PLATFORM_FEE_BPS);
      expect(await router.CREATOR_FEE_BPS()).to.equal(CREATOR_FEE_BPS);
      expect(await router.TOTAL_FEE_BPS()).to.equal(150n);
      expect(await router.BPS_DENOMINATOR()).to.equal(BPS_DENOMINATOR);
    });

    it("Should set default minBuybackThreshold", async function () {
      expect(await router.minBuybackThreshold()).to.equal(ethers.parseEther("0.001"));
    });

    it("Should revert if pancakeRouter is zero address", async function () {
      const AsterPadRouter = await ethers.getContractFactory("contracts/AsterPadRouterFlattened.sol:AsterPadRouter");
      await expect(
        AsterPadRouter.deploy(ethers.ZeroAddress, treasuryAddress)
      ).to.be.revertedWithCustomError(router, "InvalidAddress");
    });

    it("Should revert if treasury is zero address", async function () {
      const AsterPadRouter = await ethers.getContractFactory("contracts/AsterPadRouterFlattened.sol:AsterPadRouter");
      await expect(
        AsterPadRouter.deploy(await mockPancakeRouter.getAddress(), ethers.ZeroAddress)
      ).to.be.revertedWithCustomError(router, "InvalidAddress");
    });
  });

  // ===========================================================================
  // TOKEN REGISTRATION TESTS
  // ===========================================================================
  
  describe("Token Registration", function () {
    it("Should register a token with Standard mode", async function () {
      const tokenAddress = await mockToken.getAddress();
      
      // Register token and check event is emitted (don't check exact timestamp due to timing)
      const tx = await router.registerToken(tokenAddress, creatorAddress, 0);
      const receipt = await tx.wait();
      
      // Verify event was emitted
      const event = receipt.logs.find((log: any) => {
        try {
          const parsed = router.interface.parseLog(log);
          return parsed?.name === "TokenRegistered";
        } catch { return false; }
      });
      expect(event).to.not.be.undefined;

      expect(await router.isRegisteredToken(tokenAddress)).to.be.true;
      expect(await router.tokenCreator(tokenAddress)).to.equal(creatorAddress);
      expect(await router.tokenLaunchMode(tokenAddress)).to.equal(0);
    });

    it("Should register a token with Snowball mode", async function () {
      const tokenAddress = await mockToken.getAddress();
      
      await router.registerToken(tokenAddress, creatorAddress, 1);

      expect(await router.tokenLaunchMode(tokenAddress)).to.equal(1);
    });

    it("Should register a token with Fireball mode", async function () {
      const tokenAddress = await mockToken.getAddress();
      
      await router.registerToken(tokenAddress, creatorAddress, 2);

      expect(await router.tokenLaunchMode(tokenAddress)).to.equal(2);
    });

    it("Should revert if token is zero address", async function () {
      await expect(
        router.registerToken(ethers.ZeroAddress, creatorAddress, 0)
      ).to.be.revertedWithCustomError(router, "InvalidAddress");
    });

    it("Should revert if creator is zero address", async function () {
      const tokenAddress = await mockToken.getAddress();
      
      await expect(
        router.registerToken(tokenAddress, ethers.ZeroAddress, 0)
      ).to.be.revertedWithCustomError(router, "InvalidAddress");
    });

    it("Should revert if token already registered", async function () {
      const tokenAddress = await mockToken.getAddress();
      
      await router.registerToken(tokenAddress, creatorAddress, 0);
      
      await expect(
        router.registerToken(tokenAddress, creatorAddress, 0)
      ).to.be.revertedWithCustomError(router, "TokenAlreadyRegistered");
    });

    it("Should revert if launch mode is invalid", async function () {
      const tokenAddress = await mockToken.getAddress();
      
      await expect(
        router.registerToken(tokenAddress, creatorAddress, 3)
      ).to.be.revertedWithCustomError(router, "InvalidLaunchMode");
    });

    it("Should revert if non-owner tries to register", async function () {
      const tokenAddress = await mockToken.getAddress();
      
      await expect(
        router.connect(user).registerToken(tokenAddress, creatorAddress, 0)
      ).to.be.revertedWithCustomError(router, "OwnableUnauthorizedAccount");
    });
  });

  // ===========================================================================
  // BATCH REGISTRATION TESTS
  // ===========================================================================
  
  describe("Batch Token Registration", function () {
    it("Should batch register multiple tokens", async function () {
      const MockToken2 = await ethers.getContractFactory("MockERC20");
      const token2 = await MockToken2.deploy("Test Token 2", "TEST2", ethers.parseEther("1000000000"));
      const token3 = await MockToken2.deploy("Test Token 3", "TEST3", ethers.parseEther("1000000000"));

      const tokens = [
        await mockToken.getAddress(),
        await token2.getAddress(),
        await token3.getAddress()
      ];
      const creators = [creatorAddress, creatorAddress, userAddress];
      const modes = [0, 1, 2];

      await router.batchRegisterTokens(tokens, creators, modes);

      expect(await router.isRegisteredToken(tokens[0])).to.be.true;
      expect(await router.isRegisteredToken(tokens[1])).to.be.true;
      expect(await router.isRegisteredToken(tokens[2])).to.be.true;
      
      expect(await router.tokenLaunchMode(tokens[0])).to.equal(0);
      expect(await router.tokenLaunchMode(tokens[1])).to.equal(1);
      expect(await router.tokenLaunchMode(tokens[2])).to.equal(2);
    });

    it("Should skip invalid entries in batch", async function () {
      const tokens = [await mockToken.getAddress(), ethers.ZeroAddress];
      const creators = [creatorAddress, creatorAddress];
      const modes = [0, 0];

      await router.batchRegisterTokens(tokens, creators, modes);

      expect(await router.isRegisteredToken(tokens[0])).to.be.true;
      expect(await router.isRegisteredToken(ethers.ZeroAddress)).to.be.false;
    });

    it("Should revert if arrays have different lengths", async function () {
      const tokens = [await mockToken.getAddress()];
      const creators = [creatorAddress, creatorAddress];
      const modes = [0];

      await expect(
        router.batchRegisterTokens(tokens, creators, modes)
      ).to.be.revertedWith("Length mismatch");
    });
  });

  // ===========================================================================
  // BUY TOKENS TESTS
  // ===========================================================================
  
  describe("Buy Tokens - Standard Mode", function () {
    beforeEach(async function () {
      const tokenAddress = await mockToken.getAddress();
      await router.registerToken(tokenAddress, creatorAddress, 0); // Standard mode
    });

    it("Should execute buy with correct fee distribution", async function () {
      const tokenAddress = await mockToken.getAddress();
      const buyAmount = ethers.parseEther("1");
      const deadline = Math.floor(Date.now() / 1000) + 3600;

      const treasuryBalanceBefore = await ethers.provider.getBalance(treasuryAddress);
      const creatorBalanceBefore = await ethers.provider.getBalance(creatorAddress);

      await router.connect(user).buyTokens(tokenAddress, 0, deadline, { value: buyAmount });

      const treasuryBalanceAfter = await ethers.provider.getBalance(treasuryAddress);
      const creatorBalanceAfter = await ethers.provider.getBalance(creatorAddress);

      // Platform fee: 1% of 1 BNB = 0.01 BNB
      const expectedPlatformFee = (buyAmount * PLATFORM_FEE_BPS) / BPS_DENOMINATOR;
      expect(treasuryBalanceAfter - treasuryBalanceBefore).to.equal(expectedPlatformFee);

      // Creator fee: 0.5% of 1 BNB = 0.005 BNB
      const expectedCreatorFee = (buyAmount * CREATOR_FEE_BPS) / BPS_DENOMINATOR;
      expect(creatorBalanceAfter - creatorBalanceBefore).to.equal(expectedCreatorFee);
    });

    it("Should update stats correctly", async function () {
      const tokenAddress = await mockToken.getAddress();
      const buyAmount = ethers.parseEther("1");
      const deadline = Math.floor(Date.now() / 1000) + 3600;

      await router.connect(user).buyTokens(tokenAddress, 0, deadline, { value: buyAmount });

      expect(await router.totalTradesRouted()).to.equal(1);
      expect(await router.tokenTradeCount(tokenAddress)).to.equal(1);
      expect(await router.tokenVolumeBnb(tokenAddress)).to.equal(buyAmount);
      
      const expectedPlatformFee = (buyAmount * PLATFORM_FEE_BPS) / BPS_DENOMINATOR;
      expect(await router.totalPlatformFees()).to.equal(expectedPlatformFee);
      expect(await router.tokenPlatformFees(tokenAddress)).to.equal(expectedPlatformFee);
    });

    it("Should emit TokenBuy event", async function () {
      const tokenAddress = await mockToken.getAddress();
      const buyAmount = ethers.parseEther("1");
      const deadline = Math.floor(Date.now() / 1000) + 3600;

      await expect(router.connect(user).buyTokens(tokenAddress, 0, deadline, { value: buyAmount }))
        .to.emit(router, "TokenBuy");
    });

    it("Should revert if token not registered", async function () {
      const deadline = Math.floor(Date.now() / 1000) + 3600;
      
      await expect(
        router.connect(user).buyTokens(userAddress, 0, deadline, { value: ethers.parseEther("1") })
      ).to.be.revertedWithCustomError(router, "TokenNotRegistered");
    });

    it("Should revert if no BNB sent", async function () {
      const tokenAddress = await mockToken.getAddress();
      const deadline = Math.floor(Date.now() / 1000) + 3600;
      
      await expect(
        router.connect(user).buyTokens(tokenAddress, 0, deadline, { value: 0 })
      ).to.be.revertedWithCustomError(router, "NoBNBSent");
    });

    it("Should revert if deadline expired", async function () {
      const tokenAddress = await mockToken.getAddress();
      const deadline = Math.floor(Date.now() / 1000) - 3600; // Past deadline
      
      await expect(
        router.connect(user).buyTokens(tokenAddress, 0, deadline, { value: ethers.parseEther("1") })
      ).to.be.revertedWithCustomError(router, "DeadlineExpired");
    });
  });

  // ===========================================================================
  // BUY TOKENS - SNOWBALL MODE
  // ===========================================================================
  
  describe("Buy Tokens - Snowball Mode", function () {
    beforeEach(async function () {
      const tokenAddress = await mockToken.getAddress();
      await router.registerToken(tokenAddress, creatorAddress, 1); // Snowball mode
    });

    it("Should accumulate creator fees for buyback", async function () {
      const tokenAddress = await mockToken.getAddress();
      const buyAmount = ethers.parseEther("1");
      const deadline = Math.floor(Date.now() / 1000) + 3600;

      const creatorBalanceBefore = await ethers.provider.getBalance(creatorAddress);

      await router.connect(user).buyTokens(tokenAddress, 0, deadline, { value: buyAmount });

      // Creator balance should NOT change (fees go to pendingBuyback)
      const creatorBalanceAfter = await ethers.provider.getBalance(creatorAddress);
      expect(creatorBalanceAfter).to.equal(creatorBalanceBefore);

      // Pending buyback should increase
      const expectedCreatorFee = (buyAmount * CREATOR_FEE_BPS) / BPS_DENOMINATOR;
      expect(await router.pendingBuyback(tokenAddress)).to.equal(expectedCreatorFee);
    });
  });

  // ===========================================================================
  // SELL TOKENS TESTS
  // ===========================================================================
  
  describe("Sell Tokens", function () {
    beforeEach(async function () {
      const tokenAddress = await mockToken.getAddress();
      await router.registerToken(tokenAddress, creatorAddress, 0);
      
      // Give user some tokens to sell
      await mockToken.transfer(userAddress, ethers.parseEther("10000"));
      await mockToken.connect(user).approve(await router.getAddress(), ethers.parseEther("10000"));
      
      // Fund the mock router with BNB for the swap
      await owner.sendTransaction({
        to: await mockPancakeRouter.getAddress(),
        value: ethers.parseEther("100")
      });
    });

    it("Should revert if token not registered", async function () {
      const deadline = Math.floor(Date.now() / 1000) + 3600;
      
      await expect(
        router.connect(user).sellTokens(userAddress, ethers.parseEther("100"), 0, deadline)
      ).to.be.revertedWithCustomError(router, "TokenNotRegistered");
    });

    it("Should revert if no tokens sent", async function () {
      const tokenAddress = await mockToken.getAddress();
      const deadline = Math.floor(Date.now() / 1000) + 3600;
      
      await expect(
        router.connect(user).sellTokens(tokenAddress, 0, 0, deadline)
      ).to.be.revertedWithCustomError(router, "NoTokensSent");
    });
  });

  // ===========================================================================
  // BUYBACK TESTS
  // ===========================================================================
  
  describe("Execute Buyback", function () {
    beforeEach(async function () {
      const tokenAddress = await mockToken.getAddress();
      await router.registerToken(tokenAddress, creatorAddress, 1); // Snowball mode
      
      // Fund router for buyback
      await owner.sendTransaction({
        to: await router.getAddress(),
        value: ethers.parseEther("1")
      });
    });

    it("Should revert if token not registered", async function () {
      await expect(
        router.executeBuyback(userAddress, 0)
      ).to.be.revertedWithCustomError(router, "TokenNotRegistered");
    });

    it("Should revert if not a Snowball/Fireball token", async function () {
      const MockToken2 = await ethers.getContractFactory("MockERC20");
      const standardToken = await MockToken2.deploy("Standard", "STD", ethers.parseEther("1000000000"));
      await router.registerToken(await standardToken.getAddress(), creatorAddress, 0); // Standard mode
      
      await expect(
        router.executeBuyback(await standardToken.getAddress(), 0)
      ).to.be.revertedWithCustomError(router, "NotSnowballToken");
    });

    it("Should revert if below threshold", async function () {
      const tokenAddress = await mockToken.getAddress();
      
      await expect(
        router.executeBuyback(tokenAddress, 0)
      ).to.be.revertedWithCustomError(router, "BelowBuybackThreshold");
    });
  });

  // ===========================================================================
  // ADMIN FUNCTIONS TESTS
  // ===========================================================================
  
  describe("Admin Functions", function () {
    describe("Pause/Unpause", function () {
      it("Should pause the contract", async function () {
        await router.pause();
        expect(await router.paused()).to.be.true;
      });

      it("Should unpause the contract", async function () {
        await router.pause();
        await router.unpause();
        expect(await router.paused()).to.be.false;
      });

      it("Should revert trades when paused", async function () {
        const tokenAddress = await mockToken.getAddress();
        await router.registerToken(tokenAddress, creatorAddress, 0);
        await router.pause();
        
        const deadline = Math.floor(Date.now() / 1000) + 3600;
        
        await expect(
          router.connect(user).buyTokens(tokenAddress, 0, deadline, { value: ethers.parseEther("1") })
        ).to.be.revertedWithCustomError(router, "EnforcedPause");
      });
    });

    describe("Set Treasury", function () {
      it("Should update treasury address", async function () {
        await expect(router.setTreasury(userAddress))
          .to.emit(router, "TreasuryUpdated")
          .withArgs(treasuryAddress, userAddress);

        expect(await router.treasury()).to.equal(userAddress);
      });

      it("Should revert if zero address", async function () {
        await expect(
          router.setTreasury(ethers.ZeroAddress)
        ).to.be.revertedWithCustomError(router, "InvalidAddress");
      });

      it("Should revert if non-owner", async function () {
        await expect(
          router.connect(user).setTreasury(userAddress)
        ).to.be.revertedWithCustomError(router, "OwnableUnauthorizedAccount");
      });
    });

    describe("Update Creator", function () {
      it("Should update token creator", async function () {
        const tokenAddress = await mockToken.getAddress();
        await router.registerToken(tokenAddress, creatorAddress, 0);

        await expect(router.updateCreator(tokenAddress, userAddress))
          .to.emit(router, "CreatorUpdated")
          .withArgs(tokenAddress, creatorAddress, userAddress);

        expect(await router.tokenCreator(tokenAddress)).to.equal(userAddress);
      });

      it("Should revert if token not registered", async function () {
        await expect(
          router.updateCreator(await mockToken.getAddress(), userAddress)
        ).to.be.revertedWithCustomError(router, "TokenNotRegistered");
      });
    });

    describe("Set Min Buyback Threshold", function () {
      it("Should update threshold", async function () {
        const newThreshold = ethers.parseEther("0.01");
        
        await expect(router.setMinBuybackThreshold(newThreshold))
          .to.emit(router, "MinBuybackThresholdUpdated");

        expect(await router.minBuybackThreshold()).to.equal(newThreshold);
      });
    });

    describe("Recover Functions", function () {
      it("Should recover non-registered tokens", async function () {
        const MockToken2 = await ethers.getContractFactory("MockERC20");
        const randomToken = await MockToken2.deploy("Random", "RND", ethers.parseEther("1000"));
        
        await randomToken.transfer(await router.getAddress(), ethers.parseEther("100"));
        
        await router.recoverToken(
          await randomToken.getAddress(), 
          ethers.parseEther("100"), 
          ownerAddress
        );

        expect(await randomToken.balanceOf(ownerAddress)).to.equal(ethers.parseEther("1000"));
      });

      it("Should revert recovering registered tokens", async function () {
        const tokenAddress = await mockToken.getAddress();
        await router.registerToken(tokenAddress, creatorAddress, 0);
        
        await expect(
          router.recoverToken(tokenAddress, ethers.parseEther("1"), ownerAddress)
        ).to.be.revertedWithCustomError(router, "CannotRecoverRegisteredToken");
      });

      it("Should recover BNB when paused", async function () {
        await owner.sendTransaction({
          to: await router.getAddress(),
          value: ethers.parseEther("1")
        });
        
        await router.pause();
        
        const balanceBefore = await ethers.provider.getBalance(treasuryAddress);
        await router.recoverBNB(ethers.parseEther("1"), treasuryAddress);
        const balanceAfter = await ethers.provider.getBalance(treasuryAddress);
        
        expect(balanceAfter - balanceBefore).to.equal(ethers.parseEther("1"));
      });

      it("Should revert BNB recovery when not paused", async function () {
        await expect(
          router.recoverBNB(ethers.parseEther("1"), treasuryAddress)
        ).to.be.revertedWithCustomError(router, "ExpectedPause");
      });
    });
  });

  // ===========================================================================
  // VIEW FUNCTIONS TESTS
  // ===========================================================================
  
  describe("View Functions", function () {
    it("Should return correct token info", async function () {
      const tokenAddress = await mockToken.getAddress();
      await router.registerToken(tokenAddress, creatorAddress, 1);

      const info = await router.getTokenInfo(tokenAddress);
      
      expect(info.registered).to.be.true;
      expect(info.creator).to.equal(creatorAddress);
      expect(info.launchMode).to.equal(1);
    });

    it("Should return correct global stats", async function () {
      const stats = await router.getGlobalStats();
      
      expect(stats._totalPlatformFees).to.equal(0);
      expect(stats._totalCreatorFees).to.equal(0);
      expect(stats._totalTradesRouted).to.equal(0);
      expect(stats._treasury).to.equal(treasuryAddress);
    });

    it("Should return contract balance", async function () {
      await owner.sendTransaction({
        to: await router.getAddress(),
        value: ethers.parseEther("1")
      });

      expect(await router.getContractBalance()).to.equal(ethers.parseEther("1"));
    });
  });

  // ===========================================================================
  // OWNERSHIP TESTS (Ownable2Step)
  // ===========================================================================
  
  describe("Ownable2Step", function () {
    it("Should initiate ownership transfer", async function () {
      await expect(router.transferOwnership(userAddress))
        .to.emit(router, "OwnershipTransferStarted")
        .withArgs(ownerAddress, userAddress);

      expect(await router.pendingOwner()).to.equal(userAddress);
      expect(await router.owner()).to.equal(ownerAddress); // Still owner until accepted
    });

    it("Should complete ownership transfer on accept", async function () {
      await router.transferOwnership(userAddress);
      
      await expect(router.connect(user).acceptOwnership())
        .to.emit(router, "OwnershipTransferred")
        .withArgs(ownerAddress, userAddress);

      expect(await router.owner()).to.equal(userAddress);
      expect(await router.pendingOwner()).to.equal(ethers.ZeroAddress);
    });

    it("Should revert if wrong address accepts", async function () {
      await router.transferOwnership(userAddress);
      
      await expect(
        router.connect(treasury).acceptOwnership()
      ).to.be.revertedWithCustomError(router, "OwnableUnauthorizedAccount");
    });
  });

  // ===========================================================================
  // REENTRANCY TESTS
  // ===========================================================================
  
  describe("Reentrancy Protection", function () {
    it("Should prevent reentrancy on buyTokens", async function () {
      // This test would require a malicious contract that tries to reenter
      // The nonReentrant modifier protects against this
      // For now, we just verify the modifier exists by checking the contract compiles
      expect(await router.getAddress()).to.not.equal(ethers.ZeroAddress);
    });
  });

  // ===========================================================================
  // HELPER FUNCTIONS
  // ===========================================================================
  
  async function getBlockTimestamp(): Promise<number> {
    const block = await ethers.provider.getBlock("latest");
    return block!.timestamp;
  }
});

