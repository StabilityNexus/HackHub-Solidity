// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Hackathon} from "./HackHub.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

error OnlyOngoingHackathons();
error OnlyHackathonContract();
error HackathonNotOngoing();
error InvalidIndexRange();
error EndIndexOutOfBounds();
error TokenTransferFailed();

contract HackHubFactory {
    address[] public ongoingHackathons;
    address[] public pastHackathons;
    
    mapping(address => address[]) private participantOngoingHackathons;
    mapping(address => address[]) private participantPastHackathons;

    mapping(address => address[]) private judgeOngoingHackathons;
    mapping(address => address[]) private judgePastHackathons;

    mapping(address => bool) public isOngoing;
    
    event HackathonCreated(address indexed hackathon, address indexed organizer);
    event HackathonConcluded(address indexed hackathon);
    event ParticipantRegistered(address indexed hackathon, address indexed participant);
    event JudgeRegistered(address indexed hackathon, address indexed judge);

    function createHackathon(
        string   memory name,
        uint256         startDate,
        uint256         startTime, 
        uint256         submissionEndDate,
        uint256         submissionEndTime,
        address[]memory judges,
        uint256[]memory tokenPerJudge,
        address         prizeToken,
        uint256         prizeAmount 
    ) external payable {
        if (prizeToken != address(0)) {
            bool success = IERC20(prizeToken).transferFrom(msg.sender, address(this), prizeAmount);
            if (!success) revert TokenTransferFailed();
            IERC20(prizeToken).approve(address(this), prizeAmount);
        }

        Hackathon h = (new Hackathon){value: msg.value}(
            name,
            startDate,
            startTime,
            submissionEndDate,
            submissionEndTime,
            judges,
            tokenPerJudge,
            prizeToken,
            prizeAmount
        );
        isOngoing[address(h)] = true;
        ongoingHackathons.push(address(h));

        for (uint256 i = 0; i < judges.length; i++) {
            address j = judges[i];
            judgeOngoingHackathons[j].push(address(h));
            emit JudgeRegistered(address(h), j);
        }
        
        emit HackathonCreated(address(h), msg.sender);
    }

    function registerParticipant(address participant) external {
        if (!isOngoing[msg.sender]) revert OnlyOngoingHackathons();
        participantOngoingHackathons[participant].push(msg.sender);
        emit ParticipantRegistered(msg.sender, participant);
    }

    function hackathonConcluded(address hackathon) external {
        if (msg.sender != hackathon) revert OnlyHackathonContract();
        if (!isOngoing[hackathon]) revert HackathonNotOngoing();
        for (uint i = 0; i < ongoingHackathons.length; i++) {
            if (ongoingHackathons[i] == hackathon) {
                ongoingHackathons[i] = ongoingHackathons[ongoingHackathons.length - 1];
                ongoingHackathons.pop();
                break;
            }
        }
        pastHackathons.push(hackathon);
        isOngoing[hackathon] = false;
        Hackathon hackHubContract = Hackathon(hackathon);
        uint256 judgeCount = hackHubContract.judgeCount();
        
        for (uint256 i = 0; i < judgeCount; i++) {
            address[] memory judges = hackHubContract.getJudges(i, i);
            if (judges.length > 0) {
                address judge = judges[0];
                _moveHackathonBetweenArrays(judgeOngoingHackathons[judge], judgePastHackathons[judge], hackathon);
            }
        }

        uint256 participantCount = hackHubContract.participantCount();
        for (uint256 i = 0; i < participantCount; i++) {
            address[] memory participants = hackHubContract.getParticipants(i, i);
            if (participants.length > 0) {
                address participant = participants[0];
                _moveHackathonBetweenArrays(participantOngoingHackathons[participant], participantPastHackathons[participant], hackathon);
            }
        }

        emit HackathonConcluded(hackathon);
    }
    
    function getOngoingCount() external view returns (uint256) { return ongoingHackathons.length; }
    function getPastCount() external view returns (uint256) { return pastHackathons.length; }
    
    function getOngoingHackathons(uint256 startIndex, uint256 endIndex) external view returns (address[] memory) { return _getSlice(ongoingHackathons, startIndex, endIndex);}
    function getPastHackathons(uint256 startIndex, uint256 endIndex) external view returns (address[] memory) { return _getSlice(pastHackathons, startIndex, endIndex);}
    
    function getParticipantOngoingHackathons(address participant, uint256 startIndex, uint256 endIndex) external view returns (address[] memory) { return _getSlice(participantOngoingHackathons[participant], startIndex, endIndex); }
    function getParticipantPastHackathons(address participant, uint256 startIndex, uint256 endIndex) external view returns (address[] memory) { return _getSlice(participantPastHackathons[participant], startIndex, endIndex); }
    
    function getJudgeOngoingHackathons(address judge, uint256 startIndex, uint256 endIndex) external view returns (address[] memory) { return _getSlice(judgeOngoingHackathons[judge], startIndex, endIndex); }
    function getJudgePastHackathons(address judge, uint256 startIndex, uint256 endIndex) external view returns (address[] memory) { return _getSlice(judgePastHackathons[judge], startIndex, endIndex); }

    function getParticipantOngoingCount(address participant) external view returns (uint256) { return participantOngoingHackathons[participant].length; }
    function getParticipantPastCount(address participant) external view returns (uint256) { return participantPastHackathons[participant].length; }

    function getJudgeOngoingCount(address judge) external view returns (uint256) { return judgeOngoingHackathons[judge].length; }
    function getJudgePastCount(address judge) external view returns (uint256) { return judgePastHackathons[judge].length; }

    function _getSlice(address[] storage source, uint256 startIndex, uint256 endIndex) internal view returns (address[] memory) {
        if (startIndex > endIndex) revert InvalidIndexRange();
        if (endIndex >= source.length) revert EndIndexOutOfBounds();
        uint256 length = endIndex - startIndex + 1;
        address[] memory result = new address[](length);
        for (uint256 i = 0; i < length; i++) {
            result[i] = source[startIndex + i];
        }
        return result;
    }

    function _moveHackathonBetweenArrays(address[] storage fromArr, address[] storage toArr, address hackathon) internal {
        toArr.push(hackathon);
        for (uint256 i = 0; i < fromArr.length; i++) {
            if (fromArr[i] == hackathon) {
                fromArr[i] = fromArr[fromArr.length - 1];
                fromArr.pop();
                return;
            }
        }
    }
}