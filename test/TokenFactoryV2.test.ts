/**
 * TokenFactoryV2 Unit Tests
 * 
 * Tests for the UUPS Upgradeable contract on BSC Mainnet:
 * Proxy: 0xd2889580D9C8508696c9Ce82149E8867632E6C76
 * Implementation: 0x07C6a591C4bDF892a9d7F1d03A418a9c321B0482
 * 
 * Run with: npx hardhat test test/TokenFactoryV2.test.ts
 * 
 * V2 Features:
 * - UUPS Proxy pattern (upgradeable)
 * - Creator auto-exempt in AsterTokenV2 (fixes Snowball buyback bug)
 * - Optimized contract size (< 24KB)
 */

import { expect } from "chai";
import { ethers, upgrades } from "hardhat";
import { SignerWithAddress } from "@nomicfoundation/hardhat-ethers/signers";

describe("TokenFactoryV2", function () {
  this.timeout(120000);

  let tokenFactory: any;
  let owner: SignerWithAddress;
  let feeRecipient: SignerWithAddress;
  let creator: SignerWithAddress;
  let buyer: SignerWithAddress;
  let user: SignerWithAddress;

  const CREATION_FEE = ethers.parseEther("0.01");
  const TOTAL_SUPPLY = ethers.parseEther("1000000000"); // 1 billion

  beforeEach(async function () {
    [owner, feeRecipient, creator, buyer, user] = await ethers.getSigners();

    const TokenFactoryV2 = await ethers.getContractFactory("contracts/TokenFactoryV2Optimized.sol:TokenFactoryV2");
    // initialize(feeRecipient_, owner_) - note the parameter order!
    tokenFactory = await upgrades.deployProxy(
      TokenFactoryV2,
      [feeRecipient.address, owner.address],
      { 
        kind: 'uups',
        unsafeAllow: ['constructor', 'state-variable-immutable']
      }
    );
    await tokenFactory.waitForDeployment();
  });

  describe("Deployment & Initialization", function () {
    it("should set the correct owner", async function () {
      expect(await tokenFactory.owner()).to.equal(owner.address);
    });

    it("should set the correct fee recipient", async function () {
      expect(await tokenFactory.feeRecipient()).to.equal(feeRecipient.address);
    });

    it("should set default creation fee (0.01 BNB)", async function () {
      expect(await tokenFactory.creationFee()).to.equal(CREATION_FEE);
    });

    it("should not be paused initially", async function () {
      expect(await tokenFactory.paused()).to.equal(false);
    });

    it("should have zero tokens created initially", async function () {
      expect(await tokenFactory.getTokenCount()).to.equal(0);
    });

    it("should return correct version", async function () {
      expect(await tokenFactory.version()).to.equal("2.0.0");
    });
  });

  describe("createToken", function () {
    it("should create a token successfully", async function () {
      const tx = await tokenFactory.connect(creator).createToken(
        "Test Token",
        "TEST",
        "https://example.com/logo.png",
        "A test token",
        "Meme",
        { value: CREATION_FEE }
      );

      const receipt = await tx.wait();
      expect(receipt).to.emit(tokenFactory, "TokenCreated");
      expect(await tokenFactory.getTokenCount()).to.equal(1);
    });

    it("should set creator as exempt in token (V2 FIX)", async function () {
      const tx = await tokenFactory.connect(creator).createToken(
        "Test Token",
        "TEST",
        "https://example.com/logo.png",
        "A test token",
        "Meme",
        { value: CREATION_FEE }
      );

      const receipt = await tx.wait();
      
      const event = receipt.logs.find((log: any) => {
        try {
          const parsed = tokenFactory.interface.parseLog({
            topics: log.topics,
            data: log.data
          });
          return parsed?.name === "TokenCreated";
        } catch {
          return false;
        }
      });

      expect(event).to.not.be.undefined;
      
      const parsed = tokenFactory.interface.parseLog({
        topics: event.topics,
        data: event.data
      });
      
      const tokenAddress = parsed.args.token;

      const token = await ethers.getContractAt(
        "contracts/TokenFactoryV2Optimized.sol:AsterTokenV2",
        tokenAddress
      );

      // V2 FIX: Creator should be auto-exempt
      expect(await token.isExempt(creator.address)).to.equal(true);
    });

    it("should store logoURI and description", async function () {
      const logoURI = "https://example.com/logo.png";
      const description = "A test token with metadata";

      const tx = await tokenFactory.connect(creator).createToken(
        "Test Token",
        "TEST",
        logoURI,
        description,
        "Meme",
        { value: CREATION_FEE }
      );

      const receipt = await tx.wait();
      
      const event = receipt.logs.find((log: any) => {
        try {
          const parsed = tokenFactory.interface.parseLog({
            topics: log.topics,
            data: log.data
          });
          return parsed?.name === "TokenCreated";
        } catch {
          return false;
        }
      });

      const parsed = tokenFactory.interface.parseLog({
        topics: event.topics,
        data: event.data
      });
      
      const tokenAddress = parsed.args.token;

      const token = await ethers.getContractAt(
        "contracts/TokenFactoryV2Optimized.sol:AsterTokenV2",
        tokenAddress
      );

      expect(await token.logoURI()).to.equal(logoURI);
      expect(await token.description()).to.equal(description);
    });

    it("should revert when paused", async function () {
      await tokenFactory.connect(owner).pause();
      
      await expect(
        tokenFactory.connect(creator).createToken(
          "Test Token",
          "TEST",
          "",
          "",
          "Meme",
          { value: CREATION_FEE }
        )
      ).to.be.revertedWith("Paused");
    });

    it("should revert with insufficient fee", async function () {
      await expect(
        tokenFactory.connect(creator).createToken(
          "Test Token",
          "TEST",
          "",
          "",
          "Meme",
          { value: ethers.parseEther("0.001") }
        )
      ).to.be.revertedWith("Fee");
    });
  });

  describe("Token Properties", function () {
    let tokenAddress: string;
    let poolAddress: string;
    let token: any;

    beforeEach(async function () {
      const tx = await tokenFactory.connect(creator).createToken(
        "Test Token",
        "TEST",
        "https://example.com/logo.png",
        "Test description",
        "Meme",
        { value: CREATION_FEE }
      );

      const receipt = await tx.wait();
      
      const event = receipt.logs.find((log: any) => {
        try {
          const parsed = tokenFactory.interface.parseLog({
            topics: log.topics,
            data: log.data
          });
          return parsed?.name === "TokenCreated";
        } catch {
          return false;
        }
      });

      const parsed = tokenFactory.interface.parseLog({
        topics: event.topics,
        data: event.data
      });
      
      tokenAddress = parsed.args.token;
      poolAddress = parsed.args.pool;

      token = await ethers.getContractAt(
        "contracts/TokenFactoryV2Optimized.sol:AsterTokenV2",
        tokenAddress
      );
    });

    it("should have correct total supply (1 billion)", async function () {
      expect(await token.totalSupply()).to.equal(TOTAL_SUPPLY);
    });

    it("should have correct name", async function () {
      expect(await token.name()).to.equal("Test Token");
    });

    it("should have correct symbol", async function () {
      expect(await token.symbol()).to.equal("TEST");
    });

    it("should have 18 decimals", async function () {
      expect(await token.decimals()).to.equal(18);
    });

    it("should set creator correctly", async function () {
      expect(await token.creator()).to.equal(creator.address);
    });

    it("should set pool correctly", async function () {
      expect(await token.pool()).to.equal(poolAddress);
    });

    it("should mint all tokens to pool", async function () {
      expect(await token.balanceOf(poolAddress)).to.equal(TOTAL_SUPPLY);
    });

    it("should not have trading enabled initially", async function () {
      expect(await token.tradingEnabled()).to.equal(false);
    });

    it("should have creator as exempt (V2 FIX)", async function () {
      expect(await token.isExempt(creator.address)).to.equal(true);
    });
  });

  describe("Pool Mapping", function () {
    it("should map token to pool", async function () {
      const tx = await tokenFactory.connect(creator).createToken(
        "Test Token",
        "TEST",
        "",
        "",
        "Meme",
        { value: CREATION_FEE }
      );

      const receipt = await tx.wait();
      
      const event = receipt.logs.find((log: any) => {
        try {
          const parsed = tokenFactory.interface.parseLog({
            topics: log.topics,
            data: log.data
          });
          return parsed?.name === "TokenCreated";
        } catch {
          return false;
        }
      });

      const parsed = tokenFactory.interface.parseLog({
        topics: event.topics,
        data: event.data
      });
      
      const tokenAddress = parsed.args.token;
      const poolAddress = parsed.args.pool;

      expect(await tokenFactory.tokenToPool(tokenAddress)).to.equal(poolAddress);
    });

    it("should mark pool as AsterPool", async function () {
      const tx = await tokenFactory.connect(creator).createToken(
        "Test Token",
        "TEST",
        "",
        "",
        "Meme",
        { value: CREATION_FEE }
      );

      const receipt = await tx.wait();
      
      const event = receipt.logs.find((log: any) => {
        try {
          const parsed = tokenFactory.interface.parseLog({
            topics: log.topics,
            data: log.data
          });
          return parsed?.name === "TokenCreated";
        } catch {
          return false;
        }
      });

      const parsed = tokenFactory.interface.parseLog({
        topics: event.topics,
        data: event.data
      });
      
      const poolAddress = parsed.args.pool;

      expect(await tokenFactory.isAsterPool(poolAddress)).to.equal(true);
    });
  });

  describe("Admin Functions", function () {
    it("should allow owner to set creation fee", async function () {
      const newFee = ethers.parseEther("0.02");
      await tokenFactory.connect(owner).setCreationFee(newFee);
      expect(await tokenFactory.creationFee()).to.equal(newFee);
    });

    it("should allow owner to set fee recipient", async function () {
      await tokenFactory.connect(owner).setFeeRecipient(user.address);
      expect(await tokenFactory.feeRecipient()).to.equal(user.address);
    });

    it("should allow owner to pause", async function () {
      await tokenFactory.connect(owner).pause();
      expect(await tokenFactory.paused()).to.equal(true);
    });

    it("should allow owner to unpause", async function () {
      await tokenFactory.connect(owner).pause();
      await tokenFactory.connect(owner).unpause();
      expect(await tokenFactory.paused()).to.equal(false);
    });

    it("should revert if non-owner tries admin functions", async function () {
      await expect(
        tokenFactory.connect(user).setCreationFee(ethers.parseEther("0.1"))
      ).to.be.revertedWith("Not owner");

      await expect(
        tokenFactory.connect(user).setFeeRecipient(user.address)
      ).to.be.revertedWith("Not owner");

      await expect(
        tokenFactory.connect(user).pause()
      ).to.be.revertedWith("Not owner");
    });

    it("should allow owner to transfer ownership", async function () {
      await tokenFactory.connect(owner).transferOwnership(user.address);
      expect(await tokenFactory.owner()).to.equal(user.address);
    });
  });

  describe("View Functions", function () {
    it("should return all tokens", async function () {
      for (let i = 0; i < 3; i++) {
        await tokenFactory.connect(creator).createToken(
          `Token ${i}`,
          `TK${i}`,
          "",
          "",
          "Meme",
          { value: CREATION_FEE }
        );
      }

      const tokens = await tokenFactory.getAllTokens();
      expect(tokens.length).to.equal(3);
    });

    it("should return correct token count", async function () {
      await tokenFactory.connect(creator).createToken(
        "Token 1",
        "TK1",
        "",
        "",
        "Meme",
        { value: CREATION_FEE }
      );

      expect(await tokenFactory.getTokenCount()).to.equal(1);
    });
  });

  describe("Multiple Token Creation", function () {
    it("should handle multiple tokens from same creator", async function () {
      for (let i = 0; i < 5; i++) {
        await tokenFactory.connect(creator).createToken(
          `Token ${i}`,
          `TK${i}`,
          "",
          "",
          "Meme",
          { value: CREATION_FEE }
        );
      }

      expect(await tokenFactory.getTokenCount()).to.equal(5);
    });

    it("should handle tokens from different creators", async function () {
      await tokenFactory.connect(creator).createToken(
        "Creator Token",
        "CTK",
        "",
        "",
        "Meme",
        { value: CREATION_FEE }
      );

      await tokenFactory.connect(buyer).createToken(
        "Buyer Token",
        "BTK",
        "",
        "",
        "Meme",
        { value: CREATION_FEE }
      );

      await tokenFactory.connect(user).createToken(
        "User Token",
        "UTK",
        "",
        "",
        "Meme",
        { value: CREATION_FEE }
      );

      expect(await tokenFactory.getTokenCount()).to.equal(3);
    });
  });
});
