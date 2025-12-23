/**
 * SnowballFactoryV2 Unit Tests
 * 
 * Tests for the deployed contract on BSC Mainnet:
 * https://repo.sourcify.dev/56/0x9DF2285dB7c3dd16DC54e97607342B24f3037Cc5
 * 
 * Run with: npx hardhat test test/SnowballFactoryV2.test.ts
 * 
 * V2 Features:
 * - Per-pool fee tracking (fair distribution)
 * - pendingBuyback mapping for each pool
 * - batchAutoBuyback for efficient cron processing
 * - getPoolsWithPendingBuybacks view function
 */

import { expect } from "chai";
import { ethers } from "hardhat";
import { SignerWithAddress } from "@nomicfoundation/hardhat-ethers/signers";

describe("SnowballFactoryV2", function () {
  // Increase timeout for deployment
  this.timeout(120000);

  let snowballFactory: any;
  let tokenFactory: any;
  let owner: SignerWithAddress;
  let feeRecipient: SignerWithAddress;
  let creator: SignerWithAddress;
  let buyer: SignerWithAddress;
  let user: SignerWithAddress;

  const CREATION_FEE = ethers.parseEther("0.01");
  const DEAD_ADDRESS = "0x000000000000000000000000000000000000dEaD";

  beforeEach(async function () {
    [owner, feeRecipient, creator, buyer, user] = await ethers.getSigners();

    // Deploy the real TokenFactory first (use fully qualified name to avoid ambiguity)
    const TokenFactoryFactory = await ethers.getContractFactory("contracts/TokenFactory.sol:TokenFactory");
    tokenFactory = await TokenFactoryFactory.deploy();
    await tokenFactory.waitForDeployment();

    // Deploy SnowballFactoryV2 with TokenFactory address
    const SnowballFactoryFactory = await ethers.getContractFactory("contracts/SnowballFactoryV2Flattened.sol:SnowballFactoryV2");
    snowballFactory = await SnowballFactoryFactory.deploy(await tokenFactory.getAddress());
    await snowballFactory.waitForDeployment();
  });

  describe("Deployment", function () {
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

    it("should have default minBuybackThreshold", async function () {
      // Default is 0.001 BNB (1e15 wei)
      expect(await snowballFactory.minBuybackThreshold()).to.equal(ethers.parseEther("0.001"));
    });

    it("should revert if token factory is zero address", async function () {
      const SnowballFactoryFactory = await ethers.getContractFactory("contracts/SnowballFactoryV2Flattened.sol:SnowballFactoryV2");
      await expect(
        SnowballFactoryFactory.deploy(ethers.ZeroAddress)
      ).to.be.revertedWith("Invalid factory");
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
      await snowballFactory.connect(creator).createSnowballToken(
        "Fireball Token",
        "FIRE",
        "https://example.com/logo.png",
        "A hot deflationary token",
        "Meme",
        1, // FIREBALL mode
        { value: CREATION_FEE }
      );

      // Check launch mode is FIREBALL
      expect(await snowballFactory.fireballPoolCount()).to.equal(1);
      expect(await snowballFactory.snowballPoolCount()).to.equal(0);
    });

    it("should track the real creator correctly", async function () {
      const tx = await snowballFactory.connect(creator).createSnowballToken(
        "Test Token",
        "TEST",
        "",
        "",
        "Meme",
        0,
        { value: CREATION_FEE }
      );

      const receipt = await tx.wait();
      
      // Parse event to get pool address
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

      if (event) {
        const parsed = snowballFactory.interface.parseLog({
          topics: event.topics,
          data: event.data
        });
        const poolAddress = parsed?.args[1];
        
        // Check real creator is tracked
        expect(await snowballFactory.poolToRealCreator(poolAddress)).to.equal(creator.address);
        expect(await snowballFactory.isSnowballPool(poolAddress)).to.equal(true);
      }
    });

    it("should revert when paused", async function () {
      await snowballFactory.pause();

      await expect(
        snowballFactory.connect(creator).createSnowballToken(
          "Test Token",
          "TEST",
          "",
          "",
          "Meme",
          0,
          { value: CREATION_FEE }
        )
      ).to.be.reverted; // EnforcedPause error
    });

    it("should add token to allSnowballTokens array", async function () {
      await snowballFactory.connect(creator).createSnowballToken(
        "Test Token",
        "TEST",
        "",
        "",
        "Meme",
        0,
        { value: CREATION_FEE }
      );

      // Get the token from the array
      const tokenAddress = await snowballFactory.allSnowballTokens(0);
      expect(tokenAddress).to.not.equal(ethers.ZeroAddress);
    });
  });

  describe("V2 Features - Per-Pool Tracking", function () {
    let poolAddress: string;
    let tokenAddress: string;

    beforeEach(async function () {
      const tx = await snowballFactory.connect(creator).createSnowballToken(
        "Test Token",
        "TEST",
        "",
        "",
        "Meme",
        0, // SNOWBALL
        { value: CREATION_FEE }
      );

      const receipt = await tx.wait();
      
      // Parse event to get addresses
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

      if (event) {
        const parsed = snowballFactory.interface.parseLog({
          topics: event.topics,
          data: event.data
        });
        tokenAddress = parsed?.args[0];
        poolAddress = parsed?.args[1];
      }
    });

    it("should track pendingBuyback per pool", async function () {
      // Initially zero
      expect(await snowballFactory.pendingBuyback(poolAddress)).to.equal(0);
    });

    it("should return correct pool info with V2 fields", async function () {
      const info = await snowballFactory.getPoolInfo(poolAddress);

      expect(info.realCreator).to.equal(creator.address);
      expect(info.mode).to.equal(0); // SNOWBALL
      expect(info.buybackBnb).to.equal(0);
      expect(info.tokensBurned).to.equal(0);
      expect(info.pendingBnb).to.equal(0); // V2 field
      expect(info.isRegistered).to.equal(true);
    });

    it("should return isRegistered=false for non-snowball pools", async function () {
      const randomAddress = ethers.Wallet.createRandom().address;
      const info = await snowballFactory.getPoolInfo(randomAddress);

      expect(info.isRegistered).to.equal(false);
    });

    it("should track token to pool mapping", async function () {
      const mappedPool = await snowballFactory.tokenToPool(tokenAddress);
      expect(mappedPool).to.equal(poolAddress);
    });

    it("should return empty array when no pools have pending buybacks", async function () {
      const [pools, amounts] = await snowballFactory.getPoolsWithPendingBuybacks();
      expect(pools.length).to.equal(0);
      expect(amounts.length).to.equal(0);
    });
  });

  describe("Access Control", function () {
    it("should allow owner to pause", async function () {
      await snowballFactory.pause();
      expect(await snowballFactory.paused()).to.equal(true);
    });

    it("should allow owner to unpause", async function () {
      await snowballFactory.pause();
      await snowballFactory.unpause();
      expect(await snowballFactory.paused()).to.equal(false);
    });

    it("should not allow non-owner to pause", async function () {
      await expect(
        snowballFactory.connect(user).pause()
      ).to.be.reverted; // OwnableUnauthorizedAccount error
    });

    it("should not allow non-owner to unpause", async function () {
      await snowballFactory.pause();
      await expect(
        snowballFactory.connect(user).unpause()
      ).to.be.reverted;
    });

    it("should use two-step ownership transfer", async function () {
      // Start transfer
      await snowballFactory.transferOwnership(user.address);

      // Owner is still the original
      expect(await snowballFactory.owner()).to.equal(owner.address);

      // Pending owner is set
      expect(await snowballFactory.pendingOwner()).to.equal(user.address);

      // New owner accepts
      await snowballFactory.connect(user).acceptOwnership();

      // Now new owner is set
      expect(await snowballFactory.owner()).to.equal(user.address);
    });

    it("should not allow non-pending owner to accept ownership", async function () {
      await snowballFactory.transferOwnership(user.address);
      
      await expect(
        snowballFactory.connect(creator).acceptOwnership()
      ).to.be.reverted;
    });
  });

  describe("V2 Admin Functions", function () {
    it("should allow owner to set minBuybackThreshold", async function () {
      const newThreshold = ethers.parseEther("0.005");
      await snowballFactory.setMinBuybackThreshold(newThreshold);
      expect(await snowballFactory.minBuybackThreshold()).to.equal(newThreshold);
    });

    it("should not allow non-owner to set minBuybackThreshold", async function () {
      await expect(
        snowballFactory.connect(user).setMinBuybackThreshold(ethers.parseEther("0.01"))
      ).to.be.reverted;
    });

    it("should allow owner to set minBuybackTokens", async function () {
      const newMin = ethers.parseEther("100");
      await snowballFactory.setMinBuybackTokens(newMin);
      expect(await snowballFactory.minBuybackTokens()).to.equal(newMin);
    });

    it("should not allow non-owner to set minBuybackTokens", async function () {
      await expect(
        snowballFactory.connect(user).setMinBuybackTokens(ethers.parseEther("100"))
      ).to.be.reverted;
    });
  });

  describe("BNB Recovery", function () {
    beforeEach(async function () {
      // Send BNB to factory
      await owner.sendTransaction({
        to: await snowballFactory.getAddress(),
        value: ethers.parseEther("1.0")
      });
    });

    it("should allow owner to recover BNB when paused", async function () {
      // Must pause first - recoverBNB has whenPaused modifier
      await snowballFactory.pause();

      const initialBalance = await ethers.provider.getBalance(user.address);

      // recoverBNB(address to, uint256 amount)
      await snowballFactory.recoverBNB(user.address, ethers.parseEther("1.0"));

      const finalBalance = await ethers.provider.getBalance(user.address);
      expect(finalBalance - initialBalance).to.equal(ethers.parseEther("1.0"));
    });

    it("should not allow non-owner to recover BNB", async function () {
      await snowballFactory.pause();
      await expect(
        snowballFactory.connect(user).recoverBNB(user.address, ethers.parseEther("1.0"))
      ).to.be.reverted;
    });

    it("should revert if amount exceeds balance", async function () {
      await snowballFactory.pause();
      await expect(
        snowballFactory.recoverBNB(user.address, ethers.parseEther("100"))
      ).to.be.revertedWith("Invalid amount");
    });

    it("should report correct contract balance", async function () {
      expect(await snowballFactory.getContractBalance()).to.equal(ethers.parseEther("1.0"));
    });
  });

  describe("Buyback Functions", function () {
    let poolAddress: string;

    beforeEach(async function () {
      const tx = await snowballFactory.connect(creator).createSnowballToken(
        "Test Token",
        "TEST",
        "",
        "",
        "Meme",
        0,
        { value: CREATION_FEE }
      );

      const receipt = await tx.wait();
      
      // Parse event to get pool address
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

      if (event) {
        const parsed = snowballFactory.interface.parseLog({
          topics: event.topics,
          data: event.data
        });
        poolAddress = parsed?.args[1];
      }
    });

    it("should revert autoBuyback for non-snowball pool", async function () {
      const randomAddress = ethers.Wallet.createRandom().address;

      await expect(
        snowballFactory.autoBuyback(randomAddress, 1)
      ).to.be.revertedWith("Not a valid snowball pool");
    });

    it("should validate pool is registered for buyback", async function () {
      expect(await snowballFactory.isSnowballPool(poolAddress)).to.equal(true);
    });

    it("should revert autoBuyback when minTokensOut is zero", async function () {
      await expect(
        snowballFactory.autoBuyback(poolAddress, 0)
      ).to.be.revertedWith("Min tokens too low");
    });

    it("should revert batchAutoBuyback when minTokensOut is zero", async function () {
      await expect(
        snowballFactory.batchAutoBuyback([], 0)
      ).to.be.revertedWith("Min tokens too low");
    });
  });

  describe("Multiple Token Creation", function () {
    it("should handle multiple Snowball tokens", async function () {
      // Create 3 Snowball tokens
      for (let i = 0; i < 3; i++) {
        await snowballFactory.connect(creator).createSnowballToken(
          `Snowball ${i}`,
          `SNOW${i}`,
          "",
          "",
          "Meme",
          0,
          { value: CREATION_FEE }
        );
      }

      expect(await snowballFactory.snowballPoolCount()).to.equal(3);
      expect(await snowballFactory.fireballPoolCount()).to.equal(0);
    });

    it("should handle multiple Fireball tokens", async function () {
      // Create 3 Fireball tokens
      for (let i = 0; i < 3; i++) {
        await snowballFactory.connect(creator).createSnowballToken(
          `Fireball ${i}`,
          `FIRE${i}`,
          "",
          "",
          "Meme",
          1,
          { value: CREATION_FEE }
        );
      }

      expect(await snowballFactory.snowballPoolCount()).to.equal(0);
      expect(await snowballFactory.fireballPoolCount()).to.equal(3);
    });

    it("should handle mixed Snowball and Fireball tokens", async function () {
      // Create 2 Snowball and 2 Fireball
      await snowballFactory.connect(creator).createSnowballToken(
        "Snowball 1", "SNOW1", "", "", "Meme", 0, { value: CREATION_FEE }
      );
      await snowballFactory.connect(creator).createSnowballToken(
        "Fireball 1", "FIRE1", "", "", "Meme", 1, { value: CREATION_FEE }
      );
      await snowballFactory.connect(creator).createSnowballToken(
        "Snowball 2", "SNOW2", "", "", "Meme", 0, { value: CREATION_FEE }
      );
      await snowballFactory.connect(creator).createSnowballToken(
        "Fireball 2", "FIRE2", "", "", "Meme", 1, { value: CREATION_FEE }
      );

      expect(await snowballFactory.snowballPoolCount()).to.equal(2);
      expect(await snowballFactory.fireballPoolCount()).to.equal(2);
    });
  });

  describe("Receive BNB", function () {
    it("should receive BNB directly", async function () {
      const amount = ethers.parseEther("0.5");

      await owner.sendTransaction({
        to: await snowballFactory.getAddress(),
        value: amount
      });

      expect(await snowballFactory.getContractBalance()).to.equal(amount);
    });
  });

  describe("Global Stats", function () {
    it("should return correct global stats initially", async function () {
      // Returns: (_totalBuybacksBnb, _totalTokensBurned, _snowballPools, _fireballPools, _totalPools, _contractBalance)
      const [totalBuybacksBnb, totalTokensBurned, snowballPools, fireballPools, totalPools, contractBalance] = 
        await snowballFactory.getGlobalStats();
      
      expect(totalPools).to.equal(0);
      expect(snowballPools).to.equal(0);
      expect(fireballPools).to.equal(0);
      expect(totalBuybacksBnb).to.equal(0);
      expect(totalTokensBurned).to.equal(0);
    });

    it("should update pool counts after token creation", async function () {
      await snowballFactory.connect(creator).createSnowballToken(
        "Test", "TEST", "", "", "Meme", 0, { value: CREATION_FEE }
      );

      const [, , snowballPools, , totalPools] = await snowballFactory.getGlobalStats();
      expect(totalPools).to.equal(1);
      expect(snowballPools).to.equal(1);
    });
  });
});

