// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Hackathon} from "./HackHub.sol";
import {IERC20Minimal} from "./Interfaces.sol";
import {HackHubUtils} from "./HackHubUtils.sol";

error OnlyOngoingHackathons();
error OnlyHackathonContract();
error TokenTransferFailed();

contract HackHubFactory {
    address[] public ongoingHackathons;
    address[] public pastHackathons;
    
    mapping(address => address[]) private participantOngoing;
    mapping(address => address[]) private participantPast;
    mapping(address => address[]) private judgeOngoing;
    mapping(address => address[]) private judgePast;
    mapping(address => bool) public isOngoing;
    
    event HackathonCreated(address indexed hackathon, address indexed organizer);
    event HackathonConcluded(address indexed hackathon);
    event ParticipantRegistered(address indexed hackathon, address indexed participant);
    event JudgeRegistered(address indexed hackathon, address indexed judge);

    function createHackathon(
        string memory name,
        uint256 startTime, 
        uint256 endTime,
        string memory startDate,
        string memory endDate,
        address[] memory judges,
        uint256[] memory tokenPerJudge,
        string[] memory judgeNames,
        address prizeToken,
        uint256 prizeAmount 
    ) external payable {
        Hackathon h = (new Hackathon){value: msg.value}(
            name, startTime, endTime, startDate, endDate, judges, tokenPerJudge, judgeNames, prizeToken, prizeAmount
        );
        
        if (prizeToken != address(0)) {
            if (!IERC20Minimal(prizeToken).transferFrom(msg.sender, address(h), prizeAmount)) {
                revert TokenTransferFailed();
            }
        }
        
        address hackAddr = address(h);
        isOngoing[hackAddr] = true;
        ongoingHackathons.push(hackAddr);

        uint256 judgeCount = judges.length;
        for (uint256 i; i < judgeCount;) {
            address j = judges[i];
            judgeOngoing[j].push(hackAddr);
            emit JudgeRegistered(hackAddr, j);
            unchecked { ++i; }
        }
        
        emit HackathonCreated(hackAddr, msg.sender);
    }

    function registerParticipant(address participant) external {
        if (!isOngoing[msg.sender]) revert OnlyOngoingHackathons();
        participantOngoing[participant].push(msg.sender);
        emit ParticipantRegistered(msg.sender, participant);
    }

    function hackathonConcluded(address hackathon) external {
        if (msg.sender != hackathon || !isOngoing[hackathon]) revert OnlyHackathonContract();
        
        HackHubUtils.removeFromArray(ongoingHackathons, hackathon);
        pastHackathons.push(hackathon);
        isOngoing[hackathon] = false;
        
        Hackathon h = Hackathon(hackathon);
        uint256 judgeCount = h.judgeCount();
        
        for (uint256 i; i < judgeCount;) {
            address[] memory judges = h.getJudges(i, i);
            if (judges.length > 0) {
                HackHubUtils.moveItem(judgeOngoing[judges[0]], judgePast[judges[0]], hackathon);
            }
            unchecked { ++i; }
        }

        address[] memory participants = h.getParticipants();
        for (uint256 i; i < participants.length;) {
            HackHubUtils.moveItem(participantOngoing[participants[i]], participantPast[participants[i]], hackathon);
            unchecked { ++i; }
        }

        emit HackathonConcluded(hackathon);
    }
    
    function getCounts() external view returns (uint256 ongoing, uint256 past) {
        return (ongoingHackathons.length, pastHackathons.length);
    }

    function getUserCounts(address user) external view returns (
        uint256 participantOngoingCount, 
        uint256 participantPastCount, 
        uint256 judgeOngoingCount, 
        uint256 judgePastCount
    ) {
        return (
            participantOngoing[user].length,
            participantPast[user].length,
            judgeOngoing[user].length,
            judgePast[user].length
        );
    }
    
    function getHackathons(uint256 start, uint256 end, bool ongoing) external view returns (address[] memory) {
        return HackHubUtils.getSlice(ongoing ? ongoingHackathons : pastHackathons, start, end);
    }
    function getParticipantHackathons(address participant, uint256 start, uint256 end, bool ongoing) 
        external view returns (address[] memory) { 
        return HackHubUtils.getSlice(ongoing ? participantOngoing[participant] : participantPast[participant], start, end); 
    }
    function getJudgeHackathons(address judge, uint256 start, uint256 end, bool ongoing) 
        external view returns (address[] memory) { 
        return HackHubUtils.getSlice(ongoing ? judgeOngoing[judge] : judgePast[judge], start, end); 
    }
}