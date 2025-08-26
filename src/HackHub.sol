// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Ownable, IERC20Minimal, IHackHubFactory} from "./Interfaces.sol";
import {SponsorshipLib} from "./SponsorshipLib.sol";

using SponsorshipLib for SponsorshipLib.SponsorshipStorage;

error InvalidParams();
error NotJudge();
error SubmissionClosed();
error NoVotesCast();
error BeforeEndTime();
error AlreadyClaimed();
error InsufficientTokens();
error AlreadyConcluded();
error AlreadySubmitted();
error TokenTransferFailed();

contract Hackathon is Ownable {
    
    struct Project {
        address submitter;
        address recipient;
        string name;
        string sourceCode;
        string docs;
    }

    string public name;            // name of the Hackathon
    uint256 public startTime;      // Start time of Hackathon
    uint256 public endTime;        // End time of Hackathon
    string public startDate;       
    string public endDate;         
    string public imageURL;        // URL hash to an image or banner
    uint256 public totalTokens;    // Total number of reward tokens involved
    address public factory;        // Factory instance
    bool public concluded;         // Flag indicating the hackathon has been concluded
    
    Project[] public projects;
    address[] public participants;
    address[] private judgeAddresses;

    mapping(address => bool) public isJudge;
    mapping(address => uint256) public judgeTokens;
    mapping(address => uint256) public remainingJudgeTokens;
    mapping(uint256 => uint256) public projectTokens;
    mapping(uint256 => bool) public prizeClaimed;
    mapping(address => mapping(uint256 => uint256)) public judgeVotes;
    mapping(address => uint256) public participantProjectId;
    mapping(address => bool) public hasSubmitted;
    
    SponsorshipLib.SponsorshipStorage private sponsorshipStorage;         // Prize pool managed through SponsorshipLib

    // event ProjectSubmitted(uint256 indexed id, address indexed submitter);
    // event Voted(address indexed judge, uint256 indexed projectId, uint256 amount);
    // event PrizeClaimed(uint256 indexed projectId, uint256 amount);

    modifier duringSubmission() {
        if (block.timestamp < startTime || block.timestamp > endTime) revert SubmissionClosed();
        _;
    }
    
    modifier duringEvaluation() {
        if (block.timestamp <= endTime || concluded) revert SubmissionClosed();
        _;
    }
    
    modifier afterConcluded() {
        if (!concluded) revert BeforeEndTime();
        _;
    }
    
    constructor(string memory _name,uint256 _startTime,uint256 _endTime,string memory _startDate, string memory _endDate,
        address[] memory _judges,uint256[] memory _tokens,string memory _imageURL) payable Ownable(tx.origin) {
        
        if (_startTime >= _endTime || _judges.length != _tokens.length) revert InvalidParams();
        name = _name;startTime = _startTime; endTime = _endTime; startDate = _startDate; endDate = _endDate; imageURL = _imageURL; factory = msg.sender;
        
        sponsorshipStorage.submitToken(address(0), "Native");
        sponsorshipStorage.whitelistToken(address(0), 1);
        
        uint256 judgesLength = _judges.length;
        for (uint256 i; i < judgesLength;) {
            address j = _judges[i];
            if (isJudge[j]) revert InvalidParams();
            uint256 t = _tokens[i];
            isJudge[j] = true;
            totalTokens += t;
            judgeTokens[j] = t;
            remainingJudgeTokens[j] = t;
            judgeAddresses.push(j);
            unchecked { ++i; }
        }
    }

    function submitProject( string calldata _name, string calldata _sourceCode, string calldata _docs, address _recipient) external duringSubmission {
        if(hasSubmitted[msg.sender]) revert AlreadySubmitted();
        address recipient = _recipient == address(0) ? msg.sender : _recipient;

        uint256 id = projects.length;
        projects.push(Project(msg.sender, recipient, _name, _sourceCode, _docs));
        hasSubmitted[msg.sender] = true;
        participantProjectId[msg.sender] = id;
        participants.push(msg.sender);
        IHackHubFactory(factory).registerParticipant(msg.sender);
        // emit ProjectSubmitted(id, msg.sender);
    }

    function vote(uint256 projectId, uint256 amount) external duringEvaluation {
        if (!isJudge[msg.sender] || projectId >= projects.length) revert InvalidParams();
        
        uint256 currentVote = judgeVotes[msg.sender][projectId];
        uint256 available = remainingJudgeTokens[msg.sender] + currentVote;
        if (available < amount) revert InsufficientTokens();
        
        remainingJudgeTokens[msg.sender] = available - amount;
        projectTokens[projectId] = projectTokens[projectId] - currentVote + amount;
        judgeVotes[msg.sender][projectId] = amount;
        // emit Voted(msg.sender, projectId, amount);
    }

    function concludeHackathon() external duringEvaluation onlyOwner {
        if (concluded) revert AlreadyConcluded();
        concluded = true;
        IHackHubFactory(factory).hackathonConcluded(address(this));
    }

    function claimPrize(uint256 projectId) external afterConcluded {
        if (projectId >= projects.length || projects[projectId].submitter != msg.sender || prizeClaimed[projectId]) revert InvalidParams();

        prizeClaimed[projectId] = true;
        address recipient = projects[projectId].recipient;
        uint256 projectShare = projectTokens[projectId];

        sponsorshipStorage.distributePrizes(recipient, projectShare, totalTokens);        
        // emit PrizeClaimed(projectId, projectShare);
    }

    function adjustJudgeTokens(address judge, uint256 amount) external onlyOwner duringSubmission {
        uint256 oldAmount = judgeTokens[judge];
        
        judgeTokens[judge] = amount;
        remainingJudgeTokens[judge] = amount;
        if (amount > oldAmount) totalTokens += (amount - oldAmount);
        else if (oldAmount > amount) totalTokens -= (oldAmount - amount);
    }

    function submitToken(address token, string calldata tokenName) external { sponsorshipStorage.submitToken(token, tokenName); }
    function whitelistToken(address token, uint256 minAmount) external onlyOwner { sponsorshipStorage.whitelistToken(token, minAmount); }

    function depositToToken(address token, uint256 amount, string calldata sponsorName, string calldata sponsorImageURL) external payable {
        if (concluded) revert AlreadyConcluded();
        sponsorshipStorage.depositToToken(token, amount, sponsorName, sponsorImageURL);
    }

    function projectCount() external view returns (uint256) { return projects.length; }
    function judgeCount() external view returns (uint256) { return judgeAddresses.length; }
    
    function getAllJudges() external view returns (address[] memory) { return judgeAddresses; }
    function getParticipants() external view returns (address[] memory) { return participants; }
    
    function getTokenTotal(address token) external view returns (uint256) { return sponsorshipStorage.getTokenTotal(token); }
    function getTokenMinAmount(address token) external view returns (uint256) { return sponsorshipStorage.getTokenMinAmount(token);  }
    function getApprovedTokensList() external view returns (address[] memory) { return sponsorshipStorage.getApprovedTokensList(); }

    function getSponsorProfile(address sponsor) external view returns (string memory sponsorName, string memory sponsorImageURL) {return sponsorshipStorage.getSponsorProfile(sponsor); }
    function getSponsorTokenAmount(address sponsor, address token) external view returns (uint256) { return sponsorshipStorage.getSponsorTokenAmount(sponsor, token); }
    function getAllSponsors() external view returns (address[] memory) { return sponsorshipStorage.getAllSponsors(); }

    function getSubmittedTokensList() external view returns (address[] memory) { return sponsorshipStorage.getSubmittedTokensList(); }
    function getTokenSubmission(address token) external view returns (string memory tokenName, address submitter, bool exists) { return sponsorshipStorage.getTokenSubmission(token);}
}