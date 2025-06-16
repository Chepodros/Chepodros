// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// OpenZeppelin contracts for ERC20 token, Ownable access control, and upgradeability
import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol"; // Standard ReentrancyGuard for non-upgradeable base
import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol"; // Uniswap V2 Router interface
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol"; // Required for upgradeable contracts
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol"; // UUPS pattern for upgradeability

// Interface for standard ERC20 tokens, used for rescueTokens
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title Chepodros Token (CHEPOS) - UUPS Implementation for Uniswap V2
 * @dev ERC20 token with anti-bot features, dynamic taxation, liquidity management via Uniswap V2,
 * @dev and timelocked administrative controls. Designed as an upgradeable contract (UUPS pattern) for future extensibility.
 */
contract Chepodros is Initializable, ERC20Upgradeable, OwnableUpgradeable, ReentrancyGuard, UUPSUpgradeable {
    // === Constants ===
    uint256 public constant INITIAL_SUPPLY = 21_000_000_000 * 10 ** 18; // Total token supply (21 billion with 18 decimals).
    uint256 public constant BUY_TAX = 3; // Buy tax percentage (e.g., 3 means 3%).
    uint256 public constant SELL_TAX = 7; // Sell tax percentage (e.g., 7 means 7%).
    uint256 public constant MAX_ANTI_BOT_TAX = 50; // Initial maximum anti-bot tax percentage (e.g., 50 means 50%).
    uint256 public constant ANTI_BOT_DURATION = 5 minutes; // Duration of the anti-bot tax period (e.g., 5 minutes).
    uint256 public constant WHITELIST_DURATION = 2 minutes; // Duration for whitelist-only trading after launch (e.g., 2 minutes).
    uint256 public constant TIMELOCK_DURATION = 24 hours; // Standard timelock duration for critical administrative functions (e.g., 24 hours).
    uint256 public constant SWAP_GAS_LIMIT_MIN = 300_000; // Minimum gas limit allowed for internal swap transactions.
    uint256 public constant SWAP_GAS_LIMIT_MAX = 2_000_000; // Maximum gas limit allowed for internal swap transactions.
    uint256 public constant MIN_SWAP_AMOUNT = 10_000 * 10 ** 18; // Minimum token amount to trigger an automatic swap of collected taxes to ETH.
    uint256 public constant LIMIT_DISABLE_PERIOD = 7 days; // Duration after launch when transaction and wallet limits are automatically disabled.

    // === State Variables ===
    IUniswapV2Router02 public uniswapRouter; // Address of the Uniswap V2 router for liquidity operations.
    address public WETH; // Address of Wrapped Ether (WETH), necessary for ETH conversions via Uniswap.
    address public taxWallet; // Wallet address designated to receive ETH from collected taxes.

    bool public tradingEnabled; // Flag to control the overall trading state (true when enabled).
    uint256 public launchTime; // Timestamp when trading was activated (used for anti-bot and whitelist timing).
    uint256 public limitsDisableTime; // Timestamp when transaction and wallet limits will be automatically disabled.
    uint256 public swapGasLimit; // Current gas limit setting used for internal swap transactions.

    bool public taxesEnabled; // Manual control flag to enable or disable the tax mechanism.

    uint256 public maxTxAmount; // Maximum token amount allowed per single transaction.
    uint256 public maxWallet;    // Maximum token balance allowed per individual wallet.

    // Timelock variables for various administrative functions, storing the timestamp when the timelock expires.
    uint256 public taxWalletTimelock; // Timelock for updating the tax wallet address.
    uint256 public rescueTimelock;    // Timelock for rescue operations (tokens or ETH).
    uint256 public taxesEnabledTimelock; // Timelock for enabling/disabling taxes.
    uint256 public maxTxAmountTimelock;  // Timelock for max transaction amount updates.
    uint256 public maxWalletTimelock;    // Timelock for max wallet balance updates.
    uint256 public swapGasLimitTimelock; // Timelock for swap gas limit updates.
    uint224 public limitsDisableTimelock; // Timelock for setting the limits disable time. (Note: uint224 for efficiency)

    // === Future Integration Variables (for Chainlink & 1inch) ===
    address public chainlinkPriceFeed; // Address of the Chainlink Price Feed contract for external price data integration.
    uint256 public chainlinkTimelock; // Timelock for updating the Chainlink Price Feed address.
    address public oneInchRouter; // Address of the 1inch Router contract for optimized swap routing.
    uint256 public oneInchTimelock; // Timelock for updating the 1inch Router address.

    mapping(address => bool) public excludedFromFees; // Mapping of addresses that are exempt from tax calculation.
    mapping(address => bool) public isWhitelisted;    // Mapping of addresses allowed to trade during the initial whitelist phase.

    // === Events ===
    event TaxWalletUpdated(address indexed newWallet); // Emitted when the tax wallet address is successfully updated.
    event TaxesEnabledUpdated(bool enabled); // Emitted when the tax mechanism is enabled or disabled.
    event SwapGasLimitUpdated(uint256 gasLimit); // Emitted when the swap gas limit is updated.
    event ExcludedFromFees(address indexed account); // Emitted when an address is added to the fee exclusion list.
    event RescueTokens(address indexed to, uint256 amount); // Emitted when ERC20 tokens are rescued from the contract.
    event RescueETH(address indexed to, uint256 amount);    // Emitted when ETH is rescued from the contract.
    event MaxTxAmountUpdated(uint256 amount); // Emitted when the max transaction amount is updated.
    event MaxWalletUpdated(uint256 amount);    // Emitted when the max wallet balance is updated.
    event WhitelistUpdated(address indexed account, bool status); // Emitted when a whitelist status for an address is updated.
    event LimitsDisableTimeSet(uint256 timestamp); // Emitted when the limits disable time is manually set.

    // Timelock trigger events. These indicate that a timelock has been initiated.
    event TaxesTimelockTriggered(); // Emitted when the timelock for taxes enable/disable is triggered.
    event MaxTxTimelockTriggered(); // Emitted when the timelock for max transaction amount is triggered.
    event MaxWalletTimelockTriggered(); // Emitted when the timelock for max wallet balance is triggered.
    event SwapGasLimitTimelockTriggered(); // Emitted when the timelock for swap gas limit is triggered.
    event LimitsDisableTimelockTriggered(); // Emitted when the timelock for limits disable time is triggered.
    event ChainlinkTimelockTriggered(); // Emitted when the timelock for Chainlink price feed address update is triggered.
    event OneInchTimelockTriggered(); // Emitted when the timelock for 1inch router address update is triggered.
    event ChainlinkPriceFeedUpdated(address indexed newAddress); // Emitted when the Chainlink price feed address is updated.
    event OneInchRouterUpdated(address indexed newAddress);      // Emitted when the 1inch router address is updated.

    // === Modifiers ===
    /**
     * @dev Restricts calls until the rescue operations timelock has passed.
     */
    modifier onlyAfterRescueTimelock() {
        require(block.timestamp >= rescueTimelock, "Timelock: rescue locked");
        _;
    }

    /**
     * @dev Restricts calls until the taxes enabled/disabled timelock has passed.
     */
    modifier onlyAfterTaxesTimelock() {
        require(block.timestamp >= taxesEnabledTimelock, "Timelock: taxes locked");
        _;
    }

    /**
     * @dev Restricts calls until the max transaction amount timelock has passed.
     */
    modifier onlyAfterMaxTxTimelock() {
        require(block.timestamp >= maxTxAmountTimelock, "Timelock: maxTx locked");
        _;
    }

    /**
     * @dev Restricts calls until the max wallet balance timelock has passed.
     */
    modifier onlyAfterMaxWalletTimelock() {
        require(block.timestamp >= maxWalletTimelock, "Timelock: maxWallet locked");
        _;
    }

    /**
     * @dev Restricts calls until the swap gas limit timelock has passed.
     */
    modifier onlyAfterGasLimitTimelock() {
        require(block.timestamp >= swapGasLimitTimelock, "Timelock: gas limit locked");
        _;
    }

    /**
     * @dev Restricts calls until the limits disable time timelock has passed.
     */
    modifier onlyAfterLimitsDisableTimelock() {
        require(block.timestamp >= limitsDisableTimelock, "Timelock: limits disable locked");
        _;
    }

    /**
     * @dev Restricts calls until the Chainlink price feed timelock has passed.
     */
    modifier onlyAfterChainlinkTimelock() {
        require(block.timestamp >= chainlinkTimelock, "Timelock: Chainlink locked");
        _;
    }

    /**
     * @dev Restricts calls until the 1inch router timelock has passed.
     */
    modifier onlyAfterOneInchTimelock() {
        require(block.timestamp >= oneInchTimelock, "Timelock: 1inch locked");
        _;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    /**
     * @dev Constructor for the upgradeable contract. It disables the initializer,
     * ensuring that the `initialize` function is called only once through the proxy.
     */
    constructor() {
        _disableInitializers();
    }

    /**
     * @dev Initializes the contract's state variables. This function replaces the traditional constructor
     * for upgradeable contracts and must be called only once via the proxy.
     * @param _uniswapRouter The address of the Uniswap V2 router to be used for liquidity operations.
     * @param _WETH The address of the Wrapped Ether (WETH) token.
     */
    function initialize(address _uniswapRouter, address _WETH) initializer public {
        __ERC20_init("Chepodros", "CHEPOS"); // Initializes the ERC20 token with name and symbol.
        __Ownable_init(msg.sender); // Initializes ownership to the deployer.
        __UUPSUpgradeable_init(); // Initializes the UUPS upgradeability pattern.

        uniswapRouter = IUniswapV2Router02(_uniswapRouter); // Sets the Uniswap V2 router address.
        WETH = _WETH; // Sets the WETH address.
        taxWallet = msg.sender; // Sets the deployer as the initial tax wallet.
        maxTxAmount = INITIAL_SUPPLY; // Sets initial max transaction amount to full supply (no limit).
        maxWallet = INITIAL_SUPPLY;    // Sets initial max wallet balance to full supply (no limit).
        swapGasLimit = 1_000_000; // Sets an initial gas limit for swap operations.
        tradingEnabled = false; // Trading is initially disabled.
        taxesEnabled = true; // Taxes are initially enabled.
        limitsDisableTime = 0; // Limits are active by default until trading is enabled.
    }

    /**
     * @dev Internal function to authorize upgrades for UUPS proxy.
     * Only the contract owner is allowed to call this, ensuring upgrade security.
     * @param newImplementation The address of the new implementation contract to upgrade to.
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    /**
     * @dev Overrides ERC20's _transfer function to implement custom logic including:
     * - Trading activation control.
     * - Initial whitelist enforcement.
     * - Max transaction and max wallet limits (with automatic disablement).
     * - Dynamic tax calculation (anti-bot and permanent buy/sell taxes).
     * - Automatic swapping of collected tax tokens to ETH via Uniswap V2.
     * @param from The address tokens are transferred from.
     * @param to The address tokens are transferred to.
     * @param amount The amount of tokens to transfer.
     */
    function _transfer(address from, address to, uint256 amount) internal override(ERC20Upgradeable) {
        // Basic ERC20 transfer validation: prevent transfers to/from zero address.
        require(from != address(0) && to != address(0), "ERC20: zero address");

        // Trading restrictions:
        // Transactions are only allowed if trading is enabled, OR if sender/receiver is owner, OR if whitelisted (during initial phase).
        require(tradingEnabled || from == owner() || to == owner() || isWhitelisted[from] || isWhitelisted[to], "Trading not enabled");

        // Initial whitelist phase enforcement:
        // During a specific period after launch, only whitelisted addresses can trade.
        if (block.timestamp < launchTime + WHITELIST_DURATION) {
            require(isWhitelisted[from] || isWhitelisted[to], "Only whitelisted addresses allowed during initial phase");
        }

        // Transaction and wallet limits enforcement:
        // Limits are active until `limitsDisableTime` has passed.
        // Excluded accounts, the contract itself, and the owner are exempt from these checks.
        if (block.timestamp < limitsDisableTime || limitsDisableTime == 0) {
            if (!excludedFromFees[from] && !excludedFromFees[to]) {
                require(amount <= maxTxAmount, "Exceeds maxTxAmount"); // Enforce max transaction amount.
                // Max wallet check applies only if recipient is not the contract itself or the owner.
                if (to != address(this) && to != owner()) {
                    require(balanceOf(to) + amount <= maxWallet, "Exceeds maxWallet"); // Enforce max wallet balance.
                }
            }
        }

        uint256 taxAmount = 0; // Initialize tax amount.

        // Tax calculation:
        // Taxes are applied only if enabled and neither sender nor receiver is excluded from fees.
        if (taxesEnabled && !excludedFromFees[from] && !excludedFromFees[to]) {
            if (tradingEnabled && block.timestamp < launchTime + ANTI_BOT_DURATION) {
                // Anti-bot tax phase: tax percentage reduces over time.
                uint256 timeElapsed = block.timestamp - launchTime; // Time passed since launch.
                uint256 reduction = (timeElapsed / 1 minutes) * 10; // Tax reduction by 10% every minute.
                // Calculate anti-bot tax, ensuring it doesn't go below zero.
                uint256 antiBotTax = MAX_ANTI_BOT_TAX > reduction ? MAX_ANTI_BOT_TAX - reduction : 0;
                taxAmount = amount * antiBotTax / 100;
            } else {
                // Permanent tax phase: standard buy/sell taxes.
                if (from == address(uniswapRouter)) { // If tokens are coming from the Uniswap router (a buy).
                    taxAmount = amount * BUY_TAX / 100;
                } else if (to == address(uniswapRouter)) { // If tokens are going to the Uniswap router (a sell).
                    taxAmount = amount * SELL_TAX / 100;
                }
            }
        }

        uint256 amountAfterTax = amount - taxAmount; // Amount to transfer to the recipient after tax.
        super._transfer(from, to, amountAfterTax); // Perform the actual token transfer.

        if (taxAmount > 0) {
            super._transfer(from, address(this), taxAmount); // Transfer calculated tax amount to the contract for collection.
        }

        // Automatic swap of collected taxes:
        // Triggers if tokens are being sent to the Uniswap router (a sell transaction)
        // and the contract holds enough tokens to meet the minimum swap amount.
        if (to == address(uniswapRouter) && balanceOf(address(this)) >= MIN_SWAP_AMOUNT) {
            swapTokensForEth(balanceOf(address(this)));
        }
    }

    /**
     * @dev Swaps collected tokens held by the contract for WETH (Wrapped Ether) via Uniswap V2
     * and sends the resulting WETH to the designated tax wallet.
     * This function is private and called internally, primarily by `_transfer` for auto-swaps.
     * It uses Uniswap V2's `swapExactTokensForETHSupportingFeeOnTransferTokens` to handle fee-on-transfer tokens.
     * Protected by ReentrancyGuard to prevent re-entrant attacks.
     * @param tokenAmount The amount of contract's own tokens to swap.
     */
    function swapTokensForEth(uint256 tokenAmount) private nonReentrant {
        // Approve the Uniswap V2 router to spend the contract's tokens.
        _approve(address(this), address(uniswapRouter), tokenAmount);

        // Define the swap path: from this token to WETH.
        address[] memory path = new address[](2);
        path[0] = address(this); // Input token is the contract's own token.
        path[1] = WETH;          // Output token is WETH.

        // Execute the swap on Uniswap V2, with a minimum output amount to protect against slippage
        // and a specified gas limit.
        uniswapRouter.swapExactTokensForETHSupportingFeeOnTransferTokens{gas: swapGasLimit}(
            tokenAmount,                  // The exact amount of tokens to swap.
            tokenAmount * 95 / 100,       // amountOutMin: Minimum amount of WETH expected (5% slippage protection).
            path,                         // The trading path.
            taxWallet,                    // Recipient of the swapped WETH.
            block.timestamp               // deadline: Transaction must be mined by this timestamp.
        );
    }

    /**
     * @dev Allows the owner to manually trigger a swap of collected tax tokens to WETH
     * and send the resulting WETH to the tax wallet.
     * This function provides a manual override for the automatic swap mechanism.
     * It uses Uniswap V2's `swapExactTokensForETHSupportingFeeOnTransferTokens` to handle fee-on-transfer tokens.
     * Protected by ReentrancyGuard to prevent re-entrant attacks.
     * Can only be called by the contract owner.
     */
    function manualSwapAndSend() external onlyOwner nonReentrant {
        uint256 contractBalance = balanceOf(address(this)); // Get the current balance of tokens held by the contract.
        require(contractBalance > 0, "No tokens to swap"); // Revert if the contract holds no tokens to swap.

        // Approve the Uniswap V2 router to spend the contract's tokens.
        _approve(address(this), address(uniswapRouter), contractBalance);

        // Define the swap path: from this token to WETH.
        address[] memory path = new address[](2);
        path[0] = address(this); // Input token is the contract's own token.
        path[1] = WETH;          // Output token is WETH.

        // Execute the swap on Uniswap V2, with a minimum output amount to protect against slippage
        // and a specified gas limit.
        uniswapRouter.swapExactTokensForETHSupportingFeeOnTransferTokens{gas: swapGasLimit}(
            contractBalance,              // The exact amount of tokens to swap.
            contractBalance * 95 / 100,   // amountOutMin: Minimum amount of WETH expected (5% slippage protection).
            path,                         // The trading path.
            taxWallet,                    // Recipient of the swapped WETH.
            block.timestamp               // deadline: Transaction must be mined by this timestamp.
        );
    }

    /**
     * @dev Enables trading for the token.
     * This function can only be called once by the contract owner.
     * It sets `tradingEnabled` to true and records the `launchTime`, also setting `limitsDisableTime`.
     */
    function openTrading() external onlyOwner {
        require(!tradingEnabled, "Already enabled"); // Ensure trading is not already enabled.
        tradingEnabled = true; // Set trading status to enabled.
        launchTime = block.timestamp; // Record the timestamp of trading activation.
        limitsDisableTime = launchTime + LIMIT_DISABLE_PERIOD; // Set the automatic limits disable time.
    }

    /**
     * @dev Allows any token holder to burn (destroy) their own tokens,
     * effectively reducing the total supply of the token.
     * @param amount The amount of tokens to burn from the caller's balance.
     */
    function burn(uint256 amount) external {
        _burn(msg.sender, amount); // Calls the internal ERC20 burn function.
    }

    /**
     * @dev Sets a new address for the tax wallet.
     * This function is protected by a timelock (`taxWalletTimelock`) to allow for a delay
     * before the change takes effect, providing time for review or cancellation.
     * Can only be called by the contract owner.
     * @param newWallet The address of the new tax wallet. Must not be the zero address.
     */
    function setTaxWallet(address newWallet) external onlyOwner {
        require(block.timestamp >= taxWalletTimelock, "Timelock: tax wallet locked"); // Check if timelock has expired.
        require(newWallet != address(0), "Zero address"); // Ensure the new address is not the zero address.
        taxWallet = newWallet; // Update the tax wallet address.
        emit TaxWalletUpdated(newWallet); // Emit an event indicating the update.
    }

    /**
     * @dev Enables or disables the tax mechanism for transactions.
     * This function is protected by a timelock (`taxesEnabledTimelock`).
     * Can only be called by the contract owner.
     * @param enabled True to enable taxes, false to disable them.
     */
    function setTaxesEnabled(bool enabled) external onlyOwner onlyAfterTaxesTimelock {
        taxesEnabled = enabled; // Set the tax mechanism status.
        emit TaxesEnabledUpdated(enabled); // Emit an event indicating the change.
    }

    /**
     * @dev Sets the gas limit for internal Uniswap swap transactions.
     * This function is protected by a timelock (`swapGasLimitTimelock`).
     * Can only be called by the contract owner.
     * @param gasLimit The new gas limit. Must be within defined `SWAP_GAS_LIMIT_MIN` and `SWAP_GAS_LIMIT_MAX`.
     */
    function setSwapGasLimit(uint256 gasLimit) external onlyOwner onlyAfterGasLimitTimelock {
        require(gasLimit >= SWAP_GAS_LIMIT_MIN && gasLimit <= SWAP_GAS_LIMIT_MAX, "Invalid gas limit"); // Validate gas limit range.
        swapGasLimit = gasLimit; // Update the swap gas limit.
        emit SwapGasLimitUpdated(gasLimit); // Emit an event indicating the update.
    }

    /**
     * @dev Excludes a single address from tax calculation.
     * Transactions involving this address will not incur taxes.
     * Can only be called by the contract owner.
     * @param account The address to exclude from fees.
     */
    function excludeFromFees(address account) external onlyOwner {
        excludedFromFees[account] = true; // Set the exclusion status for the given account.
        emit ExcludedFromFees(account); // Emit an event indicating the exclusion.
    }

    /**
     * @dev Allows excluding multiple addresses from fee calculation in a single transaction.
     * Can only be called by the contract owner.
     * @param accounts_ The array of addresses to exclude from fees.
     */
    function batchExcludeFromFees(address[] calldata accounts_) external onlyOwner {
        for (uint256 i = 0; i < accounts_.length; i++) {
            excludedFromFees[accounts_[i]] = true; // Set each address's exclusion status to true.
            emit ExcludedFromFees(accounts_[i]); // Emits an event for each excluded address.
        }
    }

    /**
     * @dev Updates the maximum transaction amount allowed for transfers.
     * This function is protected by a timelock (`maxTxAmountTimelock`).
     * Can only be called by the contract owner.
     * @param amount The new maximum transaction amount.
     */
    function updateMaxTxAmount(uint256 amount) external onlyOwner onlyAfterMaxTxTimelock {
        maxTxAmount = amount; // Update the maximum transaction amount.
        emit MaxTxAmountUpdated(amount); // Emit an event indicating the update.
    }

    /**
     * @dev Updates the maximum token balance allowed per wallet.
     * This function is protected by a timelock (`maxWalletTimelock`).
     * Can only be called by the contract owner.
     * @param amount The new maximum wallet balance.
     */
    function updateMaxWallet(uint256 amount) external onlyOwner onlyAfterMaxWalletTimelock {
        maxWallet = amount; // Update the maximum wallet balance.
        emit MaxWalletUpdated(amount); // Emit an event indicating the update.
    }

    /**
     * @dev Sets or unsets the whitelist status for a specific address.
     * Whitelisted addresses are allowed to trade during the initial whitelist-only phase.
     * Can only be called by the contract owner.
     * @param account The address to modify.
     * @param whitelisted True to whitelist, false to un-whitelist the address.
     */
    function setWhitelist(address account, bool whitelisted) external onlyOwner {
        isWhitelisted[account] = whitelisted; // Set the whitelist status for the given account.
        emit WhitelistUpdated(account, whitelisted); // Emit an event indicating the update.
    }

    /**
     * @dev Allows adding multiple addresses to the whitelist in a single transaction.
     * Can only be called by the contract owner.
     * @param accounts_ The array of addresses to add to the whitelist.
     */
    function batchAddToWhitelist(address[] calldata accounts_) external onlyOwner {
        for (uint256 i = 0; i < accounts_.length; i++) {
            isWhitelisted[accounts_[i]] = true; // Set each address's whitelist status to true.
            emit WhitelistUpdated(accounts_[i], true); // Emits an event for each whitelisted address.
        }
    }

    /**
     * @dev Allows the contract owner to rescue accidentally sent ERC20 tokens
     * (other than this contract's own token) that might be stuck in this contract.
     * This function is protected by a timelock (`rescueTimelock`).
     * @param token The address of the ERC20 token to rescue. Must not be this contract's address.
     * @param to The recipient address for the rescued tokens.
     * @param amount The amount of tokens to rescue.
     */
    function rescueTokens(address token, address to, uint256 amount) external onlyOwner onlyAfterRescueTimelock {
        require(token != address(this), "Cannot rescue own tokens (CHEPOS)"); // Prevent rescuing the contract's own tokens.
        IERC20(token).transfer(to, amount); // Transfer the specified token amount to the recipient.
        emit RescueTokens(to, amount); // Emit an event indicating the rescue.
    }

    /**
     * @dev Allows the contract owner to rescue accidentally sent ETH that might be stuck in this contract.
     * This function is protected by a timelock (`rescueTimelock`).
     * @param to The recipient address for the rescued ETH.
     */
    function rescueETH(address to) external onlyOwner onlyAfterRescueTimelock {
        uint256 balance = address(this).balance; // Get the current ETH balance of the contract.
        payable(to).transfer(balance); // Transfer all ETH to the recipient.
        emit RescueETH(to, balance); // Emit an event indicating the rescue.
    }

    /**
     * @dev Sets the timestamp when transaction and wallet limits will be automatically disabled.
     * This function can only be called once by the owner after trading is enabled (or if `limitsDisableTime` is 0).
     * It is protected by a timelock (`limitsDisableTimelock`).
     * @param timestamp_ The specific future timestamp when limits should be disabled.
     */
    function setLimitsDisableTime(uint256 timestamp_) external onlyOwner onlyAfterLimitsDisableTimelock {
        require(timestamp_ > block.timestamp, "Timestamp must be in the future"); // Ensure the timestamp is in the future.
        // Ensure this function is only callable if limitsDisableTime has not been set, or if it was set automatically during launch.
        require(limitsDisableTime == 0 || limitsDisableTime == launchTime + LIMIT_DISABLE_PERIOD, "Limits disable time already set or cannot be changed manually after automatic setting");
        limitsDisableTime = timestamp_; // Sets the timestamp for disabling limits.
        emit LimitsDisableTimeSet(timestamp_); // Emits an event.
    }

    /**
     * @dev Sets the address of the Chainlink Price Feed contract.
     * This function is protected by a timelock (`chainlinkTimelock`).
     * Can only be called by the contract owner.
     * @param _newAddress The new address of the Chainlink Price Feed. Must not be the zero address.
     */
    function setChainlinkPriceFeed(address _newAddress) external onlyOwner onlyAfterChainlinkTimelock {
        require(_newAddress != address(0), "Zero address not allowed"); // Ensure the new address is not the zero address.
        chainlinkPriceFeed = _newAddress; // Update the Chainlink Price Feed address.
        emit ChainlinkPriceFeedUpdated(_newAddress); // Emit an event indicating the update.
    }

    /**
     * @dev Sets the address of the 1inch Router contract.
     * This function is protected by a timelock (`oneInchTimelock`).
     * Can only be called by the contract owner.
     * @param _newAddress The new address of the 1inch Router. Must not be the zero address.
     */
    function setOneInchRouter(address _newAddress) external onlyOwner onlyAfterOneInchTimelock {
        require(_newAddress != address(0), "Zero address not allowed"); // Ensure the new address is not the zero address.
        oneInchRouter = _newAddress; // Update the 1inch Router address.
        emit OneInchRouterUpdated(_newAddress); // Emit an event indicating the update.
    }

    // === Timelock Management Functions ===
    // These functions allow the owner to initiate a timelock for subsequent administrative actions.
    // The actual action can only be performed after the `TIMELOCK_DURATION` has passed from the trigger time.

    /**
     * @dev Triggers the timelock for rescue operations (`rescueTokens`, `rescueETH`).
     * Rescue functions will become callable only after `TIMELOCK_DURATION` has passed from this call.
     * Can only be called by the contract owner.
     */
    function triggerRescueTimelock() external onlyOwner {
        rescueTimelock = block.timestamp + TIMELOCK_DURATION; // Set the timelock expiration for rescue functions.
    }

    /**
     * @dev Triggers the timelock for changing the tax wallet address (`setTaxWallet`).
     * The tax wallet update will become callable only after `TIMELOCK_DURATION` has passed from this call.
     * Can only be called by the contract owner.
     */
    function triggerTaxWalletTimelock() external onlyOwner {
        taxWalletTimelock = block.timestamp + TIMELOCK_DURATION; // Set the timelock expiration for tax wallet updates.
    }

    /**
     * @dev Triggers the timelock for enabling/disabling taxes (`setTaxesEnabled`).
     * The taxes setting will become callable only after `TIMELOCK_DURATION` has passed from this call.
     * Can only be called by the contract owner.
     */
    function triggerTaxesTimelock() external onlyOwner {
        taxesEnabledTimelock = block.timestamp + TIMELOCK_DURATION; // Set the timelock expiration for taxes status.
        emit TaxesTimelockTriggered(); // Emit an event indicating the timelock trigger.
    }

    /**
     * @dev Triggers the timelock for updating the maximum transaction amount (`updateMaxTxAmount`).
     * The max transaction amount update will become callable only after `TIMELOCK_DURATION` has passed from this call.
     * Can only be called by the contract owner.
     */
    function triggerMaxTxTimelock() external onlyOwner {
        maxTxAmountTimelock = block.timestamp + TIMELOCK_DURATION; // Set the timelock expiration for max transaction amount.
        emit MaxTxTimelockTriggered(); // Emit an event indicating the timelock trigger.
    }

    /**
     * @dev Triggers the timelock for updating the maximum wallet holding (`updateMaxWallet`).
     * The max wallet holding update will become callable only after `TIMELOCK_DURATION` has passed from this call.
     * Can only be called by the contract owner.
     */
    function triggerMaxWalletTimelock() external onlyOwner {
        maxWalletTimelock = block.timestamp + TIMELOCK_DURATION; // Set the timelock expiration for max wallet balance.
        emit MaxWalletTimelockTriggered(); // Emit an event indicating the timelock trigger.
    }

    /**
     * @dev Triggers the timelock for updating the swap gas limit (`setSwapGasLimit`).
     * The swap gas limit update will become callable only after `TIMELOCK_DURATION` has passed from this call.
     * Can only be called by the contract owner.
     */
    function triggerSwapGasLimitTimelock() external onlyOwner {
        swapGasLimitTimelock = block.timestamp + TIMELOCK_DURATION; // Set the timelock expiration for swap gas limit.
        emit SwapGasLimitTimelockTriggered(); // Emit an event indicating the timelock trigger.
    }

    /**
     * @dev Triggers the timelock for setting the limits disable time (`setLimitsDisableTime`).
     * The limits disable time can be set only after `TIMELOCK_DURATION` has passed from this call.
     * Can only be called by the contract owner.
     */
    function triggerLimitsDisableTimelock() external onlyOwner {
        limitsDisableTimelock = block.timestamp + TIMELOCK_DURATION; // Set the timelock expiration for limits disable time.
        emit LimitsDisableTimelockTriggered(); // Emits an event.
    }

    /**
     * @dev Triggers the timelock for updating the Chainlink Price Feed address (`setChainlinkPriceFeed`).
     * The address update will become callable only after `TIMELOCK_DURATION` has passed from this call.
     * Can only be called by the contract owner.
     */
    function triggerChainlinkTimelock() external onlyOwner {
        chainlinkTimelock = block.timestamp + TIMELOCK_DURATION; // Sets the timelock expiration for Chainlink price feed.
        emit ChainlinkTimelockTriggered(); // Emits an event.
    }

    /**
     * @dev Triggers the timelock for updating the 1inch Router address (`setOneInchRouter`).
     * The address update will become callable only after `TIMELOCK_DURATION` has passed from this call.
     * Can only be called by the contract owner.
     */
    function triggerOneInchTimelock() external onlyOwner {
        oneInchTimelock = block.timestamp + TIMELOCK_DURATION; // Sets the timelock expiration for 1inch router.
        emit OneInchTimelockTriggered(); // Emits an event.
    }

    // === Fallback functions to receive ETH ===
    /**
     * @dev Allows the contract to receive plain Ether.
     * This function is executed when Ether is sent to the contract address without any data.
     */
    receive() external payable {}

    /**
     * @dev Allows the contract to receive plain Ether when no other function matches the calldata.
     * This is the fallback function.
     */
    fallback() external payable {}
}