// SPDX-license-Identifier: MIT
pragma solidity 0.8.19;

import {Script} from "forge-std/Script.sol";
import {Raffle} from "src/Raffle.sol";
import {HelperConfig} from "./HelperConfig.s.sol";
import {CreateSubscription, FundSubscription, AddConsumer} from "script/Interactions.s.sol";

contract DeployRaffle is Script {
    function run() public {
        deployContract();
    }

    function deployContract() public returns (Raffle, HelperConfig) {
        HelperConfig helperConfig = new HelperConfig();

        //local -> deploy mocks, get local config
        // sepolia -> get sepolia config
        HelperConfig.NetworkConfig memory config = helperConfig.getConfig();

        if(config.subscriptionId==0){
            //create subscription
            CreateSubscription createSubscription = new CreateSubscription();
            (config.subscriptionId, config.vrfCoordinator) = createSubscription.createSubscription(config.vrfCoordinator, config.account);

            //Fund it !!!
            FundSubscription fundSubscription = new FundSubscription();
            fundSubscription.fundSubscription(config.vrfCoordinator, config.subscriptionId, config.link, config.account);
            
        }

        vm.startBroadcast(config.account); // this is used to record the transactions in current session
        Raffle raffle = new Raffle(
            config.entryFees,
            config.interval,
            config.vrfCoordinator,
            config.gasLane,
            config.subscriptionId,
            config.callbackGasLimit
        );
        vm.stopBroadcast(); // this is used to stop recording transactions in the current session

        AddConsumer addConsumer = new AddConsumer();
        //We don't need to broadcast here because we have done it in AddConsumer function
        addConsumer.addConsumer(address(raffle), config.vrfCoordinator, config.subscriptionId, config.account);

        return (raffle, helperConfig);
    }
}