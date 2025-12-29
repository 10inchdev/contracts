import { expect } from "chai";
import { ethers } from "hardhat";
import { time } from "@nomicfoundation/hardhat-network-helpers";
import { 
  PredictionMarketV1,
  ERC1967Proxy,
  MockTokenFactory,
  MockLaunchpadPool,
  MockChainlinkOracle,
  MockToken
} from "../typechain-types";
import { SignerWithAddress } from "@nomicfoundation/hardhat-ethers/signers";

describe("PredictionMarketV1", function () {
  let predictionMarket: PredictionMarketV1;
  let proxy: ERC1967Proxy;
  let tokenFactory: MockTokenFactory;
  let launchpadPool: MockLaunchpadPool;
  let oracle: MockChainlinkOracle;
  let mockToken: MockToken;
  
  let owner: SignerWithAddress;
  let tokenCreator: SignerWithAddress;
  let user1: SignerWithAddress;
  let user2: SignerWithAddress;
  let feeRecipient: SignerWithAddress;
  
  const BNB_PRICE = 700 * 10**8; // $700 in 8 decimals (Chainlink format)
  const MIN_BET = ethers.parseEther("0.01");
  const MAX_BET = ethers.parseEther("10");
  const CREATION_FEE = ethers.parseEther("0.05");
  const ONE_DAY = 24 * 60 * 60;
  const ONE_HOUR = 60 * 60;
  
  beforeEach(async function () {
    [owner, tokenCreator, user1, user2, feeRecipient] = await ethers.getSigners();
    
    // Deploy mock contracts
    const MockTokenFactory = await ethers.getContractFactory("MockTokenFactory");
    tokenFactory = await MockTokenFactory.deploy();
    
    const MockChainlinkOracle = await ethers.getContractFactory("MockChainlinkOracle");
    oracle = await MockChainlinkOracle.deploy(BNB_PRICE);
    
    const MockToken = await ethers.getContractFactory("MockToken");
    mockToken = await MockToken.deploy("Test Token", "TEST");
    
    const MockLaunchpadPool = await ethers.getContractFactory("MockLaunchpadPool");
    launchpadPool = await MockLaunchpadPool.deploy(
      await mockToken.getAddress(),
      "Test Token",
      "TEST",
      tokenCreator.address
    );
    
    // Register pool in factory
    await tokenFactory.setPool(await mockToken.getAddress(), await launchpadPool.getAddress());
    
    // Deploy implementation
    const PredictionMarketV1 = await ethers.getContractFactory("PredictionMarketV1");
    const implementation = await PredictionMarketV1.deploy();
    
    // Encode initialization data
    const initData = implementation.interface.encodeFunctionData("initialize", [
      await tokenFactory.getAddress(),
      await oracle.getAddress(),
      feeRecipient.address
    ]);
    
    // Deploy proxy
    const ERC1967Proxy = await ethers.getContractFactory("ERC1967Proxy");
    proxy = await ERC1967Proxy.deploy(await implementation.getAddress(), initData);
    
    // Get prediction market instance at proxy address
    predictionMarket = PredictionMarketV1.attach(await proxy.getAddress()) as PredictionMarketV1;
  });
  
  describe("Initialization", function () {
    it("Should initialize with correct owner", async function () {
      expect(await predictionMarket.owner()).to.equal(owner.address);
    });
    
    it("Should initialize with correct version", async function () {
      expect(await predictionMarket.version()).to.equal("1.0.0");
    });
    
    it("Should not be paused initially", async function () {
      expect(await predictionMarket.paused()).to.equal(false);
    });
    
    it("Should have correct fee recipient", async function () {
      expect(await predictionMarket.feeRecipient()).to.equal(feeRecipient.address);
    });
    
    it("Should have nextPredictionId = 1", async function () {
      expect(await predictionMarket.nextPredictionId()).to.equal(1);
    });
  });
  
  describe("Create Prediction", function () {
    it("Should allow token creator to create prediction for free", async function () {
      const deadline = (await time.latest()) + ONE_DAY * 7;
      const targetValue = ethers.parseEther("100000"); // $100K market cap
      
      await expect(
        predictionMarket.connect(tokenCreator).createPrediction(
          await mockToken.getAddress(),
          0, // MARKET_CAP
          targetValue,
          deadline
        )
      ).to.emit(predictionMarket, "PredictionCreated")
        .withArgs(1, await mockToken.getAddress(), 0, targetValue, deadline, tokenCreator.address, true);
      
      expect(await predictionMarket.nextPredictionId()).to.equal(2);
    });
    
    it("Should require fee from non-creators", async function () {
      const deadline = (await time.latest()) + ONE_DAY * 7;
      const targetValue = ethers.parseEther("100000");
      
      await expect(
        predictionMarket.connect(user1).createPrediction(
          await mockToken.getAddress(),
          0,
          targetValue,
          deadline
        )
      ).to.be.revertedWith("Insufficient fee");
      
      // With fee should work
      await expect(
        predictionMarket.connect(user1).createPrediction(
          await mockToken.getAddress(),
          0,
          targetValue,
          deadline,
          { value: CREATION_FEE }
        )
      ).to.emit(predictionMarket, "PredictionCreated");
    });
    
    it("Should reject deadline too soon", async function () {
      const deadline = (await time.latest()) + 30 * 60; // 30 minutes
      
      await expect(
        predictionMarket.connect(tokenCreator).createPrediction(
          await mockToken.getAddress(),
          0,
          ethers.parseEther("100000"),
          deadline
        )
      ).to.be.revertedWith("Deadline too soon");
    });
    
    it("Should reject deadline too far", async function () {
      const deadline = (await time.latest()) + ONE_DAY * 31; // 31 days
      
      await expect(
        predictionMarket.connect(tokenCreator).createPrediction(
          await mockToken.getAddress(),
          0,
          ethers.parseEther("100000"),
          deadline
        )
      ).to.be.revertedWith("Deadline too far");
    });
    
    it("Should reject unknown token", async function () {
      const deadline = (await time.latest()) + ONE_DAY * 7;
      
      await expect(
        predictionMarket.connect(user1).createPrediction(
          user2.address, // Not a registered token
          0,
          ethers.parseEther("100000"),
          deadline,
          { value: CREATION_FEE }
        )
      ).to.be.revertedWith("Token not found");
    });
  });
  
  describe("Betting", function () {
    let predictionId: bigint;
    let deadline: number;
    
    beforeEach(async function () {
      deadline = (await time.latest()) + ONE_DAY * 7;
      await predictionMarket.connect(tokenCreator).createPrediction(
        await mockToken.getAddress(),
        0,
        ethers.parseEther("100000"),
        deadline
      );
      predictionId = 1n;
    });
    
    it("Should allow betting YES", async function () {
      const betAmount = ethers.parseEther("0.5");
      
      await expect(
        predictionMarket.connect(user1).bet(predictionId, true, { value: betAmount })
      ).to.emit(predictionMarket, "BetPlaced")
        .withArgs(predictionId, user1.address, true, betAmount, betAmount, 0);
      
      const bet = await predictionMarket.getUserBet(predictionId, user1.address);
      expect(bet.amount).to.equal(betAmount);
      expect(bet.isYes).to.equal(true);
      expect(bet.claimed).to.equal(false);
    });
    
    it("Should allow betting NO", async function () {
      const betAmount = ethers.parseEther("0.5");
      
      await expect(
        predictionMarket.connect(user1).bet(predictionId, false, { value: betAmount })
      ).to.emit(predictionMarket, "BetPlaced");
      
      const bet = await predictionMarket.getUserBet(predictionId, user1.address);
      expect(bet.isYes).to.equal(false);
    });
    
    it("Should reject bet below minimum", async function () {
      await expect(
        predictionMarket.connect(user1).bet(predictionId, true, { value: ethers.parseEther("0.005") })
      ).to.be.revertedWith("Bet too small");
    });
    
    it("Should reject bet above maximum", async function () {
      await expect(
        predictionMarket.connect(user1).bet(predictionId, true, { value: ethers.parseEther("15") })
      ).to.be.revertedWith("Bet too large");
    });
    
    it("Should reject betting on opposite side", async function () {
      await predictionMarket.connect(user1).bet(predictionId, true, { value: MIN_BET });
      
      await expect(
        predictionMarket.connect(user1).bet(predictionId, false, { value: MIN_BET })
      ).to.be.revertedWith("Cannot bet both sides");
    });
    
    it("Should allow additional bet on same side", async function () {
      await predictionMarket.connect(user1).bet(predictionId, true, { value: MIN_BET });
      await predictionMarket.connect(user1).bet(predictionId, true, { value: MIN_BET });
      
      const bet = await predictionMarket.getUserBet(predictionId, user1.address);
      expect(bet.amount).to.equal(MIN_BET * 2n);
    });
    
    it("Should reject betting after freeze period", async function () {
      // Fast forward to 5 minutes before deadline (within 10 min freeze)
      await time.increaseTo(deadline - 5 * 60);
      
      await expect(
        predictionMarket.connect(user1).bet(predictionId, true, { value: MIN_BET })
      ).to.be.revertedWith("Betting closed");
    });
  });
  
  describe("Resolution", function () {
    let predictionId: bigint;
    let deadline: number;
    
    beforeEach(async function () {
      deadline = (await time.latest()) + ONE_DAY * 7;
      await predictionMarket.connect(tokenCreator).createPrediction(
        await mockToken.getAddress(),
        0, // MARKET_CAP
        ethers.parseEther("50000"), // $50K target
        deadline
      );
      predictionId = 1n;
      
      // Place bets
      await predictionMarket.connect(user1).bet(predictionId, true, { value: ethers.parseEther("1") });
      await predictionMarket.connect(user2).bet(predictionId, false, { value: ethers.parseEther("1") });
    });
    
    it("Should reject resolution before deadline", async function () {
      await expect(
        predictionMarket.resolve(predictionId)
      ).to.be.revertedWith("Not yet deadline");
    });
    
    it("Should resolve YES when target is met", async function () {
      // Set high price to exceed market cap target
      await launchpadPool.setVirtualBnb(ethers.parseEther("100")); // High BNB value
      
      await time.increaseTo(deadline);
      // Update oracle timestamp to current time
      await oracle.setPrice(BNB_PRICE);
      
      await expect(
        predictionMarket.resolve(predictionId)
      ).to.emit(predictionMarket, "PredictionResolved")
        .withArgs(predictionId, true, ethers.parseEther("1"), ethers.parseEther("1"), owner.address);
    });
    
    it("Should resolve NO when target is not met", async function () {
      // Keep low price
      await launchpadPool.setVirtualBnb(ethers.parseEther("0.1")); // Low BNB value
      
      await time.increaseTo(deadline);
      // Update oracle timestamp to current time
      await oracle.setPrice(BNB_PRICE);
      
      await expect(
        predictionMarket.resolve(predictionId)
      ).to.emit(predictionMarket, "PredictionResolved")
        .withArgs(predictionId, false, ethers.parseEther("1"), ethers.parseEther("1"), owner.address);
    });
    
    it("Should reject double resolution", async function () {
      await time.increaseTo(deadline);
      // Update oracle timestamp to current time
      await oracle.setPrice(BNB_PRICE);
      await predictionMarket.resolve(predictionId);
      
      await expect(
        predictionMarket.resolve(predictionId)
      ).to.be.revertedWith("Already resolved");
    });
  });
  
  describe("Claiming Winnings", function () {
    let predictionId: bigint;
    let deadline: number;
    
    beforeEach(async function () {
      deadline = (await time.latest()) + ONE_DAY * 7;
      await predictionMarket.connect(tokenCreator).createPrediction(
        await mockToken.getAddress(),
        0,
        ethers.parseEther("50000"),
        deadline
      );
      predictionId = 1n;
      
      // User1 bets YES, User2 bets NO
      await predictionMarket.connect(user1).bet(predictionId, true, { value: ethers.parseEther("1") });
      await predictionMarket.connect(user2).bet(predictionId, false, { value: ethers.parseEther("1") });
      
      // Set high price for YES to win
      await launchpadPool.setVirtualBnb(ethers.parseEther("100"));
      
      await time.increaseTo(deadline);
      // Update oracle timestamp to current time
      await oracle.setPrice(BNB_PRICE);
      await predictionMarket.resolve(predictionId);
    });
    
    it("Should allow winner to claim", async function () {
      const balanceBefore = await ethers.provider.getBalance(user1.address);
      
      await expect(
        predictionMarket.connect(user1).claim(predictionId)
      ).to.emit(predictionMarket, "WinningsClaimed");
      
      const balanceAfter = await ethers.provider.getBalance(user1.address);
      expect(balanceAfter).to.be.gt(balanceBefore);
    });
    
    it("Should reject claim from loser", async function () {
      await expect(
        predictionMarket.connect(user2).claim(predictionId)
      ).to.be.revertedWith("Did not win");
    });
    
    it("Should reject double claim", async function () {
      await predictionMarket.connect(user1).claim(predictionId);
      
      await expect(
        predictionMarket.connect(user1).claim(predictionId)
      ).to.be.revertedWith("Already claimed");
    });
    
    it("Should calculate correct winnings with 2% fee", async function () {
      // YES pool = 1 BNB, NO pool = 1 BNB
      // Winner gets: 1 BNB (their bet) + 0.98 BNB (98% of losing pool)
      // Expected: ~1.98 BNB
      
      const winnings = await predictionMarket.calculateWinnings(predictionId, user1.address);
      expect(winnings).to.equal(ethers.parseEther("1.98"));
    });
  });
  
  describe("Graduation Predictions", function () {
    let predictionId: bigint;
    let deadline: number;
    
    beforeEach(async function () {
      deadline = (await time.latest()) + ONE_DAY * 7;
      await predictionMarket.connect(tokenCreator).createPrediction(
        await mockToken.getAddress(),
        1, // GRADUATION
        0,
        deadline
      );
      predictionId = 1n;
      
      await predictionMarket.connect(user1).bet(predictionId, true, { value: ethers.parseEther("1") });
      await predictionMarket.connect(user2).bet(predictionId, false, { value: ethers.parseEther("1") });
    });
    
    it("Should resolve YES when graduated", async function () {
      await launchpadPool.setGraduated(true);
      await time.increaseTo(deadline);
      
      await predictionMarket.resolve(predictionId);
      
      const pred = await predictionMarket.getPrediction(predictionId);
      expect(pred.outcome).to.equal(true);
    });
    
    it("Should resolve NO when not graduated", async function () {
      await launchpadPool.setGraduated(false);
      await time.increaseTo(deadline);
      
      await predictionMarket.resolve(predictionId);
      
      const pred = await predictionMarket.getPrediction(predictionId);
      expect(pred.outcome).to.equal(false);
    });
  });
  
  describe("Admin Functions", function () {
    it("Should allow owner to pause", async function () {
      await expect(predictionMarket.pause())
        .to.emit(predictionMarket, "Paused")
        .withArgs(owner.address);
      
      expect(await predictionMarket.paused()).to.equal(true);
    });
    
    it("Should allow owner to unpause", async function () {
      await predictionMarket.pause();
      
      await expect(predictionMarket.unpause())
        .to.emit(predictionMarket, "Unpaused")
        .withArgs(owner.address);
      
      expect(await predictionMarket.paused()).to.equal(false);
    });
    
    it("Should reject non-owner pause", async function () {
      await expect(
        predictionMarket.connect(user1).pause()
      ).to.be.revertedWith("Not owner");
    });
    
    it("Should block betting when paused", async function () {
      const deadline = (await time.latest()) + ONE_DAY * 7;
      await predictionMarket.connect(tokenCreator).createPrediction(
        await mockToken.getAddress(),
        0,
        ethers.parseEther("100000"),
        deadline
      );
      
      await predictionMarket.pause();
      
      await expect(
        predictionMarket.connect(user1).bet(1, true, { value: MIN_BET })
      ).to.be.revertedWith("Contract paused");
    });
    
    it("Should implement 2-step ownership transfer", async function () {
      await predictionMarket.transferOwnership(user1.address);
      
      // Owner is still the original owner
      expect(await predictionMarket.owner()).to.equal(owner.address);
      expect(await predictionMarket.pendingOwner()).to.equal(user1.address);
      
      // Accept ownership
      await predictionMarket.connect(user1).acceptOwnership();
      
      expect(await predictionMarket.owner()).to.equal(user1.address);
      expect(await predictionMarket.pendingOwner()).to.equal(ethers.ZeroAddress);
    });
    
    it("Should allow owner to withdraw fees", async function () {
      const deadline = (await time.latest()) + ONE_DAY * 7;
      
      // Create prediction with fee
      await predictionMarket.connect(user1).createPrediction(
        await mockToken.getAddress(),
        0,
        ethers.parseEther("100000"),
        deadline,
        { value: CREATION_FEE }
      );
      
      const balanceBefore = await ethers.provider.getBalance(feeRecipient.address);
      
      await expect(predictionMarket.withdrawFees())
        .to.emit(predictionMarket, "FeesWithdrawn")
        .withArgs(feeRecipient.address, CREATION_FEE);
      
      const balanceAfter = await ethers.provider.getBalance(feeRecipient.address);
      expect(balanceAfter - balanceBefore).to.equal(CREATION_FEE);
    });
    
    it("Should allow emergency resolve", async function () {
      const deadline = (await time.latest()) + ONE_DAY * 7;
      await predictionMarket.connect(tokenCreator).createPrediction(
        await mockToken.getAddress(),
        0,
        ethers.parseEther("100000"),
        deadline
      );
      
      await time.increaseTo(deadline);
      
      await expect(
        predictionMarket.emergencyResolve(1, true)
      ).to.emit(predictionMarket, "PredictionResolved");
      
      const pred = await predictionMarket.getPrediction(1);
      expect(pred.resolved).to.equal(true);
      expect(pred.outcome).to.equal(true);
    });
  });
  
  describe("Oracle Validation", function () {
    it("Should reject stale oracle data", async function () {
      const deadline = (await time.latest()) + ONE_DAY * 7;
      await predictionMarket.connect(tokenCreator).createPrediction(
        await mockToken.getAddress(),
        0,
        ethers.parseEther("50000"),
        deadline
      );
      
      await predictionMarket.connect(user1).bet(1, true, { value: MIN_BET });
      
      // Set stale price (2 hours old)
      const staleTime = (await time.latest()) - 2 * ONE_HOUR;
      await oracle.setStalePrice(BNB_PRICE, staleTime);
      
      await time.increaseTo(deadline);
      
      await expect(
        predictionMarket.resolve(1)
      ).to.be.revertedWith("Oracle data too old");
    });
    
    it("Should reject zero price", async function () {
      await oracle.setPrice(0);
      
      await expect(
        predictionMarket.getBnbPriceUsd()
      ).to.be.revertedWith("Invalid BNB price");
    });
  });
  
  describe("View Functions", function () {
    it("Should return active predictions", async function () {
      const deadline = (await time.latest()) + ONE_DAY * 7;
      
      // Create 3 predictions
      for (let i = 0; i < 3; i++) {
        await predictionMarket.connect(tokenCreator).createPrediction(
          await mockToken.getAddress(),
          0,
          ethers.parseEther("100000"),
          deadline
        );
      }
      
      const active = await predictionMarket.getActivePredictions();
      expect(active.length).to.equal(3);
    });
    
    it("Should calculate potential winnings correctly", async function () {
      const deadline = (await time.latest()) + ONE_DAY * 7;
      await predictionMarket.connect(tokenCreator).createPrediction(
        await mockToken.getAddress(),
        0,
        ethers.parseEther("100000"),
        deadline
      );
      
      await predictionMarket.connect(user1).bet(1, true, { value: ethers.parseEther("1") });
      
      // If betting 1 BNB YES with 1 BNB already in YES pool
      const potential = await predictionMarket.calculatePotentialWinnings(1, true, ethers.parseEther("1"));
      
      // With empty NO pool, you just get your bet back
      expect(potential).to.equal(ethers.parseEther("1"));
    });
  });
});
