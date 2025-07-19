// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

error HackHub__InvalidParams();
error HackHub__NotJudge();
error HackHub__SubmissionClosed();
error HackHub__AlreadyDistributed();
error HackHub__NoVotesCast();
error HackHub__NotAfterEndTime();
error HackHub__AlreadyClaimed();
error HackHub__NoTokensToVote();
error HackHub__InsufficientTokens();
error HackHub__AlreadyConcluded();

interface IHackHubFactory {
    function hackathonConcluded(address hackathon) external;
}

contract HackHub is Ownable {
    struct Judge {
        address addr;
        string  name;
    }
    struct Project {
        address submitter;
        string  sourceCode;
        string  documentation;
    }

    string  public hackathonName;
    uint256 public startTime;
    uint256 public endTime;
    uint256 public prizePool;             // in wei
    uint256 public totalTokens;           // total tokens assigned to all judges
    bool    public concluded;             // whether hackathon has been concluded
    address public factory;               // factory contract address

    Judge[] public judges;
    mapping(address => bool) public isJudge;
    mapping(address => uint256) public judgeTokens;  // judge address → number of tokens
    
    Project[] public projects;
    mapping(uint256 => uint256) public projectTokens; // projectId → tokens received
    mapping(uint256 => bool) public prizeClaimed;   // projectId → has claimed prize
    bool public distributed;

    event ProjectSubmitted(uint256 indexed projectId, address indexed submitter);
    event Voted(address indexed judge, uint256 indexed projectId, uint256 amount);
    event PrizeIncreased(uint256 newPrizePool, uint256 addedAmount);
    event TokensAdjusted(address indexed judge, uint256 newTokenAmount);
    event prizeShareClaimed(uint256 indexed projectId, address indexed submitter, uint256 amount);
    event HackathonConcluded();

    modifier duringSubmission() {
        if (block.timestamp < startTime || block.timestamp > endTime) {
            revert HackHub__SubmissionClosed();
        }
        _;
    }
    modifier afterEnd() {
        if (block.timestamp <= endTime) {
            revert HackHub__NotAfterEndTime();
        }
        _;
    }
    
    constructor(
        string   memory _name,
        uint256         _startTime,
        uint256         _endTime,
        address[]memory _judgeAddrs,
        string[] memory _judgeNames,
        uint256[]memory _tokenPerJudge
    ) payable Ownable(tx.origin) {
        if ( _startTime >= _endTime || msg.value == 0 || _judgeAddrs.length != _judgeNames.length || _judgeAddrs.length != _tokenPerJudge.length) 
            revert HackHub__InvalidParams();

        hackathonName = _name;
        startTime     = _startTime;
        endTime       = _endTime;
        prizePool     = msg.value;
        factory       = msg.sender;  // factory is the one creating this contract

        for (uint i; i < _judgeAddrs.length; i++) {
            address j = _judgeAddrs[i];
            judges.push(Judge({ addr: j, name: _judgeNames[i] }));
            isJudge[j] = true;
            judgeTokens[j] = _tokenPerJudge[i];
            totalTokens += _tokenPerJudge[i];
        }
    }

    function submitProject(string memory _sourceCode, string memory _documentation) external duringSubmission {
        projects.push(Project({
            submitter: msg.sender,
            sourceCode: _sourceCode,
            documentation: _documentation
        }));
        emit ProjectSubmitted(projects.length - 1, msg.sender);
    }

    function vote(uint256 projectId, uint256 amount) external duringSubmission {
        if (!isJudge[msg.sender]) revert HackHub__NotJudge();
        if (judgeTokens[msg.sender] == 0) revert HackHub__NoTokensToVote();
        if (judgeTokens[msg.sender] < amount) revert HackHub__InsufficientTokens();
        if (projectId >= projects.length) revert HackHub__InvalidParams();

        judgeTokens[msg.sender] -= amount;
        projectTokens[projectId] += amount;
        emit Voted(msg.sender, projectId, amount);
    }

    function increasePrizePool() external payable onlyOwner {
        if (msg.value == 0) revert HackHub__InvalidParams();
        prizePool += msg.value;
        emit PrizeIncreased(prizePool, msg.value);
    }

    /// @notice Project owner can change token allocation for judges (only before submission deadline)
    function adjustJudgeTokens(address judge, uint256 newTokenAmount) external onlyOwner duringSubmission {
        if (!isJudge[judge]) revert HackHub__NotJudge();
        
        uint256 oldTokens = judgeTokens[judge];
        totalTokens = totalTokens - oldTokens + newTokenAmount;
        judgeTokens[judge] = newTokenAmount;        
        emit TokensAdjusted(judge, newTokenAmount);
    }

    function concludeHackathon() external onlyOwner afterEnd {
        if (concluded) revert HackHub__AlreadyConcluded();
        concluded = true;        
        IHackHubFactory(factory).hackathonConcluded(address(this));
        emit HackathonConcluded();
    }

    function claimPrize(uint256 projectId) external afterEnd {
        if (projectId >= projects.length) revert HackHub__InvalidParams();
        if (projects[projectId].submitter != msg.sender) revert HackHub__InvalidParams();
        if (prizeClaimed[projectId]) revert HackHub__AlreadyClaimed();
        if (totalTokens == 0) revert HackHub__NoVotesCast();

        prizeClaimed[projectId] = true;
        uint256 projectShare = (prizePool * projectTokens[projectId]) / totalTokens;
        payable(msg.sender).transfer(projectShare);
        emit prizeShareClaimed(projectId, msg.sender, projectShare);
    }

    function getProjectPrize(uint256 projectId) external view returns (uint256) {
        if (projectId >= projects.length) return 0;
        if (totalTokens == 0) return 0;
        return (prizePool * projectTokens[projectId]) / totalTokens;
    }


    function getProjectTokens(uint256 projectId) external view returns (uint256) {
        if (projectId >= projects.length) return 0;
        return projectTokens[projectId];
    }

    function getJudgeRemainingTokens(address judge) external view returns (uint256) { return judgeTokens[judge]; }
    function projectCount() external view returns (uint) { return projects.length; }
    function judgeCount() external view returns (uint) { return judges.length; }
}