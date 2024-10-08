// SPDX-license-Identifier: MIT
pragma solidity 0.8.19;
import {Test} from "forge-std/Test.sol";
import {VRFCoordinatorV2_5Mock} from "@chainlink/contracts/src/v0.8/vrf/mocks/VRFCoordinatorV2_5Mock.sol";
import {DeployRaffle} from "script/DeployRaffle.s.sol";
import {Raffle} from "src/Raffle.sol";
import {HelperConfig} from "script/HelperConfig.s.sol";
import "forge-std/StdCheats.sol";
import {Vm} from "forge-std/Vm.sol";
import {CodeConstants} from "script/HelperConfig.s.sol";

contract RaffleTest is CodeConstants,Test {
    Raffle public raffle;
    HelperConfig public helperConfig;

    uint entryFees;
    uint interval;
    address vrfCoordinator;
    bytes32 gasLane;
    uint subscriptionId;
    uint32 callbackGasLimit;

    address public PLAYER = makeAddr("player"); // It allows us to make address using some string
    uint public constant STARTING_PLAYER_BALANCE = 10 ether;

    /*EVENTS */
    event RaffleEntered(address indexed player); //maximum number of indexed parameters allowed in a single event is 3
    event winnerPicked(address indexed winner);

    function setUp() external {
        DeployRaffle deployer = new DeployRaffle();
        (raffle, helperConfig) = deployer.deployContract();
        HelperConfig.NetworkConfig memory config = helperConfig.getConfig();
        entryFees = config.entryFees;
        interval = config.interval;
        vrfCoordinator = config.vrfCoordinator;
        gasLane = config.gasLane;
        subscriptionId = config.subscriptionId;
        callbackGasLimit = config.callbackGasLimit;

        vm.deal(PLAYER, STARTING_PLAYER_BALANCE);
    }

    function testRaffleInitializesInOpenState() public view {
        // We are doing this to check that initially the game is open so anyone can take part
        assert(raffle.getRaffleState() == Raffle.RaffleState.OPEN);
    }

    function testRaffleRevertWhenYoudDontPayEnough() public {
        //Arrange
        vm.prank(PLAYER);
        //Act
        vm.expectRevert(Raffle.Raffle__SendMoreEth.selector);
        //Assert
        raffle.enterRaffle();
    }

    function testRaffleRecordsPlayersWhenTheyEnter() public {
        //Arrange
        vm.prank(PLAYER);
        //Act
        raffle.enterRaffle{value: entryFees}();
        //Assert
        address playerRecorded = raffle.getPlayer(0);
        assert(playerRecorded == PLAYER);
    }

    function testEnteringRaffleEmitsEvent() public {
        //Arrange
        vm.prank(PLAYER);
        //Act
        vm.expectEmit(true, false, false, false, address(raffle)); // Only one true because of address indexed player
        emit RaffleEntered(PLAYER);
        //Assert
        raffle.enterRaffle{value: entryFees}();
    }

    function testDontAllowPlayersToEnterWhileRaffleIsCalculating() public {
        //Arrange
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entryFees}();
        vm.warp(block.timestamp + interval + 1); //It is used to wait for a certain period of time
        vm.roll(block.number + 1); //It will roll by current block number or will change current block
        raffle.performUpkeep("");
        //Act
        vm.expectRevert(Raffle.Raffle__RaffleNotOpen.selector); //this is written to revert if above condition is going on
        vm.prank(PLAYER);
        //Assert
        raffle.enterRaffle{value: entryFees}();
    }

    /*///////////////////////////////////////////////////////////////
                        CHECK UPKEEP
    ///////////////////////////////////////////////////////////////*/

    function testCheckUpkeepReturnsFalseIfItHasNoBalance() public {
        //Arrange
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);

        //Act
        (bool upkeepNeeded, ) = raffle.checkUpkeep("");

        //Assert
        assert(!upkeepNeeded);
    }

    function testCheckUpkeepReturnsFalseIfRaffleIsNotOpen() public {
        //Arrange
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entryFees}();
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);
        raffle.performUpkeep("");

        //Act
        (bool upkeepNeeded, ) = raffle.checkUpkeep("");

        //Assert
        assert(!upkeepNeeded);
    }

    //CHALLENGE: Write tests for all the lines in a coverage.txt
    // write a testCheckUpkeepReturnsFalseIfEnoughTimeHasPassed
    // write a testCheckUpkeepReturnsTrue WhenParametersAreGood

    /*///////////////////////////////////////////////////////////////
                        PERFORM UPKEEP
    ///////////////////////////////////////////////////////////////*/

    function testPerformUpkeepCanOnlyRunIfCheckUpkeepIsTrue() public {
        //Arrange
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entryFees}();
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);

        //Act /assert
        raffle.performUpkeep("");
    }

    function testPerformUpkeepRevertsIfCheckUpkeepIsFalse() public {
        //Arrange
        uint currentBalance = 0;
        uint numPlayers = 0;
        Raffle.RaffleState raffleState = raffle.getRaffleState();

        vm.prank(PLAYER);
        raffle.enterRaffle{value: entryFees}();
        currentBalance = currentBalance + entryFees;
        numPlayers = 1;

        //Act  /  assert
        vm.expectRevert(
            abi.encodeWithSelector(
                Raffle.Raffle__UpkeepNotNeeded.selector,
                currentBalance,
                numPlayers,
                raffleState
            )
        );
        raffle.performUpkeep("");
    }

    modifier raffleEntered() {
        //If we want to use a singlw kind of code again and again then we can modularize it using a modifier
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entryFees}();
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);
        _;
    }

    //What if we need to get  data from emitted events in our tests?
    function testPerformUpkeepUpdatesRaffleStateAndEmitsRequestId()
        public
        raffleEntered
    {
        //Act
        vm.recordLogs();
        raffle.performUpkeep(""); //recordLogs says whatever events are emitted by this function keep their record in an array
        Vm.Log[] memory entries = vm.getRecordedLogs();
        bytes32 requestId = entries[1].topics[1]; //Our event will come after vrf therefore, in entries we have written [0]
        // We are using topics[1] because 0 is reserved for something else

        //Assert
        Raffle.RaffleState raffleState = raffle.getRaffleState();
        assert(uint256(requestId) > 0);
        assert(uint256(raffleState) == 1); //We are ensuring that we get requestId when raffleState is converted
    }

    /*///////////////////////////////////////////////////////////////
                        FULFILL RANDOMWORDS
    ///////////////////////////////////////////////////////////////*/

    modifier skipFork() {
        if (block.chainid != LOCAL_CHAIN_ID) {
            return;
        }
        _;
    }

    function testFulfillRandomWordsCanOnlyBeCalledAfterPerformUpkeep(
        uint256 randomRequestId
    ) public raffleEntered skipFork {
        // Arrange / Act / Assert
        vm.expectRevert(VRFCoordinatorV2_5Mock.InvalidRequest.selector);
        VRFCoordinatorV2_5Mock(vrfCoordinator).fulfillRandomWords(
            randomRequestId,
            address(raffle)
        );
        //Here we have made it a fuzz test which tries to break our code in different cases as specified in .env file
        // This is a stateless fuzz test
    }

    function testFulfillRandomWordsPicksAWinnerResetsAndSendsMoney()
        public
        raffleEntered skipFork
    {
        //Arrange
        uint additionalEntrants = 3; //4 total
        uint startingIndex = 1;
        address expectedWinner = address(1);
        for (
            uint256 i = startingIndex;
            i < startingIndex + additionalEntrants;
            i++
        ) {
            address newPlayer = address(uint160(i));
            hoax(newPlayer, 1 ether); //It will give the new players 1 ether
            raffle.enterRaffle{value: entryFees}();
        }
        uint256 startingTimeStamp = raffle.getLastTimeStamp();
        uint256 winnerStartingBalance = expectedWinner.balance;

        //Act
        vm.recordLogs();
        raffle.performUpkeep("");
        Vm.Log[] memory entries = vm.getRecordedLogs();
        bytes32 requestId = entries[1].topics[1];
        VRFCoordinatorV2_5Mock(vrfCoordinator).fulfillRandomWords(
            uint256(requestId),
            address(raffle)
        );
        //Assert
        address recentWinner = raffle.getRecentWinner();
        Raffle.RaffleState raffleState = raffle.getRaffleState();
        uint winnerBalance = recentWinner.balance;
        uint endingTimeStamp = raffle.getLastTimeStamp();
        uint prize = entryFees * (additionalEntrants + 1);
        assert(recentWinner == expectedWinner);
        assert(uint256(raffleState) == 0);
        assert(winnerBalance == winnerStartingBalance + prize);
        assert(endingTimeStamp > startingTimeStamp);
    }
}

/*
Q - What is a forked test?
Ans- A test that runs against a local copy of a live blockchain
, allowing interaction with deployed contracts and current state 
without affecting the actual network. */

/**
 Fuzz Testing  is a type of test that helps identify vulnerabilities in a smart contract
  by systematically inputting random data values.
 */
