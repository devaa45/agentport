// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IAgentID {
    function balanceOf(address owner) external view returns (uint256);
}

/// @title AgentPort — the daily port of call for Agent ID holders
/// @notice If you hold an Agent ID, you can check in here once a day (UTC).
/// Checking in builds a streak. At 1, 3, 7 and 14 total check-ins you can
/// claim a Port Stamp: a small non-transferable token that stays with your
/// wallet, the same way your Agent ID does.
///
/// There is no owner and there are no admin keys. The contract holds no
/// funds, takes no fees, asks for no approvals, and cannot move anything
/// out of anyone's wallet. The only thing it ever writes down is who
/// showed up, and when.
contract AgentPort {
    string public constant name = "AgentPort Stamp";
    string public constant symbol = "PSTAMP";
    uint8 public constant TIERS = 4;

    /// The Agent ID contract on BNB Chain (SPACE ID Agent ID, symbol AI).
    IAgentID public immutable agentID;

    uint256 public totalAgents; // Agent ID addresses that have ever checked in
    uint256 public totalCheckIns; // every check-in ever recorded
    uint256 public totalStamps; // stamps minted so far; also the last token id

    struct Stats {
        uint64 lastDay; // last check-in day (unix days)
        uint64 streak; // current run of consecutive days
        uint64 bestStreak; // longest run so far
        uint64 checkIns; // total check-ins by this address
    }

    mapping(address => Stats) public statsOf;
    mapping(uint256 => uint256) public checkInsOnDay; // day => check-ins that day

    // Port Stamps (ERC-721, non-transferable)
    mapping(uint256 => address) private _ownerOf;
    mapping(uint256 => uint8) public stampTier; // token id => tier 1..4
    mapping(address => uint256) private _stampBalance;
    mapping(address => mapping(uint8 => bool)) public stampClaimed;

    event CheckedIn(address indexed agent, uint256 day, uint256 streak, uint256 totalCheckIns);
    event StampClaimed(address indexed agent, uint256 indexed tokenId, uint8 tier);
    event Transfer(address indexed from, address indexed to, uint256 indexed tokenId);

    constructor(address agentID_) {
        require(agentID_ != address(0), "no Agent ID contract");
        agentID = IAgentID(agentID_);
    }

    // ----- the port itself -----

    function today() public view returns (uint256) {
        return block.timestamp / 86400;
    }

    function hasAgentID(address who) public view returns (bool) {
        return agentID.balanceOf(who) > 0;
    }

    function checkedInToday(address who) public view returns (bool) {
        Stats memory s = statsOf[who];
        return s.checkIns > 0 && s.lastDay == today();
    }

    function checkIn() external {
        require(hasAgentID(msg.sender), "Agent ID required");
        uint256 day = today();
        Stats storage s = statsOf[msg.sender];
        require(s.lastDay != day, "already checked in today");
        if (s.checkIns == 0) totalAgents += 1;
        s.streak = (s.checkIns > 0 && s.lastDay == day - 1) ? s.streak + 1 : 1;
        if (s.streak > s.bestStreak) s.bestStreak = s.streak;
        s.lastDay = uint64(day);
        s.checkIns += 1;
        totalCheckIns += 1;
        checkInsOnDay[day] += 1;
        emit CheckedIn(msg.sender, day, s.streak, s.checkIns);
    }

    // ----- stamps -----

    /// Total check-ins needed for a tier: 1, 3, 7, 14.
    function threshold(uint8 tier) public pure returns (uint256) {
        if (tier == 1) return 1;
        if (tier == 2) return 3;
        if (tier == 3) return 7;
        if (tier == 4) return 14;
        revert("bad tier");
    }

    function tierName(uint8 tier) public pure returns (string memory) {
        if (tier == 1) return "First Landing";
        if (tier == 2) return "Regular";
        if (tier == 3) return "Voyager";
        if (tier == 4) return "Harbor Master";
        revert("bad tier");
    }

    function claimStamp(uint8 tier) external {
        require(tier >= 1 && tier <= TIERS, "bad tier");
        require(hasAgentID(msg.sender), "Agent ID required");
        require(statsOf[msg.sender].checkIns >= threshold(tier), "not enough check-ins yet");
        require(!stampClaimed[msg.sender][tier], "stamp already claimed");
        stampClaimed[msg.sender][tier] = true;
        uint256 tokenId = ++totalStamps;
        _ownerOf[tokenId] = msg.sender;
        stampTier[tokenId] = tier;
        _stampBalance[msg.sender] += 1;
        emit Transfer(address(0), msg.sender, tokenId);
        emit StampClaimed(msg.sender, tokenId, tier);
    }

    // ----- one-call view for the website -----

    /// Everything the front page needs about one address, in one call.
    /// claimableMask / claimedMask: bit (tier-1) set means that tier.
    function viewOf(address who)
        external
        view
        returns (
            bool hasID,
            uint64 checkIns,
            uint64 streak,
            uint64 bestStreak,
            bool inToday,
            uint8 claimableMask,
            uint8 claimedMask
        )
    {
        Stats memory s = statsOf[who];
        hasID = hasAgentID(who);
        checkIns = s.checkIns;
        streak = s.streak;
        bestStreak = s.bestStreak;
        inToday = s.checkIns > 0 && s.lastDay == today();
        for (uint8 t = 1; t <= TIERS; t++) {
            if (stampClaimed[who][t]) {
                claimedMask |= uint8(1) << (t - 1);
            } else if (s.checkIns >= threshold(t)) {
                claimableMask |= uint8(1) << (t - 1);
            }
        }
    }

    // ----- ERC-721 (read side; stamps never move) -----

    function balanceOf(address who) external view returns (uint256) {
        require(who != address(0), "zero address");
        return _stampBalance[who];
    }

    function ownerOf(uint256 tokenId) public view returns (address) {
        address owner = _ownerOf[tokenId];
        require(owner != address(0), "no such stamp");
        return owner;
    }

    function supportsInterface(bytes4 id) external pure returns (bool) {
        return id == 0x01ffc9a7 // ERC-165
            || id == 0x80ac58cd // ERC-721
            || id == 0x5b5e139f; // ERC-721 metadata
    }

    function tokenURI(uint256 tokenId) external view returns (string memory) {
        ownerOf(tokenId);
        uint8 tier = stampTier[tokenId];
        string memory svg = _svg(tokenId, tier);
        string memory json = string(
            abi.encodePacked(
                '{"name":"AgentPort Stamp #',
                _utoa(tokenId),
                " - ",
                tierName(tier),
                '","description":"A Port Stamp from AgentPort, the daily port of call for Agent ID holders on BNB Chain. Stamps are non-transferable: they stay with the wallet that earned them.",',
                '"attributes":[{"trait_type":"Tier","value":"',
                tierName(tier),
                '"},{"trait_type":"Check-ins needed","value":"',
                _utoa(threshold(tier)),
                '"}],"image":"data:image/svg+xml;base64,',
                _b64(bytes(svg)),
                '"}'
            )
        );
        return string(abi.encodePacked("data:application/json;base64,", _b64(bytes(json))));
    }

    // Stamps are earned, not traded. Every transfer path stops here.
    function transferFrom(address, address, uint256) external pure {
        revert("stamps are non-transferable");
    }

    function safeTransferFrom(address, address, uint256) external pure {
        revert("stamps are non-transferable");
    }

    function safeTransferFrom(address, address, uint256, bytes calldata) external pure {
        revert("stamps are non-transferable");
    }

    function approve(address, uint256) external pure {
        revert("stamps are non-transferable");
    }

    function setApprovalForAll(address, bool) external pure {
        revert("stamps are non-transferable");
    }

    function getApproved(uint256 tokenId) external view returns (address) {
        ownerOf(tokenId);
        return address(0);
    }

    function isApprovedForAll(address, address) external pure returns (bool) {
        return false;
    }

    // ----- small helpers -----

    function _svg(uint256 tokenId, uint8 tier) internal pure returns (string memory) {
        string memory color = tier == 1
            ? "#8fb8dd"
            : tier == 2
                ? "#6fd3a7"
                : tier == 3
                    ? "#f5c86b"
                    : "#ff9d5c";
        return string(
            abi.encodePacked(
                '<svg xmlns="http://www.w3.org/2000/svg" width="600" height="600" viewBox="0 0 600 600">',
                '<rect width="600" height="600" fill="#0b1220"/>',
                '<circle cx="300" cy="270" r="170" fill="none" stroke="',
                color,
                '" stroke-width="6"/>',
                '<circle cx="300" cy="270" r="150" fill="none" stroke="',
                color,
                '" stroke-width="1.5" opacity="0.6"/>',
                '<text x="300" y="245" font-family="Georgia,serif" font-size="44" fill="',
                color,
                '" text-anchor="middle">',
                tierName(tier),
                "</text>",
                '<text x="300" y="300" font-family="Georgia,serif" font-size="26" fill="#e8eef6" text-anchor="middle">Port Stamp #',
                _utoa(tokenId),
                "</text>",
                '<text x="300" y="340" font-family="Georgia,serif" font-size="19" fill="#9db4c8" text-anchor="middle">',
                _utoa(threshold(tier)),
                " check-ins</text>",
                '<text x="300" y="520" font-family="Georgia,serif" font-size="24" letter-spacing="6" fill="#e8eef6" text-anchor="middle">AGENTPORT</text>',
                "</svg>"
            )
        );
    }

    function _utoa(uint256 v) internal pure returns (string memory) {
        if (v == 0) return "0";
        uint256 n = v;
        uint256 len;
        while (n > 0) {
            len++;
            n /= 10;
        }
        bytes memory out = new bytes(len);
        while (v > 0) {
            out[--len] = bytes1(uint8(48 + (v % 10)));
            v /= 10;
        }
        return string(out);
    }

    function _b64(bytes memory data) internal pure returns (string memory) {
        bytes memory table = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
        uint256 len = data.length;
        if (len == 0) return "";
        uint256 outLen = ((len + 2) / 3) * 4;
        bytes memory out = new bytes(outLen);
        uint256 i;
        uint256 j;
        while (i < len) {
            uint256 a = i < len ? uint8(data[i]) : 0;
            uint256 b = i + 1 < len ? uint8(data[i + 1]) : 0;
            uint256 c = i + 2 < len ? uint8(data[i + 2]) : 0;
            uint256 triple = (a << 16) | (b << 8) | c;
            out[j++] = table[(triple >> 18) & 63];
            out[j++] = table[(triple >> 12) & 63];
            out[j++] = i + 1 < len ? table[(triple >> 6) & 63] : bytes1("=");
            out[j++] = i + 2 < len ? table[triple & 63] : bytes1("=");
            i += 3;
        }
        return string(out);
    }
}
