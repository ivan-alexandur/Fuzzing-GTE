// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {ClearingHouse} from "./ClearingHouse.sol";
import {InsuranceFund} from "./InsuranceFund.sol";
import {CollateralManager} from "./CollateralManager.sol";
import {FeeManager} from "./FeeManager.sol";

import {Market, MarketSettings, MarketMetadata} from "./Market.sol";
import {FundingRateEngine, FundingRateSettings} from "./FundingRateEngine.sol";

import {Book, BookConfig, BookSettings, BookMetadata} from "./Book.sol";
import {BookType} from "./Enums.sol";

// @todo change get to load & take loads out of ClearingHouseLib

library StorageLib {
    /// erc7201('ClearingHouse')
    bytes32 constant CLEARING_HOUSE_SLOT = 0x82401ef06211501256a876d252aaf61e7132ccc51e18716e2d709a0d4272e700;
    /// erc7201('InsuranceFund')
    bytes32 constant INSURANCE_FUND_SLOT = 0xbfd5935e9ce192860479583c8f68d8f0281e1b205c9b51903c37fd1663caf700;
    /// erc7201('CollateralManager')
    bytes32 constant COLLATERAL_MANAGER_SLOT = 0x61b9ccef1e220863792471c905db5592dea4de72f361956c0ad957095e951f00;
    /// erc7201('FeeManager')
    bytes32 constant FEE_MANAGER_SLOT = 0x342baed097735cb285ac1652589d9be5e07986ffa1048894c329a3e87d336000;

    /// erc7201('MarketSettings')
    bytes32 constant MARKET_SETTINGS_SLOT = 0xabab056a6b37dca48028a49dc141d38e864363077235e1ceedd891a9da3d5700;
    /// erc7201('MarketMetadata')
    bytes32 constant MARKET_METADATA_SLOT = 0x924d635e09fb0ed4d506fa4757253ad18d1012b6778f35eaca050f36795c0e00;
    /// erc7201('FundingRateEngine')
    bytes32 constant FUNDING_RATE_ENGINE_SLOT = 0x617f70bdcfb1b30f7368b905448126d45e4211d49d45d0b890adb64417867a00;
    /// erc7201('FundingRateSettings')
    bytes32 constant FUNDING_RATE_SETTINGS_SLOT = 0x2d9df79ce2a04bace979c8e7822d5d58e0eba86f9b6d650a53d036070e79e300;

    /// erc7201('Book')
    bytes32 constant PERP_CLOB_SLOT = 0xa57a5c98162987d0c55c599afa286778f3124669c2f7ee0229f5fa9d51839700;
    /// erc7201('BookConfig')
    bytes32 constant BOOK_CONFIG_SLOT = 0x9664b91c31ceff59d9f1ffab6c8af23eb35df7e5770fbcfcb63ce9d0c5f3d600;
    /// erc7201('BookSettings')
    bytes32 constant BOOK_SETTINGS_SLOT = 0xfd97e8e280d3f806a8f248b702ebf7f7d42962451433a0b02180a11a7d773b00;
    /// erc7201('BookMetadata')
    bytes32 constant BOOK_METADATA_SLOT = 0x96ac35e14db2dbf70714b88de0d8321e86e7af2b879d88c55718ded69e62bf00;

    /// erc7201('EventNonce')
    bytes32 constant EVENT_NONCE_SLOT = 0x00f57b92438c2add21322de9585c2e64b6631becda92262d6e63a910f44abd00;

    /*//////////////////////////////////////////////////////////////
                             CLEARINGHOUSE
    //////////////////////////////////////////////////////////////*/

    function loadClearingHouse() internal pure returns (ClearingHouse storage ch) {
        bytes32 slot = CLEARING_HOUSE_SLOT;

        assembly {
            ch.slot := slot
        }
    }

    function loadInsuranceFund() internal pure returns (InsuranceFund storage insuranceFund) {
        bytes32 slot = INSURANCE_FUND_SLOT;

        assembly {
            insuranceFund.slot := slot
        }
    }

    function loadCollateralManager() internal pure returns (CollateralManager storage collateralManager) {
        bytes32 slot = COLLATERAL_MANAGER_SLOT;

        assembly {
            collateralManager.slot := slot
        }
    }

    function loadFeeManager() internal pure returns (FeeManager storage feeManager) {
        bytes32 slot = FEE_MANAGER_SLOT;

        assembly {
            feeManager.slot := slot
        }
    }

    /*//////////////////////////////////////////////////////////////
                                 MARKET
    //////////////////////////////////////////////////////////////*/

    function loadMarket(bytes32 asset) internal view returns (Market storage market) {
        return loadClearingHouse().market[asset];
    }

    function loadMarketSettings(bytes32 asset) internal pure returns (MarketSettings storage marketSettings) {
        bytes32 slot = keccak256(abi.encode(asset, MARKET_SETTINGS_SLOT));

        assembly {
            marketSettings.slot := slot
        }
    }

    function loadMarketMetadata(bytes32 asset) internal pure returns (MarketMetadata storage marketMetadata) {
        bytes32 slot = keccak256(abi.encode(asset, MARKET_METADATA_SLOT));

        assembly {
            marketMetadata.slot := slot
        }
    }

    function loadFundingRateEngine(bytes32 asset) internal pure returns (FundingRateEngine storage fundingRateEngine) {
        bytes32 slot = keccak256(abi.encode(asset, FUNDING_RATE_ENGINE_SLOT));

        assembly {
            fundingRateEngine.slot := slot
        }
    }

    function loadFundingRateSettings(bytes32 asset) internal pure returns (FundingRateSettings storage settings) {
        bytes32 slot = keccak256(abi.encode(asset, FUNDING_RATE_SETTINGS_SLOT));

        assembly {
            settings.slot := slot
        }
    }

    /*//////////////////////////////////////////////////////////////
                                  BOOK
    //////////////////////////////////////////////////////////////*/

    function loadBook(bytes32 asset) internal pure returns (Book storage ds) {
        bytes32 assetSlot = keccak256(abi.encode(uint256(keccak256(abi.encode(asset))) - 1)) & ~bytes32(uint256(0xff));

        // note: simulates a PerpBook => asset mapping
        bytes32 slot = keccak256(abi.encode(BookType.STANDARD, assetSlot, PERP_CLOB_SLOT));

        assembly {
            ds.slot := slot
        }
    }

    function loadBackstopBook(bytes32 asset) internal pure returns (Book storage ds) {
        bytes32 assetSlot = keccak256(abi.encode(uint256(keccak256(abi.encode(asset))) - 1)) & ~bytes32(uint256(0xff));

        // note: simulates a PerpBook => asset mapping
        bytes32 slot = keccak256(abi.encode(BookType.BACKSTOP, assetSlot, PERP_CLOB_SLOT));

        assembly {
            ds.slot := slot
        }
    }

    function loadBook(bytes32 asset, BookType bookType) internal pure returns (Book storage ds) {
        bytes32 assetSlot = keccak256(abi.encode(uint256(keccak256(abi.encode(asset))) - 1)) & ~bytes32(uint256(0xff));

        // asset => book type => book mapping
        bytes32 slot = keccak256(abi.encode(bookType, assetSlot, PERP_CLOB_SLOT));

        assembly {
            ds.slot := slot
        }
    }

    function loadBookConfig(bytes32 asset) internal pure returns (BookConfig storage bookConfig) {
        bytes32 slot = keccak256(abi.encode(asset, BOOK_CONFIG_SLOT));

        assembly {
            bookConfig.slot := slot
        }
    }

    function loadBookSettings(bytes32 asset) internal pure returns (BookSettings storage bookSettings) {
        bytes32 slot = keccak256(abi.encode(asset, BOOK_SETTINGS_SLOT));

        assembly {
            bookSettings.slot := slot
        }
    }

    /*//////////////////////////////////////////////////////////////
                                 NONCE
    //////////////////////////////////////////////////////////////*/

    function incNonce() internal returns (uint256 n) {
        bytes32 slot = EVENT_NONCE_SLOT;

        assembly {
            n := add(sload(slot), 1)
            sstore(slot, n)
        }
    }

    function loadNonce() internal view returns (uint256 n) {
        bytes32 slot = EVENT_NONCE_SLOT;

        assembly {
            n := sload(slot)
        }
    }
}
