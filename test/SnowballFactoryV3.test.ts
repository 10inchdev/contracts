/**
 * SnowballFactoryV3 Unit Tests
 * 
 * Tests for the UUPS Upgradeable contract on BSC Mainnet:
 * Proxy: 0x06587986799224a88b8336f6ae0bb1d84ba6c026
 * Implementation: 0x60259109578d148210f155f6ca907435ee750115
 * 
 * Run with: npx hardhat test test/SnowballFactoryV3.test.ts
 * 
 * V3 Features:
 * - UUPS Proxy pattern (upgradeable)
 * - Configurable minBuybackThreshold (0.001 - 1 BNB)
 * - Per-pool fee tracking (fair distribution)
 * - Works with TokenFactoryV2 (creator auto-exempt)
 * - Supports both Snowball & Fireball launch modes
 */

import { expect } from "chai";
import { ethers, upgrades } from "hardhat";
import { SignerWithAddress } from "@nomicfoundation/hardhat-ethers/signers";

describe("SnowballFactoryV3", function () {
  // Increase timeout for deployment
  this.timeout(120000);

  let snowballFactory: any;
  let tokenFactory: any;
  let owner: SignerWithAddress;
  let feeRecipient: SignerWithAddress;
  let creator: SignerWithAddress;
  let buyer: SignerWithAddress;
  let user: SignerWithAddress;
  let pendingOwner: SignerWithAddress;

  const CREATION_FEE = ethers.parseEther("0.01");
  const DEAD_ADDRESS = "0x000000000000000000000000000000000000dEaD";
  const DEFAULT_THRESHOLD = ethers.parseEther("0.01"); // V3 default is 0.01 BNB

  beforeEach(async function () {
    [owner, feeRecipient, creator, buyer, user, pendingOwner] = await ethers.getSigners();

    // Deploy TokenFactoryV2 (the one that SnowballFactoryV3 uses)
    // Note: unsafeAllow needed because our flattened contract has UUPS-safe patterns
    // that the plugin incorrectly flags (constructor with _disableInitializers, __self immutable)
    const TokenFactoryV2 = await ethers.getContractFactory("contracts/TokenFactoryV2Optimized.sol:TokenFactoryV2");
    tokenFactory = await upgrades.deployProxy(
      TokenFactoryV2,
      [owner.address, feeRecipient.address],
      { 
        kind: 'uups',
        unsafeAllow: ['constructor', 'state-variable-immutable']
      }
    );
    await tokenFactory.waitForDeployment();

    // Deploy SnowballFactoryV3 as UUPS proxy
    const SnowballFactoryV3 = await ethers.getContractFactory("contracts/SnowballFactoryV3Flattened.sol:SnowballFactoryV3");
    snowballFactory = await upgrades.deployProxy(
      SnowballFactoryV3,
      [await tokenFactory.getAddress(), owner.address],
      { 
        kind: 'uups',
        unsafeAllow: ['constructor', 'state-variable-immutable']
      }
    );
    await snowballFactory.waitForDeployment();
  });

  describe("Deployment & Initialization", function () {
    it("should set the correct token factory address", async function () {
      expect(await snowballFactory.tokenFactory()).to.equal(await tokenFactory.getAddress());
    });

    it("should set the correct owner", async function () {
      expect(await snowballFactory.owner()).to.equal(owner.address);
    });

    it("should not be paused initially", async function () {
      expect(await snowballFactory.paused()).to.equal(false);
    });

    it("should have zero initial stats", async function () {
      expect(await snowballFactory.snowballPoolCount()).to.equal(0);
      expect(await snowballFactory.fireballPoolCount()).to.equal(0);
      expect(await snowballFactory.totalBuybacksBnb()).to.equal(0);
      expect(await snowballFactory.totalTokensBurnedGlobal()).to.equal(0);
    });

    it("should have V3 default minBuybackThreshold (0.01 BNB)", async function () {
      expect(await snowballFactory.minBuybackThreshold()).to.equal(DEFAULT_THRESHOLD);
    });

    it("should return correct version", async function () {
      expect(await snowballFactory.version()).to.equal("3.0.0");
    });

    it("should revert double initialization", async function () {
      await expect(
        snowballFactory.initialize(await tokenFactory.getAddress(), owner.address)
      ).to.be.revertedWith("Initializable: contract is already initialized");
    });
  });

  describe("createSnowballToken", function () {
    it("should create a Snowball token successfully", async function () {
      const tx = await snowballFactory.connect(creator).createSnowballToken(
        "Snowball Token",
        "SNOW",
        "https://example.com/logo.png",
        "A deflationary token with auto-buyback",
        "Meme",
        0, // SNOWBALL mode
        { value: CREATION_FEE }
      );

      const receipt = await tx.wait();
      
      // Check event was emitted
      expect(receipt).to.emit(snowballFactory, "SnowballTokenCreated");

      // Check counters
      expect(await snowballFactory.snowballPoolCount()).to.equal(1);
      expect(await snowballFactory.fireballPoolCount()).to.equal(0);
    });

    it("should create a Fireball token successfully", async function () {
      const tx = await snowballFactory.connect(creator).createSnowballToken(
        "Fireball Token",
        "FIRE",
        "https://example.com/fire-logo.png",
        "A hot deflationary token",
        "Meme",
        1, // FIREBALL mode
        { value: CREATION_FEE }
      );

      const receipt = await tx.wait();
      
      expect(receipt).to.emit(snowballFactory, "SnowballTokenCreated");
      expect(await snowballFactory.snowballPoolCount()).to.equal(0);
      expect(await snowballFactory.fireballPoolCount()).to.equal(1);
    });

    it("should track real creator correctly", async function () {
      const tx = await snowballFactory.connect(creator).createSnowballToken(
        "Test Token",
        "TEST",
        "https://example.com/logo.png",
        "Test description",
        "Meme",
        0,
        { value: CREATION_FEE }
      );

      const receipt = await tx.wait();
      const event = receipt.logs.find((log: any) => {
        try {
          const parsed = snowballFactory.interface.parseLog({
            topics: log.topics,
            data: log.data
          });
          return parsed?.name === "SnowballTokenCreated";
        } catch {
          return false;
        }
      });

      expect(event).to.not.be.undefined;
      
      const parsed = snowballFactory.interface.parseLog({
        topics: event.topics,
        data: event.data
      });
      
      const poolAddress = parsed.args.pool;
      
      // Real creator should be tracked
      expect(await snowballFactory.poolToRealCreator(poolAddress)).to.equal(creator.address);
      expect(await snowballFactory.isSnowballPool(poolAddress)).to.equal(true);
    });

    it("should revert when paused", async function () {
      await snowballFactory.connect(owner).pause();
      
      await expect(
        snowballFactory.connect(creator).createSnowballToken(
          "Test Token",
          "TEST",
          "https://example.com/logo.png",
          "Test description",
          "Meme",
          0,
          { value: CREATION_FEE }
        )
      ).to.be.revertedWith("Pausable: paused");
    });

    it("should revert with insufficient fee", async function () {
      await expect(
        snowballFactory.connect(creator).createSnowballToken(
          "Test Token",
          "TEST",
          "https://example.com/logo.png",
          "Test description",
          "Meme",
          0,
          { value: ethers.parseEther("0.001") } // Less than 0.01 BNB
        )
      ).to.be.revertedWith("Insufficient creation fee");
    });
  });

  describe("Configurable Buyback Threshold", function () {
    it("should allow owner to set minBuybackThreshold", async function () {
      const newThreshold = ethers.parseEther("0.05");
      
      await expect(snowballFactory.connect(owner).setMinBuybackThreshold(newThreshold))
        .to.emit(snowballFactory, "MinBuybackThresholdUpdated")
        .withArgs(DEFAULT_THRESHOLD, newThreshold);

      expect(await snowballFactory.minBuybackThreshold()).to.equal(newThreshold);
    });

    it("should revert if threshold too low", async function () {
      const tooLow = ethers.parseEther("0.0001"); // Below 0.001 BNB min
      
      await expect(
        snowballFactory.connect(owner).setMinBuybackThreshold(tooLow)
      ).to.be.revertedWith("Threshold too low (min 0.001 BNB)");
    });

    it("should revert if threshold too high", async function () {
      const tooHigh = ethers.parseEther("2"); // Above 1 BNB max
      
      await expect(
        snowballFactory.connect(owner).setMinBuybackThreshold(tooHigh)
      ).to.be.revertedWith("Threshold too high (max 1 BNB)");
    });

    it("should revert if non-owner tries to set threshold", async function () {
      await expect(
        snowballFactory.connect(user).setMinBuybackThreshold(ethers.parseEther("0.1"))
      ).to.be.revertedWith("Ownable: caller is not the owner");
    });
  });

  describe("Ownable2Step", function () {
    it("should support two-step ownership transfer", async function () {
      // Start transfer
      await snowballFactory.connect(owner).transferOwnership(pendingOwner.address);
      expect(await snowballFactory.pendingOwner()).to.equal(pendingOwner.address);
      expect(await snowballFactory.owner()).to.equal(owner.address); // Still owner

      // Accept transfer
      await snowballFactory.connect(pendingOwner).acceptOwnership();
      expect(await snowballFactory.owner()).to.equal(pendingOwner.address);
      expect(await snowballFactory.pendingOwner()).to.equal(ethers.ZeroAddress);
    });

    it("should revert if non-pending owner tries to accept", async function () {
      await snowballFactory.connect(owner).transferOwnership(pendingOwner.address);
      
      await expect(
        snowballFactory.connect(user).acceptOwnership()
      ).to.be.revertedWith("Ownable2Step: caller is not the new owner");
    });
  });

  describe("Pausable", function () {
    it("should allow owner to pause", async function () {
      await snowballFactory.connect(owner).pause();
      expect(await snowballFactory.paused()).to.equal(true);
    });

    it("should allow owner to unpause", async function () {
      await snowballFactory.connect(owner).pause();
      await snowballFactory.connect(owner).unpause();
      expect(await snowballFactory.paused()).to.equal(false);
    });

    it("should revert if non-owner tries to pause", async function () {
      await expect(
        snowballFactory.connect(user).pause()
      ).to.be.revertedWith("Ownable: caller is not the owner");
    });
  });

  describe("Admin Functions", function () {
    it("should allow owner to update tokenFactory", async function () {
      const newFactory = user.address; // Just for testing
      
      await expect(snowballFactory.connect(owner).setTokenFactory(newFactory))
        .to.emit(snowballFactory, "TokenFactoryUpdated");

      expect(await snowballFactory.tokenFactory()).to.equal(newFactory);
    });

    it("should revert if setting zero address as factory", async function () {
      await expect(
        snowballFactory.connect(owner).setTokenFactory(ethers.ZeroAddress)
      ).to.be.revertedWith("Invalid factory");
    });

    it("should allow emergency withdraw when paused", async function () {
      // Send some BNB to the contract
      await owner.sendTransaction({
        to: await snowballFactory.getAddress(),
        value: ethers.parseEther("1")
      });

      // Must pause first
      await snowballFactory.connect(owner).pause();

      const balanceBefore = await ethers.provider.getBalance(user.address);
      await snowballFactory.connect(owner).emergencyWithdraw(user.address);
      const balanceAfter = await ethers.provider.getBalance(user.address);

      expect(balanceAfter - balanceBefore).to.equal(ethers.parseEther("1"));
    });

    it("should revert emergency withdraw when not paused", async function () {
      await expect(
        snowballFactory.connect(owner).emergencyWithdraw(user.address)
      ).to.be.revertedWith("Pausable: not paused");
    });
  });

  describe("View Functions", function () {
    it("should return all snowball tokens", async function () {
      // Create 2 tokens
      await snowballFactory.connect(creator).createSnowballToken(
        "Token 1", "TK1", "", "", "Meme", 0, { value: CREATION_FEE }
      );
      await snowballFactory.connect(creator).createSnowballToken(
        "Token 2", "TK2", "", "", "Meme", 1, { value: CREATION_FEE }
      );

      const tokens = await snowballFactory.getAllSnowballTokens();
      expect(tokens.length).to.equal(2);
    });

    it("should return correct token count", async function () {
      await snowballFactory.connect(creator).createSnowballToken(
        "Token 1", "TK1", "", "", "Meme", 0, { value: CREATION_FEE }
      );

      expect(await snowballFactory.getSnowballTokenCount()).to.equal(1);
    });

    it("should return correct pool info", async function () {
      const tx = await snowballFactory.connect(creator).createSnowballToken(
        "Test Token", "TEST", "", "", "Meme", 0, { value: CREATION_FEE }
      );

      const receipt = await tx.wait();
      const event = receipt.logs.find((log: any) => {
        try {
          const parsed = snowballFactory.interface.parseLog({
            topics: log.topics,
            data: log.data
          });
          return parsed?.name === "SnowballTokenCreated";
        } catch {
          return false;
        }
      });

      const parsed = snowballFactory.interface.parseLog({
        topics: event.topics,
        data: event.data
      });
      
      const poolAddress = parsed.args.pool;

      const [realCreator, mode, buybackBnb, tokensBurned, pendingBnb, isRegistered] = 
        await snowballFactory.getPoolInfo(poolAddress);

      expect(realCreator).to.equal(creator.address);
      expect(mode).to.equal(0); // SNOWBALL
      expect(buybackBnb).to.equal(0);
      expect(tokensBurned).to.equal(0);
      expect(pendingBnb).to.equal(0);
      expect(isRegistered).to.equal(true);
    });

    it("should return global stats", async function () {
      await snowballFactory.connect(creator).createSnowballToken(
        "Token 1", "TK1", "", "", "Meme", 0, { value: CREATION_FEE }
      );
      await snowballFactory.connect(creator).createSnowballToken(
        "Token 2", "TK2", "", "", "Meme", 1, { value: CREATION_FEE }
      );

      const [snowballPools, fireballPools, totalBnb, totalBurned, balance] = 
        await snowballFactory.getGlobalStats();

      expect(snowballPools).to.equal(1);
      expect(fireballPools).to.equal(1);
      expect(totalBnb).to.equal(0);
      expect(totalBurned).to.equal(0);
    });
  });

  describe("Fee Reception", function () {
    it("should track BNB received from pools", async function () {
      // Create a token first
      const tx = await snowballFactory.connect(creator).createSnowballToken(
        "Test Token", "TEST", "", "", "Meme", 0, { value: CREATION_FEE }
      );

      const receipt = await tx.wait();
      const event = receipt.logs.find((log: any) => {
        try {
          const parsed = snowballFactory.interface.parseLog({
            topics: log.topics,
            data: log.data
          });
          return parsed?.name === "SnowballTokenCreated";
        } catch {
          return false;
        }
      });

      const parsed = snowballFactory.interface.parseLog({
        topics: event.topics,
        data: event.data
      });
      
      const poolAddress = parsed.args.pool;

      // Simulate pool sending fee (impersonate pool)
      // In real scenario, this happens when trades occur
      const feeAmount = ethers.parseEther("0.005");
      
      // For testing, we need to impersonate the pool
      await ethers.provider.send("hardhat_impersonateAccount", [poolAddress]);
      await owner.sendTransaction({ to: poolAddress, value: ethers.parseEther("1") });
      
      const poolSigner = await ethers.getSigner(poolAddress);
      await poolSigner.sendTransaction({
        to: await snowballFactory.getAddress(),
        value: feeAmount
      });

      await ethers.provider.send("hardhat_stopImpersonatingAccount", [poolAddress]);

      // Check pending buyback
      expect(await snowballFactory.pendingBuyback(poolAddress)).to.equal(feeAmount);
    });

    it("should emit UnknownBNBReceived for non-pool senders", async function () {
      const amount = ethers.parseEther("0.1");
      
      await expect(
        user.sendTransaction({
          to: await snowballFactory.getAddress(),
          value: amount
        })
      ).to.emit(snowballFactory, "UnknownBNBReceived")
        .withArgs(user.address, amount);
    });
  });

  describe("Multiple Token Creation", function () {
    it("should handle multiple tokens correctly", async function () {
      // Create 3 Snowball tokens
      for (let i = 0; i < 3; i++) {
        await snowballFactory.connect(creator).createSnowballToken(
          `Snowball ${i}`, `SNOW${i}`, "", "", "Meme", 0, { value: CREATION_FEE }
        );
      }

      // Create 2 Fireball tokens
      for (let i = 0; i < 2; i++) {
        await snowballFactory.connect(creator).createSnowballToken(
          `Fireball ${i}`, `FIRE${i}`, "", "", "Meme", 1, { value: CREATION_FEE }
        );
      }

      expect(await snowballFactory.snowballPoolCount()).to.equal(3);
      expect(await snowballFactory.fireballPoolCount()).to.equal(2);
      expect(await snowballFactory.getSnowballTokenCount()).to.equal(5);
    });
  });
});
