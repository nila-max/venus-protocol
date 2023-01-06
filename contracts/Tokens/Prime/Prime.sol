pragma solidity 0.8.17;

import "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import "./PrimeStorage.sol";

contract Prime is Ownable2StepUpgradeable, PrimeStorageV1 {

    /// @notice address of XVS vault
    address immutable internal xvsVault;

    event Mint (
        address owner,
        Token metadata
    );

    event Burn (
        address owner
    );

    constructor(
        address _xvsVault
    ) {
        xvsVault = _xvsVault;
    } 

    function initialize() external virtual initializer {
        __Ownable2Step_init();
    }

    function setLimit(
        uint256 irrevocableLimit,
        uint256 revocableLimit
    ) onlyOwner external {
        require(_totalRevocable >= _revocableLimit, "limit is lower than total minted tokens");
        require(_totalIrrevocable >= irrevocableLimit, "limit is lower than total minted tokens");

        _revocableLimit = revocableLimit;
        _irrevocableLimit = irrevocableLimit;
    }

    function setCaps(
        uint256[] memory thresholds,
        uint256[] memory stableCoinSupplyTVLCaps,
        uint256[] memory stableCoinBorrowTVLCaps,
        uint256[] memory nonStableCoinSupplyTVLCaps,
        uint256[] memory nonStableCoinBorrowTVLCaps        
    ) onlyOwner external {
        require(
            thresholds.length == uint(MAX_TIER) &&
            stableCoinSupplyTVLCaps.length == uint(MAX_TIER) &&
            stableCoinBorrowTVLCaps.length == uint(MAX_TIER) && 
            nonStableCoinSupplyTVLCaps.length == uint(MAX_TIER) &&
            nonStableCoinBorrowTVLCaps.length == uint(MAX_TIER), 
            "you need to set caps for all tiers"
        );

        uint256 threshold;
        uint256 stableCoinSupplyTVLCap;
        uint256 stableCoinBorrowTVLCap;
        uint256 nonStableCoinSupplyTVLCap;
        uint256 nonStableCoinBorrowTVLCap;

        for(uint i = 0; i < thresholds.length; i++) {
            require(
                thresholds[i] > threshold &&
                stableCoinSupplyTVLCaps[i] > stableCoinSupplyTVLCap &&
                stableCoinBorrowTVLCaps[i] > stableCoinBorrowTVLCap &&
                nonStableCoinSupplyTVLCaps[i] > nonStableCoinSupplyTVLCap &&
                nonStableCoinBorrowTVLCaps[i] > nonStableCoinBorrowTVLCap, 
                "higher tier should have higher cap"
            );

            threshold = thresholds[i];
            stableCoinSupplyTVLCap = stableCoinSupplyTVLCaps[i];
            stableCoinBorrowTVLCap = stableCoinBorrowTVLCaps[i];
            nonStableCoinSupplyTVLCap = nonStableCoinSupplyTVLCaps[i];
            nonStableCoinBorrowTVLCap = nonStableCoinBorrowTVLCaps[i];

            _tiers[Tier(i+1)] = Cap(
                thresholds[i],
                stableCoinSupplyTVLCaps[i],
                stableCoinBorrowTVLCaps[i],
                nonStableCoinSupplyTVLCaps[i],
                nonStableCoinBorrowTVLCaps[i]
            );
        }
    }

    function issue(
        bool isIrrevocable,
        address[] memory owners,
        Tier[] memory tiers
    ) onlyOwner external {
        if (isIrrevocable == true) {
            for (uint i = 0; i < owners.length; i++) {
                _mint(true, Tier.FIVE, owners[i]);
            }   
        } else {
            for (uint i = 0; i < owners.length; i++) {
                _mint(false, tiers[i], owners[i]);
                delete _stakes[owner];
            } 
        }
    }

    function staked(
        address owner,
        uint256 totalStaked
    ) external onlyXVSVault {
        Tier eligibleTier = getEligibleTier(totalStaked);

        if (
            _tokens[owner].isIrrevocable == false &&
            eligibleTier > _tokens[owner].tier &&
            _stakes[owner].tier != eligibleTier
        ) {
            _stakes[owner] = Stake(eligibleTier, block.timestamp);
        }
    }

    function claim() external {
        require(_tokens[msg.sender].tier == Tier.ZERO, "you already own prime token");
        require(_stakes[msg.sender].tier > Tier.ZERO, "you are not eligible to claim prime token");
        require(block.timestamp - _stakes[msg.sender].stakedAt >= STAKING_PERIOD, "you need to wait more time for claiming prime token");

        _mint(false, _stakes[msg.sender].tier, msg.sender);
        delete _stakes[msg.sender];
    }

    function upgrade() external {
        require(_tokens[msg.sender].tier != Tier.ZERO, "you don't own prime token");
        require(_tokens[msg.sender].isIrrevocable == false, "you can only upgrade revocable token");
        require(_stakes[msg.sender].tier > _tokens[msg.sender].tier, "you token is already upgraded");
        require(block.timestamp - _stakes[msg.sender].stakedAt >= STAKING_PERIOD, "you need to wait more time for upgrading prime token");

        _tokens[msg.sender].tier = _stakes[msg.sender].tier;
        delete _stakes[msg.sender];
    }

    function unstaked(
        address owner,
        uint256 totalStaked
    ) external onlyXVSVault {
        Tier eligibleTier = getEligibleTier(totalStaked);

        if (
            _tokens[owner].tier > Tier.ZERO &&
            eligibleTier < _tokens[owner].tier &&
            _tokens[owner].isIrrevocable == false
        ) {
            _tokens[owner].tier = eligibleTier;

            if (eligibleTier == Tier.ZERO) {
                _burn(msg.sender);
            }
        }

        if (_stakes[msg.sender].tier != Tier.ZERO && _stakes[msg.sender].tier != eligibleTier) {
            delete _stakes[msg.sender];
        }
    }

    function _mint(
        bool isIrrevocable,
        Tier tier,
        address owner
    ) internal {
        require(_tokens[owner].tier == Tier.ZERO, "user already owns a prime token");

        Token memory token = Token(isIrrevocable, tier);
        _tokens[owner] = token;

        if (isIrrevocable == true) {
            _totalIrrevocable++;
        } else {
            _totalRevocable++;
        }

        require(
            _totalIrrevocable <= _irrevocableLimit &&
            _totalRevocable <= _revocableLimit,
            "exceeds token mint limit"
        );

        emit Mint(owner, token);
    }

    function _burn(
        address owner
    ) internal {
        require(_tokens[owner].tier != Tier.ZERO, "user doesn't own an prime token");

        if (_tokens[owner].isIrrevocable == true) {
            _totalIrrevocable--;
        } else {
            _totalRevocable--;
        }

        _tokens[owner].tier = Tier.ZERO;

        emit Burn(owner);
    }

    function getEligibleTier(
        uint256 amount
    ) view internal returns (Tier eligibleTier) {
        for(uint i = 0; i < uint(MAX_TIER); i++) {
            if(amount >= _tiers[Tier(i + 1)].threshold) {
                eligibleTier = Tier(i + 1);
            } else {
                break;
            }
        }

        return eligibleTier;
    }

    modifier onlyXVSVault() {
        require(msg.sender == xvsVault, "only XVS vault can call this function");
        _;
    }
}