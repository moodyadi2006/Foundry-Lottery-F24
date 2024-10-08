// Layout of Contract:
// version
// imports
// errors
// interfaces,libraries, contracts
// Type declarations
// State variables
// Events
// Modifiers
// Functions

// Layout of Functions:
// constructor
// receive function
// fallback function
// external
// public
// internal
// private
// view and pure functions

// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;
import {VRFConsumerBaseV2Plus} from "@chainlink/contracts/src/v0.8/vrf/dev/VRFConsumerBaseV2Plus.sol";
import {VRFV2PlusClient} from "@chainlink/contracts/src/v0.8/vrf/dev/libraries/VRFV2PlusClient.sol";
import {console} from "forge-std/console.sol";

/**
 * @title A sample Raffle contract
 * @author Aditya Kumar
 * @notice This is going to be my first badass project
 * @dev implements Chainlink VRFv2.5
 */
contract Raffle is
    VRFConsumerBaseV2Plus //here, we have used abstract because Raffle is not a complete contract in itself and it needs to call functions from other contracts.
{
    /* Errors */
    error Raffle__SendMoreEth();
    error Raffle__transferFailed();
    error Raffle__RaffleNotOpen();
    error Raffle__UpkeepNotNeeded(
        uint256 balance,
        uint256 playersLength,
        uint256 raffleState
    );

    /* Type declarations */
    enum RaffleState {
        //enum is created to create custom types of finite set of constant values
        OPEN, //0
        CALCULATING //1
    }

    /* State Variables */
    uint16 private constant REQUEST_CONFIRMATIONS = 3;
    uint32 private constant NUM_WORDS = 1;
    uint32 private immutable i_callbackGasLimit;
    uint256 private immutable i_entranceFees; //here,"immutable" means very cheap amount of gas will be used but this value won't be changing
    uint256 private immutable i_interval;
    address payable[] private s_players; //this is how we make an array payable
    uint256 private s_lastTimeStamp;
    bytes32 private immutable i_keyHash;
    uint256 private immutable i_subscriptionId;
    address private s_recentWinner;
    RaffleState private s_raffleState;

    /* Events */
    event RaffleEntered(address indexed player);
    event winnerPicked(address indexed winner);
    event RequestedRaffleWinner(uint256 indexed requestId);

    constructor(
        uint entryFees,
        uint interval,
        address vrfCoordinator,
        bytes32 gasLane,
        uint256 subscriptionId,
        uint32 callbackGasLimit
    ) VRFConsumerBaseV2Plus(vrfCoordinator) {
        //Here, this coordinator is smart contract from which we will make request for random numbers.
        i_entranceFees = entryFees;
        i_interval = interval;
        s_lastTimeStamp = block.timestamp;
        i_keyHash = gasLane;
        i_subscriptionId = subscriptionId;
        i_callbackGasLimit = callbackGasLimit;
        s_raffleState = RaffleState.OPEN;
    }

    //In this function we want users give some entry fees and get joined in the pool
    function enterRaffle() external payable {
        //1. require(msg.value >= i_entryFees, "Not enough ETH sent!!!"); Here, We will not display string because it costs more and also we can not store dynamic information in it
        //Hence, We will use custom errors
        // require(msg.value >= i_entranceFees, SendMoreEth()); This is very much gas inefficient
        if (msg.value < i_entranceFees) {
            //msg.value means what amount is given by user
            revert Raffle__SendMoreEth(); // Custom errors are more gas efficient
        }
        if (s_raffleState != RaffleState.OPEN) {
            revert Raffle__RaffleNotOpen();
        }
        s_players.push(payable(msg.sender)); //It means address of sender is converted to a payable address
        //msg.sender is the person who sent the transaction
        /*People love to do work with events because:
        1. Makes migration easier, storage to new contract
        2. Makes front-end "indexing" easier*/
        emit RaffleEntered(msg.sender);
    }

    //when the winner should be picked?
    /**
     * @dev this is the function that the Chainlink nodes will call to see if lottery is ready to have a winner picked.
     * the following should be true in order for upKeepNeeded to be true:
     * 1. the time interval has passed between raffle runs
     * 2. The lottery is open.
     * 3. the contract has ETH (has players to play)
     * 4. Implicitly, your subscription has LINK
     * @param -ignored
     * @return upkeepNeeded -true if it's time to restart a lottery
     * @return -ignored
     */
    function checkUpkeep(
        bytes memory /* checkData */
    )
        public
        view
        returns (
            bool upkeepNeeded,
            bytes memory /* performData */ //upkeepNeeded tells whether its time to pick a winner and bytes memory tells what to do with this upKeep
        )
    {
        bool timeHasPassed = ((block.timestamp - s_lastTimeStamp) >=
            i_interval);
        bool isOpen = s_raffleState == RaffleState.OPEN;
        bool hasBalance = address(this).balance > 0;
        bool hasPlayers = s_players.length > 0;
        upkeepNeeded = timeHasPassed && isOpen && hasBalance && hasPlayers;
        return (upkeepNeeded, "");
    }

    //1. Get Random Number
    //2. Use random number to pick a player
    //3. Be automatically called

    // To pick a Winner automatically we will use Chainlink Automation also known as Chainlink keeper
    function performUpkeep(bytes calldata /* performData */) external {
        //Check if enough time has passed
        (bool upkeepNeeded, ) = checkUpkeep("");
        if (!upkeepNeeded) {
            revert Raffle__UpkeepNotNeeded(
                address(this).balance,
                s_players.length,
                uint256(s_raffleState)
            );
        }
        //Get our Random Number
        //1. Request RNG
        //2. Get RNG
        s_raffleState = RaffleState.CALCULATING;
        VRFV2PlusClient.RandomWordsRequest memory request = VRFV2PlusClient
            .RandomWordsRequest({
                keyHash: i_keyHash, //Maximum gas price that you are willing to pay in a request
                subId: i_subscriptionId, //Whenever we works with chainlink for our subscription then every single node gets a subscription ID
                requestConfirmations: REQUEST_CONFIRMATIONS, // It means after we send a request, how many blocks we have to wait before getting a random number
                callbackGasLimit: i_callbackGasLimit, // This is the gas limit in calling back a function
                numWords: NUM_WORDS, // This is number of random numbers that we want
                // Set nativePayment to true to pay for VRF requests with Sepolia ETH instead of LINK
                extraArgs: VRFV2PlusClient._argsToBytes(
                    VRFV2PlusClient.ExtraArgsV1({nativePayment: false})
                )
            });
        uint256 requestId = s_vrfCoordinator.requestRandomWords(request); //It is a kind of coordinator that requests random words
        emit RequestedRaffleWinner(requestId);  //It is redundant because vrfCoordinator and we both are emitting the requestId
    }

    //CEI- Checks, Effects and Interactions Pattern helps us to make our smart contract safer
    //We have marked this function override because it was written virtual in VRFConsumerBaseV2Plus, So it was meant to be overridden
    function fulfillRandomWords(
        uint256, //requestId,
        uint256[] calldata randomWords
    ) internal override {
        //CHECKS

        //EVENTS(Internal Contract state)
        uint256 indexOfWinner = randomWords[0] % s_players.length;
        address payable recentWinner = s_players[indexOfWinner];
        s_recentWinner = recentWinner;
        s_raffleState = RaffleState.OPEN;
        s_players = new address payable[](0); //this will wipe out everything in the array
        s_lastTimeStamp = block.timestamp; // this will restart our clock to pick a winner
        emit winnerPicked(s_recentWinner);

        //INTERACTIONS(External Contract interactions)
        (bool success, ) = recentWinner.call{value: address(this).balance}("");
        if (!success) {
            revert Raffle__transferFailed();
        }
    }

    /**
     * Getter Functions
     */
    function getEntranceFees() external view returns (uint256) {
        return i_entranceFees;
    }

    function getRaffleState() external view returns (RaffleState) {
        return s_raffleState;
    }

    function getPlayer(uint256 indexOfPlayer) external view returns (address) {
        return s_players[indexOfPlayer]; //this function is just created to get players from an array
    }

    function getLastTimeStamp() external view returns(uint256) {
        return s_lastTimeStamp;
    }

    function getRecentWinner() external view returns(address) {
        return s_recentWinner;
    }
}
