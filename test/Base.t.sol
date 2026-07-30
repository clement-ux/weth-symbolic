// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.31;

import {Test} from "forge-std/Test.sol";
import {WETH} from "../src/WETH.sol";

contract ForceEther {
    function forceSend(address payable recipient) external {
        selfdestruct(recipient);
    }
}

contract RejectEther {
    error EtherRejected();

    receive() external payable {
        revert EtherRejected();
    }
}

abstract contract Base is Test {
    ////////////////////////////////////////////////////
    /// --- CONTRACTS & MOCKS
    ////////////////////////////////////////////////////
    WETH internal weth;

    ////////////////////////////////////////////////////
    /// --- USERS
    ////////////////////////////////////////////////////
    // Users
    address internal alice = makeAddr("alice");
    address internal bobby = makeAddr("bobby");
    address internal carol = makeAddr("carol");
    address[] internal users = [alice, bobby, carol];

    address internal deployer = makeAddr("deployer");

    ////////////////////////////////////////////////////
    /// --- SETUP
    ////////////////////////////////////////////////////
    function setUp() public virtual {
        weth = new WETH();
    }
}
