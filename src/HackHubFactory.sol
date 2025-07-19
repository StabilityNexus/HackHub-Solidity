// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {HackHub} from "./HackHub.sol";

contract HackHubFactory {
    address[] public ongoingHackathons;
    address[] public pastHackathons;
    
    mapping(address => bool) public isOngoing;
    
    event HackathonCreated(address indexed hackathon, address indexed organizer);
    event HackathonConcluded(address indexed hackathon);

    function createHackathon(
        string   memory name,
        uint256         startTime,
        uint256         endTime,                 // end time of submission of projects
        address[]memory judges,
        string[] memory judgeNames,
        uint256[]memory tokenPerJudge
    ) external payable {
        HackHub h = (new HackHub){value: msg.value}(
            name,
            startTime,
            endTime,
            judges,
            judgeNames,
            tokenPerJudge
        );
        ongoingHackathons.push(address(h));
        isOngoing[address(h)] = true;
        emit HackathonCreated(address(h), msg.sender);
    }

    /// @notice Called by Hackathon contract when it's concluded
    function hackathonConcluded(address hackathon) external {
        require(msg.sender == hackathon, "Only hackathon can call this");
        require(isOngoing[hackathon], "Hackathon not in ongoing list");
        
        for (uint i = 0; i < ongoingHackathons.length; i++) {
            if (ongoingHackathons[i] == hackathon) {
                ongoingHackathons[i] = ongoingHackathons[ongoingHackathons.length - 1];
                ongoingHackathons.pop();
                break;
            }
        }
        pastHackathons.push(hackathon);
        isOngoing[hackathon] = false;
        emit HackathonConcluded(hackathon);
    }

    function getOngoingHackathons(uint256 startIndex, uint256 endIndex) external view returns (address[] memory) {
        require(startIndex <= endIndex, "Invalid index range");
        require(endIndex < ongoingHackathons.length, "End index out of bounds");
        
        uint256 length = endIndex - startIndex + 1;
        address[] memory result = new address[](length);
        for (uint256 i = 0; i < length; i++) result[i] = ongoingHackathons[startIndex + i];
        return result;
    }
    
    function getPastHackathons(uint256 startIndex, uint256 endIndex) external view returns (address[] memory) {
        require(startIndex <= endIndex, "Invalid index range");
        require(endIndex < pastHackathons.length, "End index out of bounds");
        
        uint256 length = endIndex - startIndex + 1;
        address[] memory result = new address[](length);
        for (uint256 i = 0; i < length; i++) result[i] = pastHackathons[startIndex + i];
        return result;
    }
    
    function getOngoingCount() external view returns (uint256) { return ongoingHackathons.length; }
    function getPastCount() external view returns (uint256) { return pastHackathons.length; }
}