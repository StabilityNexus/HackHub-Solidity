// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Ownable, IERC20Minimal, IHackHubFactory} from "./Interfaces.sol";

error InvalidParams();
error NotJudge();
error SubmissionClosed();
error NoVotesCast();
error NotAfterEndTime();
error AlreadyClaimed();
error InsufficientTokens();
error AlreadyConcluded();
error AlreadySubmitted();
error TokenTransferFailed();

contract Hackathon is Ownable {
    struct Judge {
        address addr;
        uint256 tokens;
        string name;
    }
    
    struct Project {
        address submitter;
        address recipient;
        string sourceCode;
        string docs;
    }

    string public name;
    uint256 public startTime;
    uint256 public endTime;
    string public startDate;
    string public endDate;
    uint256 public prizePool;
    uint256 public totalTokens;
    address public prizeToken;
    address public factory;
    bool public concluded;
    bool public isERC20Prize;

    Judge[] public judges;
    Project[] public projects;
    address[] public participants;

    mapping(address => bool) public isJudge;
    mapping(address => uint256) public judgeTokens;
    mapping(address => uint256) public remainingJudgeTokens;
    mapping(uint256 => uint256) public projectTokens;
    mapping(uint256 => bool) public prizeClaimed;
    mapping(address => mapping(uint256 => uint256)) public judgeVotes;
    mapping(address => uint256) public participantProjectId;
    mapping(address => bool) public hasSubmitted;

    event ProjectSubmitted(uint256 indexed id, address indexed submitter);
    event Voted(address indexed judge, uint256 indexed projectId, uint256 amount);
    event PrizeClaimed(uint256 indexed projectId, uint256 amount);
    event PrizePoolAdjusted(uint256 newAmount);

    modifier duringSubmission() {
        if (block.timestamp < startTime || block.timestamp > endTime) revert SubmissionClosed();
        _;
    }
    
    modifier duringEvaluation() {
        if (block.timestamp <= endTime || concluded) revert SubmissionClosed();
        _;
    }
    
    modifier afterConcluded() {
        if (!concluded) revert NotAfterEndTime();
        _;
    }
    
    constructor(
        string memory _name,
        uint256 _startTime,
        uint256 _endTime,
        string memory _startDate,
        string memory _endDate,
        address[] memory _judges,
        uint256[] memory _tokens,
        string[] memory _judgeNames,
        address _prizeToken,
        uint256 _prizeAmount
    ) payable Ownable(tx.origin) {
        if (_startTime >= _endTime || _judges.length != _tokens.length || _judges.length != _judgeNames.length) revert InvalidParams();

        name = _name;
        startTime = _startTime;
        endTime = _endTime;
        startDate = _startDate;
        endDate = _endDate;
        factory = msg.sender;

        if (_prizeToken == address(0)) {
            if (msg.value == 0) revert InvalidParams();
            prizePool = msg.value;
        } else {
            if (_prizeAmount == 0) revert InvalidParams();
            prizePool = _prizeAmount;
            prizeToken = _prizeToken;
            isERC20Prize = true;
        }

        uint256 judgesLength = _judges.length;
        for (uint256 i; i < judgesLength;) {
            address j = _judges[i];
            uint256 t = _tokens[i];
            isJudge[j] = true;
            totalTokens += t;
            judgeTokens[j] = t;
            remainingJudgeTokens[j] = t;
            judges.push(Judge(j, t, _judgeNames[i]));
            unchecked { ++i; }
        }
    }

    function submitProject(string calldata _sourceCode, string calldata _docs, address _recipient) 
        external duringSubmission {
        if (hasSubmitted[msg.sender]) revert AlreadySubmitted();
        
        uint256 id = projects.length;
        address recipient = _recipient == address(0) ? msg.sender : _recipient;
        
        projects.push(Project(msg.sender, recipient, _sourceCode, _docs));
        hasSubmitted[msg.sender] = true;
        participantProjectId[msg.sender] = id;
        participants.push(msg.sender);
        IHackHubFactory(factory).registerParticipant(msg.sender);
        emit ProjectSubmitted(id, msg.sender);
    }

    function vote(uint256 projectId, uint256 amount) external duringEvaluation {
        if (!isJudge[msg.sender] || projectId >= projects.length) revert InvalidParams();
        
        uint256 currentVote = judgeVotes[msg.sender][projectId];
        uint256 available = remainingJudgeTokens[msg.sender] + currentVote;
        if (available < amount) revert InsufficientTokens();
        
        remainingJudgeTokens[msg.sender] = available - amount;
        projectTokens[projectId] = projectTokens[projectId] - currentVote + amount;
        judgeVotes[msg.sender][projectId] = amount;
        emit Voted(msg.sender, projectId, amount);
    }

    function concludeHackathon() external duringEvaluation onlyOwner {
        if (concluded) revert AlreadyConcluded();
        concluded = true;
        IHackHubFactory(factory).hackathonConcluded(address(this));
    }

    function claimPrize(uint256 projectId) external afterConcluded {
        if (projectId >= projects.length || projects[projectId].submitter != msg.sender || 
            prizeClaimed[projectId] || totalTokens == 0) revert InvalidParams();

        prizeClaimed[projectId] = true;
        uint256 share = (prizePool * projectTokens[projectId]) / totalTokens;
        address recipient = projects[projectId].recipient;
        
        if (isERC20Prize) {
            if (!IERC20Minimal(prizeToken).transfer(recipient, share)) revert TokenTransferFailed();
        } else {
            (bool success,) = payable(recipient).call{value: share}("");
            if (!success) revert TokenTransferFailed();
        }
        emit PrizeClaimed(projectId, share);
    }

    function adjustJudgeTokens(address judge, uint256 amount) external onlyOwner duringSubmission {
        if (!isJudge[judge]) revert InvalidParams();
        
        uint256 oldAmount = judgeTokens[judge];
        judgeTokens[judge] = amount;
        if (amount > oldAmount) totalTokens += (amount - oldAmount);
        else totalTokens -= (oldAmount - amount);

        remainingJudgeTokens[judge] = amount;
        uint256 judgesCount = judges.length;
        for (uint256 i = 0; i < judgesCount; ++i) {
            if (judges[i].addr == judge) {
                judges[i].tokens = amount;
                break;
            }
        }
    }

    function adjustPrizePool(uint256 newAmount) external payable onlyOwner {
        if (newAmount <= prizePool) revert InvalidParams();
        if (concluded) revert AlreadyConcluded();
        
        if (isERC20Prize) {
            prizePool = newAmount;
        } else {
            uint256 difference = newAmount - prizePool;
            if (msg.value < difference) revert InvalidParams();
            prizePool = newAmount;
        }
        
        emit PrizePoolAdjusted(newAmount);
    }

    function getProjectPrize(uint256 projectId) external view returns (uint256) {
        if (projectId >= projects.length || totalTokens == 0) return 0;
        return (prizePool * projectTokens[projectId]) / totalTokens;
    }

    function projectCount() external view returns (uint256) { return projects.length; }
    function judgeCount() external view returns (uint256) { return judges.length; }
    
    function getJudges(uint256 start, uint256 end) external view returns (address[] memory) {
        if (start > end || end >= judges.length) revert InvalidParams();
        uint256 length = end - start + 1;
        address[] memory result = new address[](length);
        for (uint256 i; i < length;) {
            result[i] = judges[start + i].addr;
            unchecked { ++i; }
        }
        return result;
    }
    
    function getJudgeNames(uint256 start, uint256 end) external view returns (string[] memory) {
        if (start > end || end >= judges.length) revert InvalidParams();
        uint256 length = end - start + 1;
        string[] memory result = new string[](length);
        for (uint256 i; i < length;) {
            result[i] = judges[start + i].name;
            unchecked { ++i; }
        }
        return result;
    }

    function participantCount() external view returns (uint256) { return participants.length; }
    function getParticipants() external view returns (address[] memory) { return participants; }
}