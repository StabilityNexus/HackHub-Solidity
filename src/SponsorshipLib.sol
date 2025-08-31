// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20Minimal} from "./Interfaces.sol";

library SponsorshipLib {
    
    struct SponsorProfile { 
        string name; 
        string image; 
    }

    struct SponsorshipStorage {
        mapping(address => mapping(address => uint256)) sponsorTokenAmounts; // sponsor => token => amount
        mapping(address => uint256) tokenAmounts;                            // token => total deposited amount
        mapping(address => SponsorProfile) sponsorProfiles;                  // sponsor => profile
        address[] depositedTokens;                                           // tokens that have been deposited
        address[] sponsors;                                                  // all unique sponsors
        mapping(address => bool) isSponsor;                                  // tracks if address is already a sponsor
        mapping(address => bool) tokenExists;                                // tracks if token has been deposited before
        mapping(address => bool) blockedSponsors;                            // tracks blocked/hidden sponsors
    }

    event SponsorDeposited(address indexed sponsor, address indexed token, uint256 amount);
    event SponsorBlocked(address indexed sponsor);

    error TokenTransferFailed();
    error InvalidParams();
    error SponsorNotFound();

    function depositToToken( SponsorshipStorage storage self, address token, uint256 amount, string calldata sponsorName, string calldata sponsorImageURL) external { // Sponsors can deposit any token with any amount
        if (amount == 0) revert InvalidParams();
        if (bytes(sponsorName).length == 0 || bytes(sponsorImageURL).length == 0) revert InvalidParams();
        
        uint256 actualAmount = _handleTokenDeposit(token, amount);
        
        self.sponsorProfiles[msg.sender] = SponsorProfile({ name: sponsorName, image: sponsorImageURL });
        self.sponsorTokenAmounts[msg.sender][token] += actualAmount;
        self.tokenAmounts[token] += actualAmount;
        
        if (!self.tokenExists[token]) {               // Track new tokens
            self.tokenExists[token] = true;
            self.depositedTokens.push(token);
        }
        
        if (!self.isSponsor[msg.sender]) {              // Track new sponsors
            self.isSponsor[msg.sender] = true;
            self.sponsors.push(msg.sender);
        }
        emit SponsorDeposited(msg.sender, token, actualAmount);
    }

    function _handleTokenDeposit(address token, uint256 amount) internal returns (uint256 actualAmount) {
        if (token == address(0)) {                        // Native currency
            if (msg.value != amount) revert InvalidParams();
            return amount;
        } else {                                        // ERC20 token
            if (msg.value != 0) revert InvalidParams();
            if (!IERC20Minimal(token).transferFrom(msg.sender, address(this), amount)) revert TokenTransferFailed();
            return amount;
        }
    }

    function _handleTokenWithdrawal(address token, uint256 amount, address recipient) internal {
        if (token == address(0)) {                        // Native currency
            address target = recipient == address(0) ? msg.sender : recipient;
            (bool success,) = payable(target).call{value: amount}("");
            if (!success) revert TokenTransferFailed();
        } else {                                        // ERC20 token
            address target = recipient == address(0) ? msg.sender : recipient;
            if (!IERC20Minimal(token).transfer(target, amount)) {
                revert TokenTransferFailed();
            }
        }
    }

    function getTokenTotal(SponsorshipStorage storage self, address token) external view returns (uint256) { return self.tokenAmounts[token]; }
    function getSponsorTokenAmount(SponsorshipStorage storage self, address sponsor, address token) external view returns (uint256) { return self.sponsorTokenAmounts[sponsor][token]; }
    function getAllSponsors(SponsorshipStorage storage self) external view returns (address[] memory) { 
        uint256 totalSponsors = self.sponsors.length;
        uint256 visibleCount = 0;
        
        for (uint256 i = 0; i < totalSponsors; i++) {             // Count non-blocked sponsors
            if (!self.blockedSponsors[self.sponsors[i]]) {
                visibleCount++;
            }
        }
        address[] memory visibleSponsors = new address[](visibleCount);
        uint256 index = 0;
        for (uint256 i = 0; i < totalSponsors; i++) {             // Create array with only non-blocked sponsors
            if (!self.blockedSponsors[self.sponsors[i]]) {
                visibleSponsors[index] = self.sponsors[i];
                index++;
            }
        }
        return visibleSponsors;
    }
    function getDepositedTokensList(SponsorshipStorage storage self) external view returns (address[] memory) { return self.depositedTokens; }

    function getSponsorProfile(SponsorshipStorage storage self, address sponsor) external view returns (string memory sponsorName, string memory imageURL) {
        SponsorProfile storage p = self.sponsorProfiles[sponsor];
        return (p.name, p.image);
    }

    function distributePrizes(SponsorshipStorage storage self, address recipient, uint256 projectShare, uint256 totalTokens) external {
        if (projectShare == 0 || totalTokens == 0) return;
        address[] memory tokens = self.depositedTokens;
        uint256 len = tokens.length;
        for (uint256 i; i < len; i++) {
            address token = tokens[i];
            uint256 totalTokenAmount = self.tokenAmounts[token];
            if (totalTokenAmount == 0) continue;
            uint256 share = (totalTokenAmount * projectShare) / totalTokens;
            _handleTokenWithdrawal(token, share, recipient);
        }
    }

    function blockSponsor(SponsorshipStorage storage self, address sponsor) external {
        if (!self.isSponsor[sponsor]) revert SponsorNotFound();
        self.blockedSponsors[sponsor] = true;
        emit SponsorBlocked(sponsor);
    }
    function isSponsorBlocked(SponsorshipStorage storage self, address sponsor) external view returns (bool) {
        return self.blockedSponsors[sponsor];
    }
}
