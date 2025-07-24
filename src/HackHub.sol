// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

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

interface IHackHubFactory {
    function hackathonConcluded(address hackathon) external;
    function registerParticipant(address participant) external;
}

contract Hackathon is Ownable {
    struct Judge {
        address addr;
    }
    struct Project {
        address submitter;
        address prizeRecipient;
        string  sourceCode;
        string  documentation;
    }

    string  public hackathonName;
    uint256 public startTime;
    uint256 public submissionEndTime;
    uint256 public startDate;
    uint256 public submissionEndDate;
    uint256 public prizePool;
    uint256 public totalTokens;
    bool    public concluded;
    address public factory;
    
    address public prizeTokenAddress;
    bool    public isERC20Prize;

    Judge[] public judges;
    Project[] public projects;
    address[] public participants;

    mapping(address => bool) public isJudge;
    mapping(address => uint256) public judgeTokens;
    
    mapping(uint256 => uint256) public projectTokens;
    mapping(uint256 => bool) public prizeClaimed;
    mapping(address => mapping(uint256 => uint256)) public judgeVotes;

    mapping(address => uint256) public participantProjectId;
    mapping(address => bool) public hasSubmitted;

    event ProjectSubmitted(uint256 indexed projectId, address indexed submitter);
    event ProjectEdited(uint256 indexed projectId, address indexed submitter);
    event Voted(address indexed judge, uint256 indexed projectId, uint256 amount);
    event PrizeIncreased(uint256 newPrizePool, uint256 addedAmount);
    event TokensAdjusted(address indexed judge, uint256 newTokenAmount);
    event prizeShareClaimed(uint256 indexed projectId, address indexed submitter, uint256 amount);
    event HackathonConcluded();
    event ParticipantRegistered(address indexed participant);

    modifier duringSubmission() {
        if (block.timestamp < startTime || block.timestamp > submissionEndTime) {
            revert SubmissionClosed();
        }
        _;
    }
    modifier duringEvaluation() {
        if (block.timestamp <= submissionEndTime || concluded) {
            revert SubmissionClosed();
        }
        _;
    }
    modifier afterConcluded() {
        if (!concluded) {
            revert NotAfterEndTime();
        }
        _;
    }
    
    constructor(
        string   memory _name,
        uint256         _startDate,
        uint256         _startTime,
        uint256         _submissionEndDate,
        uint256         _submissionEndTime,
        address[]memory _judgeAddrs,
        uint256[]memory _tokenPerJudge,
        address         _prizeTokenAddress,        
        uint256         _prizeAmount             
    ) payable Ownable(tx.origin) {
        if (_startTime >= _submissionEndTime || _judgeAddrs.length != _tokenPerJudge.length) revert InvalidParams();

        if (_prizeTokenAddress == address(0)) {
            if (msg.value == 0) revert InvalidParams();
            prizePool = msg.value;
            isERC20Prize = false;
        } else {
            if (_prizeAmount == 0) revert InvalidParams();
            prizePool = _prizeAmount;
            prizeTokenAddress = _prizeTokenAddress;
            isERC20Prize = true;
            bool success = IERC20(_prizeTokenAddress).transferFrom(msg.sender, address(this), _prizeAmount);
            if (!success) revert TokenTransferFailed();
        }

        hackathonName = _name;
        startDate     = _startDate;
        startTime     = _startTime;
        submissionEndDate = _submissionEndDate;
        submissionEndTime = _submissionEndTime;
        factory       = msg.sender;

        for (uint i; i < _judgeAddrs.length; i++) {
            address j = _judgeAddrs[i];
            isJudge[j] = true;
            judgeTokens[j] = _tokenPerJudge[i];
            totalTokens += _tokenPerJudge[i];
            
            judges.push(Judge({
                addr: j
            }));
        }
    }

    function submitProject(string memory _sourceCode, string memory _documentation, address _prizeRecipient) external duringSubmission {
        if (hasSubmitted[msg.sender]) revert AlreadySubmitted();
        uint256 projectId = projects.length;
        address recipient = _prizeRecipient == address(0) ? msg.sender : _prizeRecipient;
        
        Project memory newProject = Project({
            submitter: msg.sender,
            prizeRecipient: recipient,
            sourceCode: _sourceCode,
            documentation: _documentation
        });
        participantProjectId[msg.sender] = projectId;
        projects.push(newProject);
        
        participants.push(msg.sender);
        hasSubmitted[msg.sender] = true;
        IHackHubFactory(factory).registerParticipant(msg.sender);
        emit ParticipantRegistered(msg.sender);
        emit ProjectSubmitted(projectId, msg.sender);
    }

    function editProject(string memory _sourceCode, string memory _documentation, address _prizeRecipient) external duringSubmission {
        if (!hasSubmitted[msg.sender]) revert InvalidParams();
        uint256 projectId = participantProjectId[msg.sender];
        address recipient = _prizeRecipient == address(0) ? msg.sender : _prizeRecipient;
        
        projects[projectId].sourceCode = _sourceCode;
        projects[projectId].documentation = _documentation;
        projects[projectId].prizeRecipient = recipient;
        emit ProjectEdited(projectId, msg.sender);
    }

    function vote(uint256 projectId, uint256 amount) external duringEvaluation {
        if (!isJudge[msg.sender]) revert NotJudge();
        if (projectId >= projects.length) revert InvalidParams();
        
        uint256 currentVote = judgeVotes[msg.sender][projectId];
        uint256 availableTokens = judgeTokens[msg.sender] + currentVote;
        if (availableTokens < amount) revert InsufficientTokens();
        
        judgeTokens[msg.sender] = availableTokens - amount;
        projectTokens[projectId] = projectTokens[projectId] - currentVote + amount;
        judgeVotes[msg.sender][projectId] = amount;
        emit Voted(msg.sender, projectId, amount);
    }

    function increasePrizePool(uint256 _amount) external payable onlyOwner {
        if (isERC20Prize) {
            if (_amount == 0) revert InvalidParams();
            bool success = IERC20(prizeTokenAddress).transferFrom(msg.sender, address(this), _amount);
            if (!success) revert TokenTransferFailed();
            prizePool += _amount;
            emit PrizeIncreased(prizePool, _amount);
        } else {
            if (msg.value == 0) revert InvalidParams();
            prizePool += msg.value;
            emit PrizeIncreased(prizePool, msg.value);
        }
    }

    function adjustJudgeTokens(address judge, uint256 newTokenAmount) external duringSubmission onlyOwner {
        if (!isJudge[judge]) revert NotJudge();
        if (concluded) revert AlreadyConcluded();
        
        uint256 oldTokens = judgeTokens[judge];
        totalTokens = totalTokens + newTokenAmount - oldTokens;
        judgeTokens[judge] = newTokenAmount;        
        emit TokensAdjusted(judge, newTokenAmount);
    }

    function concludeHackathon() external duringEvaluation onlyOwner {
        if (concluded) revert AlreadyConcluded();
        concluded = true;        
        IHackHubFactory(factory).hackathonConcluded(address(this));
        emit HackathonConcluded();
    }

    function claimPrize(uint256 projectId) external afterConcluded {
        if (projectId >= projects.length) revert InvalidParams();
        if (projects[projectId].submitter != msg.sender) revert InvalidParams();
        if (prizeClaimed[projectId]) revert AlreadyClaimed();
        if (totalTokens == 0) revert NoVotesCast();

        prizeClaimed[projectId] = true;
        uint256 projectShare = (prizePool * projectTokens[projectId]) / totalTokens;
        address recipient = projects[projectId].prizeRecipient;
        if (isERC20Prize) {
            bool success = IERC20(prizeTokenAddress).transfer(recipient, projectShare);
            if (!success) revert TokenTransferFailed();
        } else {
            (bool success, ) = payable(recipient).call{value: projectShare}("");
            require(success, "Transfer failed");
        }
        emit prizeShareClaimed(projectId, recipient, projectShare);
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

    function getPrizeInfo() external view returns (address tokenAddress, bool isERC20, uint256 totalPrize) {return (prizeTokenAddress, isERC20Prize, prizePool);}
    function projectCount() external view returns (uint) { return projects.length; }
    function judgeCount() external view returns (uint) { return judges.length; }
    function participantCount() external view returns (uint) { return participants.length; }
    
    function getParticipants(uint256 startIndex, uint256 endIndex) external view returns (address[] memory) {
        if (startIndex > endIndex || endIndex >= judges.length) revert InvalidParams();
        uint256 length = endIndex - startIndex + 1;
        address[] memory result = new address[](length);
        for (uint256 i = 0; i < length; i++) {
            result[i] = participants[startIndex + i];
        }
        return result;
    }
    
    function getJudges(uint256 startIndex, uint256 endIndex) external view returns (address[] memory) {
        if (startIndex > endIndex || endIndex >= judges.length) revert InvalidParams();
        uint256 length = endIndex - startIndex + 1;
        address[] memory result = new address[](length);
        for (uint256 i = 0; i < length; i++) {
            result[i] = judges[startIndex + i].addr;
        }
        return result;
    }
}