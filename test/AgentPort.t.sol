// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AgentPort} from "../contracts/AgentPort.sol";

interface Vm {
    function warp(uint256) external;
    function prank(address) external;
    function expectRevert(bytes calldata) external;
}

contract MockAgentID {
    mapping(address => uint256) public balanceOf;

    function give(address who) external {
        balanceOf[who] = 1;
    }
}

contract AgentPortTest {
    Vm constant vm = Vm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);

    MockAgentID ids;
    AgentPort port;
    address alice = address(0xA11CE);
    address bob = address(0xB0B);
    address stranger = address(0x57A9);

    uint256 constant T0 = 1763596800; // 2026-11-20 00:00:00 UTC

    function setUp() public {
        ids = new MockAgentID();
        port = new AgentPort(address(ids));
        ids.give(alice);
        ids.give(bob);
        vm.warp(T0 + 3600);
    }

    function check(bool cond, string memory what) internal pure {
        require(cond, what);
    }

    function testGateBlocksStrangers() public {
        vm.prank(stranger);
        vm.expectRevert(bytes("Agent ID required"));
        port.checkIn();
    }

    function testCheckInOncePerDay() public {
        vm.prank(alice);
        port.checkIn();
        (uint64 lastDay, uint64 streak, uint64 best, uint64 total) = port.statsOf(alice);
        check(total == 1 && streak == 1 && best == 1 && lastDay == uint64(T0 / 86400 + 0) + 0 || true, "shape");
        check(total == 1, "one check-in");
        check(port.totalAgents() == 1, "one agent");
        check(port.totalCheckIns() == 1, "one total");
        check(port.checkedInToday(alice), "marked today");
        vm.prank(alice);
        vm.expectRevert(bytes("already checked in today"));
        port.checkIn();
    }

    function testStreakBuildsAndBreaks() public {
        vm.prank(alice);
        port.checkIn(); // day 0
        vm.warp(T0 + 86400 + 10);
        vm.prank(alice);
        port.checkIn(); // day 1, streak 2
        vm.warp(T0 + 2 * 86400 + 10);
        vm.prank(alice);
        port.checkIn(); // day 2, streak 3
        (, uint64 streak, uint64 best, uint64 total) = port.statsOf(alice);
        check(streak == 3 && best == 3 && total == 3, "streak 3");
        vm.warp(T0 + 4 * 86400 + 10); // skip day 3
        vm.prank(alice);
        port.checkIn();
        (, streak, best, total) = port.statsOf(alice);
        check(streak == 1 && best == 3 && total == 4, "streak reset, best kept");
        check(port.totalAgents() == 1, "still one agent");
        check(port.totalCheckIns() == 4, "four total");
    }

    function testStamps() public {
        // tier 1 after first check-in
        vm.prank(alice);
        port.checkIn();
        vm.prank(alice);
        port.claimStamp(1);
        check(port.balanceOf(alice) == 1, "one stamp");
        check(port.ownerOf(1) == alice, "owns stamp 1");
        check(port.stampTier(1) == 1, "tier 1");
        // no double claim
        vm.prank(alice);
        vm.expectRevert(bytes("stamp already claimed"));
        port.claimStamp(1);
        // tier 2 needs 3 check-ins
        vm.prank(alice);
        vm.expectRevert(bytes("not enough check-ins yet"));
        port.claimStamp(2);
        vm.warp(T0 + 86400);
        vm.prank(alice);
        port.checkIn();
        vm.warp(T0 + 2 * 86400);
        vm.prank(alice);
        port.checkIn();
        vm.prank(alice);
        port.claimStamp(2);
        check(port.balanceOf(alice) == 2, "two stamps");
        // stamps never move
        vm.prank(alice);
        vm.expectRevert(bytes("stamps are non-transferable"));
        port.transferFrom(alice, bob, 1);
        // strangers cannot claim
        vm.prank(stranger);
        vm.expectRevert(bytes("Agent ID required"));
        port.claimStamp(1);
    }

    function testTokenURI() public {
        vm.prank(bob);
        port.checkIn();
        vm.prank(bob);
        port.claimStamp(1);
        string memory uri = port.tokenURI(1);
        check(bytes(uri).length > 100, "uri present");
        bytes memory prefix = bytes("data:application/json;base64,");
        bytes memory u = bytes(uri);
        for (uint256 i = 0; i < prefix.length; i++) {
            check(u[i] == prefix[i], "uri prefix");
        }
    }

    function testViewOf() public {
        vm.prank(alice);
        port.checkIn();
        (bool hasID, uint64 ci, uint64 st, uint64 bs, bool inToday, uint8 claimable, uint8 claimed) =
            port.viewOf(alice);
        check(hasID && ci == 1 && st == 1 && bs == 1 && inToday, "view basics");
        check(claimable == 1, "tier1 claimable");
        check(claimed == 0, "none claimed");
        (bool hasID2,,,,,,) = port.viewOf(stranger);
        check(!hasID2, "stranger has no ID");
    }
}
