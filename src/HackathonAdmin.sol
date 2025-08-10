// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Hackathon} from "./HackHub.sol";
import {HackHubUtils} from "./HackHubUtils.sol";
// Judge struct & utility functions are in HackHubUtils

library HackathonAdmin {
    // Errors
    error OnlyOngoingHackathons();
    error OnlyHackathonContract();

    // Events
    event ParticipantRegistered(address indexed hackathon, address indexed participant);
    event JudgeRegistered(address indexed hackathon, address indexed judge);
    event HackathonConcluded(address indexed hackathon);

    function registerParticipant(
        mapping(address => bool) storage isOngoing,
        mapping(address => address[]) storage participantOngoing,
        address participant
    ) external {
        if (!isOngoing[msg.sender]) revert OnlyOngoingHackathons();
        participantOngoing[participant].push(msg.sender);
        emit ParticipantRegistered(msg.sender, participant);
    }

    function registerJudge(
        mapping(address => bool) storage isOngoing,
        mapping(address => address[]) storage judgeOngoing,
        address judge
    ) external {
        if (!isOngoing[msg.sender]) revert OnlyOngoingHackathons();
        judgeOngoing[judge].push(msg.sender);
        emit JudgeRegistered(msg.sender, judge);
    }

    function getUserCounts(
        mapping(address => address[]) storage participantOngoing,
        mapping(address => address[]) storage participantPast,
        mapping(address => address[]) storage judgeOngoing,
        mapping(address => address[]) storage judgePast,
        address user
    ) external view returns (
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

    // ---------------- Conclusion -----------------
    function concludeHackathon(
        address[] storage ongoingHackathons,
        address[] storage pastHackathons,
        mapping(address => bool) storage isOngoing,
        mapping(address => address[]) storage participantOngoing,
        mapping(address => address[]) storage participantPast,
        mapping(address => address[]) storage judgeOngoing,
        mapping(address => address[]) storage judgePast,
        address hackathon
    ) external {
        if (msg.sender != hackathon || !isOngoing[hackathon]) revert OnlyHackathonContract();

        // Move hackathon to past
        HackHubUtils.removeFromArray(ongoingHackathons, hackathon);
        pastHackathons.push(hackathon);
        isOngoing[hackathon] = false;

        Hackathon h = Hackathon(hackathon);

        address[] memory judges = h.getAllJudges();
        for (uint256 i; i < judges.length;) {
            HackHubUtils.moveItem(judgeOngoing[judges[i]], judgePast[judges[i]], hackathon);
            unchecked { ++i; }
        }

        address[] memory participants = h.getParticipants();
        for (uint256 i; i < participants.length;) {
            HackHubUtils.moveItem(participantOngoing[participants[i]], participantPast[participants[i]], hackathon);
            unchecked { ++i; }
        }

        emit HackathonConcluded(hackathon);
    }
}
