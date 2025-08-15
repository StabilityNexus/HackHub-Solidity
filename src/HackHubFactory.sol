// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {HackHubUtils} from "./HackHubUtils.sol";
import {HackathonAdmin} from "./HackathonAdmin.sol";
import {Hackathon} from "./HackHub.sol";

contract HackHubFactory {
    
    error TokenTransferFailed();
    
    event HackathonCreated(address indexed hackathon, address indexed organizer);
    address[] public ongoingHackathons;
    address[] public pastHackathons;
    
    mapping(address => address[]) private participantOngoing;
    mapping(address => address[]) private participantPast;
    mapping(address => address[]) private judgeOngoing;
    mapping(address => address[]) private judgePast;
    mapping(address => bool) public isOngoing;

    /**
    * @dev Assumption: judge addresses are unique.
    * The contract does NOT enforce uniqueness on-chain. The frontend/integration MUST
    * ensure no two judges share the same address (no duplicates are submitted).
    */
    function createHackathon(string memory name, uint256 startTime, uint256 endTime, string memory startDate, string memory endDate, 
        address[] memory judges, uint256[] memory tokenPerJudge, string memory imageURL ) external payable {
        Hackathon h = (new Hackathon){value: msg.value}(name, startTime, endTime, startDate, endDate, judges, tokenPerJudge, imageURL);
        address hackathonAddr = address(h);

        isOngoing[hackathonAddr] = true;
        ongoingHackathons.push(hackathonAddr);
        emit HackathonCreated(hackathonAddr, msg.sender);
    }

    function registerParticipant(address participant) external { HackathonAdmin.registerParticipant(isOngoing, participantOngoing, participant); }
    function registerJudge(address judge) external { HackathonAdmin.registerJudge(isOngoing, judgeOngoing, judge); }
    function getCounts() external view returns (uint256 ongoing, uint256 past) { return (ongoingHackathons.length, pastHackathons.length); }

    function hackathonConcluded(address hackathon) external {
        HackathonAdmin.concludeHackathon(
            ongoingHackathons, pastHackathons, isOngoing,
            participantOngoing, participantPast, judgeOngoing, judgePast, hackathon
        );
    }

    function getUserCounts(address user) external view returns (uint256 participantOngoingCount, uint256 participantPastCount, uint256 judgeOngoingCount, uint256 judgePastCount) {
        return (
            participantOngoing[user].length,
            participantPast[user].length,
            judgeOngoing[user].length,
            judgePast[user].length
        );
    }
    
    function getHackathons(uint256 start, uint256 end, bool ongoing) external view returns (address[] memory) { return HackHubUtils.getSlice(ongoing ? ongoingHackathons : pastHackathons, start, end); }
    function getParticipantHackathons(address participant, uint256 start, uint256 end, bool ongoing) external view returns (address[] memory) {  return HackHubUtils.getSlice(ongoing ? participantOngoing[participant] : participantPast[participant], start, end); }
    function getJudgeHackathons(address judge, uint256 start, uint256 end, bool ongoing) external view returns (address[] memory) { return HackHubUtils.getSlice(ongoing ? judgeOngoing[judge] : judgePast[judge], start, end); }
}