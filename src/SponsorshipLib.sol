// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20Minimal} from "./Interfaces.sol";

library SponsorshipLib {
    
    struct SponsorProfile { 
        string name; 
        string image; 
    }

    struct TokenSubmission {
        string name;
        address submitter;
        bool exists;
    }

    struct SponsorshipStorage {
        mapping(address => mapping(address => uint256)) sponsorTokenAmounts; // sponsor => token => amount
        mapping(address => uint256) approvedTokensAmount;                    // token => total approved amount
        mapping(address => uint256) tokenMinAmount;                          // token => minimum amount per deposit
        mapping(address => SponsorProfile) sponsorProfiles;                  // sponsor => profile
        mapping(address => TokenSubmission) tokenSubmissions;                // token => submission details
        address[] approvedTokenList;                                         // tokens with non-zero approved amount
        address[] submittedTokenList;                                        // all submitted tokens
        address[] sponsors;                                                  // all unique sponsors
    }

    event TokenSubmitted(address indexed token, string name, address indexed submitter);
    event TokenApproved(address indexed token, uint256 minAmount);
    event SponsorDeposited(address indexed sponsor, address indexed token, uint256 amount);

    error TokenTransferFailed();
    error InvalidParams();
    error TokenNotApproved();
    error TokenAlreadySubmitted();

    
    function submitToken(SponsorshipStorage storage self, address token, string calldata tokenName) external {      // Anyone can submit a token for consideration
        if (token == address(0) && bytes(tokenName).length == 0) revert InvalidParams();
        if (self.tokenSubmissions[token].exists) revert TokenAlreadySubmitted();
        
        self.tokenSubmissions[token] = TokenSubmission({name: tokenName, submitter: msg.sender, exists: true});
        self.submittedTokenList.push(token);
        emit TokenSubmitted(token, tokenName, msg.sender);
    }

    // Owner approves a submitted token with minimum amount
    function approveToken(SponsorshipStorage storage self, address token, uint256 minAmount) external {
        if (!self.tokenSubmissions[token].exists) revert InvalidParams();
        
        self.tokenMinAmount[token] = minAmount;
        if (self.approvedTokensAmount[token] == 0)  self.approvedTokenList.push(token);
        emit TokenApproved(token, minAmount);
    }

    function depositToToken( SponsorshipStorage storage self, address token, uint256 amount, string calldata sponsorName, string calldata sponsorImageURL) external { // Sponsors deposit to approved tokens
        if (self.tokenMinAmount[token] == 0) revert TokenNotApproved();
        if (amount == 0) revert InvalidParams();
        if (bytes(sponsorName).length == 0 || bytes(sponsorImageURL).length == 0) revert InvalidParams();
        
        _handleTokenTransfer(token, amount, true, address(0));
        
        if (amount >= self.tokenMinAmount[token]) {
            self.sponsorProfiles[msg.sender] = SponsorProfile({ name: sponsorName, image: sponsorImageURL });
            self.sponsorTokenAmounts[msg.sender][token] += amount;
            self.approvedTokensAmount[token] += amount;
            emit SponsorDeposited(msg.sender, token, amount);
        } 
    }

    function _handleTokenTransfer(address token, uint256 amount, bool isDeposit, address recipient) internal {
        if (token == address(0)) {                        // Native currency
            if (isDeposit) {
                if (msg.value != amount) revert InvalidParams();
            } else {
                address target = recipient == address(0) ? msg.sender : recipient;
                (bool success,) = payable(target).call{value: amount}("");
                if (!success) revert TokenTransferFailed();
            }
        } else {                                        // ERC20 token
            if (isDeposit) {
                if (msg.value != 0) revert InvalidParams();
                if (!IERC20Minimal(token).transferFrom(msg.sender, address(this), amount)) {
                    revert TokenTransferFailed();
                }
            } else {
                address target = recipient == address(0) ? msg.sender : recipient;
                if (!IERC20Minimal(token).transfer(target, amount)) {
                    revert TokenTransferFailed();
                }
            }
        }
    }

    function getTokenTotal(SponsorshipStorage storage self, address token) external view returns (uint256) { return self.approvedTokensAmount[token]; }
    function getSponsorTokenAmount(SponsorshipStorage storage self, address sponsor, address token) external view returns (uint256) { return self.sponsorTokenAmounts[sponsor][token]; }
    function getTokenMinAmount(SponsorshipStorage storage self, address token) external view returns (uint256) { return self.tokenMinAmount[token]; }
    
    function getAllSponsors(SponsorshipStorage storage self) external view returns (address[] memory) { return self.sponsors; }
    function getApprovedTokensList(SponsorshipStorage storage self) external view returns (address[] memory) { return self.approvedTokenList; }
    function isTokenApproved(SponsorshipStorage storage self, address token) external view returns (bool) { return self.tokenMinAmount[token] > 0; }

    function getSubmittedTokensList(SponsorshipStorage storage self) external view returns (address[] memory) { return self.submittedTokenList; }

    function getTokenSubmission(SponsorshipStorage storage self, address token) external view returns (string memory name, address submitter, bool exists) {
        TokenSubmission storage submission = self.tokenSubmissions[token];
        return (submission.name, submission.submitter, submission.exists);
    }

    function getSponsorProfile(SponsorshipStorage storage self, address sponsor) external view returns (string memory sponsorName, string memory imageURL) {
        SponsorProfile storage p = self.sponsorProfiles[sponsor];
        return (p.name, p.image);
    }

    function distributePrizes(SponsorshipStorage storage self, address recipient, uint256 projectShare, uint256 totalTokens) external {
        if (projectShare == 0 || totalTokens == 0) return;
        address[] memory tokens = self.approvedTokenList;
        uint256 len = tokens.length;
        for (uint256 i; i < len; i++) {
            address token = tokens[i];
            uint256 totalTokenAmount = self.approvedTokensAmount[token];
            if (totalTokenAmount == 0) continue;
            uint256 share = (totalTokenAmount * projectShare) / totalTokens;
            _handleTokenTransfer(token, share, false, recipient);
        }
    }
}
