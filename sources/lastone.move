module lastone::lastone;

use std::ascii::{Self, String};
use std::u64;
use sui::balance::{Self, Balance};
use sui::clock::{Self, Clock};
use sui::coin::{Self, Coin};
use sui::event;
use sui::sui::SUI;
use sui::table::{Self, Table};
use sui::vec_map::{Self, VecMap};

const VERSION: u64 = 3;

public fun package_version(): u64 { VERSION }

// === Errors ===
const EEventNotFound: u64 = 0;
const EEventAlreadyClosed: u64 = 1;
const EEventAlreadyResolved: u64 = 2;
const EInsufficientFunds: u64 = 3;
const EEventNotClosed: u64 = 6;
const EPositionNotFound: u64 = 8; // Error for user position lookup failure
const ECalculationError: u64 = 91; // Error for mathematical calculation issues
const EPeriodTooSmall: u64 = 10; // Error for period too small
const EOutcomeError: u64 = 11;

// === Event Status ===
const EVENT_STATUS_ACTIVE: u8 = 0;
const EVENT_STATUS_RESOLVED: u8 = 2;
// Virtual Liquidity
const VIRTUAL_LIQUIDITY: u64 = 1_000_000_000; // 1 SUI in MIST
// Basis points constants
const BASIS_POINTS: u64 = 10000; // 100% in basis points
const INITIAL_PRICE: u64 = 5000; // 50% in basis points

// === Structs ===

// New struct to hold user's shares per event
public struct UserPosition has drop, store {
    yes_shares: u64,
    no_shares: u64,
}

/// Shared object holding event data (using Tables)
public struct Events has key {
    id: UID,
    // Store Event objects directly, keyed by a simple counter ID for lookup
    next_event_id_counter: u64,
    events: Table<u64, Event>,
    // Store user positions: User Address -> Event ID -> UserPosition
    // Updated value type to UserPosition
    positions: Table<address, VecMap<u64, UserPosition>>,
    // event_creators: Table<u64, address>, // Creator stored within Event struct
    // total_liquidity: Balance<SUI> // Total liquidity managed across all events
}

/// Represents a single prediction event
public struct Event has key, store {
    id: UID,
    round_id: u64,
    name: String,
    end_time: u64, // Timestamp in milliseconds
    // Prices are stored directly, where P_yes + P_no = 1
    yes_price: u64, // Price in basis points (10000 = 100%)
    no_price: u64, // Price in basis points (10000 = 100%)
    status: u8, // Using constants: 0: Active, 1: Closed, 2: Resolved
    resolved_outcome: u8, // 1 for YES, 2 for NO, 0 if not resolved
    yes_shares: u64,
    no_shares: u64,
    // Liquidity will be managed via dedicated pools or balances associated with the event
    yes_liquidity: Balance<SUI>, // Shares representing YES outcome (acts like liquidity)
    no_liquidity: Balance<SUI>, // Shares representing NO outcome (acts like liquidity)
    total_liquidity: u64, // Total SUI value locked in the event according to shares
    creator: address,
}

/// Capability required to manage the Lastone protocol
public struct AdminCap has key {
    id: UID,
}

// === Events ===

public struct EventCreated has copy, drop {
    event_id: u64, // Using the counter ID for simplicity in events
    round_id: u64,
    name_bytes: vector<u8>, // Store bytes instead of String
    end_time: u64,
    creator: address,
}

public struct PositionOpened has copy, drop {
    event_id: u64,
    user: address,
    is_yes: bool, // True if bought YES shares, False if bought NO shares
    sui_amount: u64, // Amount of SUI spent
    shares_bought: u64, // Amount of shares received (renamed from shares_minted)
}

// Event emitted when a user sells shares
public struct PositionClosed has copy, drop {
    event_id: u64,
    user: address,
    is_yes: bool, // True if sold YES shares, False if sold NO shares
    sui_amount: u64, // Amount of SUI received
    shares_sold: u64, // Amount of shares sold
}

public struct EventResolved has copy, drop {
    event_id: u64,
    outcome: u8, // 1 for YES, 2 for NO
}

// Define a struct to hold the information returned by get_events_list
// Make sure all fields are copy, drop, store if the struct itself needs these abilities
public struct EventInfo has copy, drop, store {
    event_id: u64,
    round_id: u64,
    name: String, // Be mindful of string copying costs/semantics
    end_time: u64,
    yes_price: u64,
    no_price: u64,
    yes_liquidity: u64,
    no_liquidity: u64,
    status: u8,
    total_liquidity: u64,
    creator: address,
    resolved_outcome: u8,
}

// === Init ===
/// Helper function to calculate price change based on bet size relative to event liquidity
fun calculate_price_change(bet_amount: u64, total_liquidity: u64): u64 {
    // If there is no liquidity, use the default price change value
    if (total_liquidity == 0) {
        500 // 5% change in basis points
    } else {
        // Calculate impact - larger bets relative to liquidity have a greater impact
        let bet_u128 = bet_amount as u128;
        let liquidity_u128 = (total_liquidity + VIRTUAL_LIQUIDITY) as u128;

        // Impact formula: bet_amount * scale_factor / (total_liquidity + virtual_liquidity)
        // Scaling factor (1000) controls the magnitude of price change per bet
        let price_change_u128 = (bet_u128 * 1000) / liquidity_u128;

        // Limit the maximum price change per transaction
        if (price_change_u128 > 2000) {
            2000 // Maximum 20% change
        } else {
            price_change_u128 as u64
        }
    }
}

/// Initialize the Lastone protocol
fun init(ctx: &mut TxContext) {
    // Create and transfer the Admin Capability to the publisher
    transfer::transfer(AdminCap { id: object::new(ctx) }, tx_context::sender(ctx));

    // Create the shared Events object
    transfer::share_object(Events {
        id: object::new(ctx),
        next_event_id_counter: 0,
        events: table::new<u64, Event>(ctx),
        positions: table::new<address, VecMap<u64, UserPosition>>(ctx),
        // total_liquidity: balance::zero<SUI>()
    });
}

// === Functions (Entry points and helpers will be added here) ===

/// Creates a new prediction event.
/// Only requires round_id and event name, event_id is auto-incremented and end_time is calculated automatically.
public entry fun create_event(
    _: &AdminCap,
    events_obj: &mut Events,
    round_id: u64,
    name: String, // Function receives ownership of name
    clock: &Clock, // Need Clock object to get current time
    period_minutes: u64,
    ctx: &mut TxContext,
) {
    // Set event end time to period minutes from now
    let current_timestamp = clock::timestamp_ms(clock);
    assert!(period_minutes >= 1, EPeriodTooSmall);
    let end_time = current_timestamp + period_minutes * 60 * 1000; // period minutes later

    let event_id_counter = events_obj.next_event_id_counter;
    events_obj.next_event_id_counter = event_id_counter + 1;

    let sender = tx_context::sender(ctx);

    // Get name bytes for the event before moving the original name
    let name_bytes = *ascii::as_bytes(&name); // Copy the bytes vector with the dereference operator *

    let new_event = Event {
        id: object::new(ctx),
        round_id: round_id,
        name: name, // Original name is moved here
        end_time: end_time,
        yes_price: INITIAL_PRICE, // Initial price of 0.5 (50%) for YES
        no_price: INITIAL_PRICE, // Initial price of 0.5 (50%) for NO
        status: EVENT_STATUS_ACTIVE,
        // resolved_outcome is initially None
        resolved_outcome: 0,
        yes_shares: 0,
        no_shares: 0,
        yes_liquidity: balance::zero<SUI>(),
        no_liquidity: balance::zero<SUI>(),
        total_liquidity: 0, // Starts with zero actual liquidity
        creator: sender,
    };

    // Add the event to the shared table
    table::add(&mut events_obj.events, event_id_counter, new_event);

    // Emit an event using the cloned bytes
    event::emit(EventCreated {
        event_id: event_id_counter,
        round_id: round_id,
        name_bytes: name_bytes, // Use the cloned bytes here
        end_time: end_time,
        creator: sender,
    });
}

/// Returns a user's position in a specific event
/// Returns (yes_shares, no_shares)
/// Returns (0, 0) if the user has no position in the event
public fun get_user_position(events_obj: &Events, event_id: u64, user: address): (u64, u64) {
    // Check if the user has any positions
    if (!table::contains(&events_obj.positions, user)) {
        return (0, 0)
    };

    // Get the user's positions map
    let positions_map = table::borrow(&events_obj.positions, user);

    // Check if the user has a position in this event
    if (!vec_map::contains(positions_map, &event_id)) {
        return (0, 0)
    };

    // Get the user's position in this event
    let position = vec_map::get(positions_map, &event_id);
    (position.yes_shares, position.no_shares)
}

/// Returns a list of events with basic details, supporting pagination.
/// `start` is the event ID to start from (inclusive).
/// `limit` is the maximum number of events to return.
public fun get_events_list(events_obj: &Events, start: u64, limit: u64): vector<EventInfo> {
    let mut event_infos = vector::empty<EventInfo>();
    let mut cursor = start;
    let mut count = 0;
    let max_id = events_obj.next_event_id_counter; // Get the upper bound

    // Iterate while we have events and haven't reached the limit
    while (cursor < max_id && count < limit) {
        // Check if a event exists at the current cursor ID
        if (table::contains(&events_obj.events, cursor)) {
            let event = table::borrow(&events_obj.events, cursor);
            vector::push_back(
                &mut event_infos,
                EventInfo {
                    event_id: cursor, // Use the key as the ID
                    round_id: event.round_id,
                    name: event.name, // Cloning the string might be necessary depending on usage
                    end_time: event.end_time,
                    yes_price: event.yes_price,
                    no_price: event.no_price,
                    yes_liquidity: balance::value(&event.yes_liquidity),
                    no_liquidity: balance::value(&event.no_liquidity),
                    status: event.status,
                    total_liquidity: event.total_liquidity,
                    creator: event.creator,
                    resolved_outcome: event.resolved_outcome,
                },
            );
            count = count + 1;
        };
        cursor = cursor + 1;
    };
    event_infos
}

/// Returns the current prices of a event (yes price, no price, total liquidity)
public fun get_event_prices(events_obj: &Events, event_id: u64): (u64, u64, u64) {
    assert!(table::contains(&events_obj.events, event_id), EEventNotFound);
    let event = table::borrow(&events_obj.events, event_id);
    (event.yes_price, event.no_price, event.total_liquidity)
}

/// Calculates how many SUI tokens are needed to buy a specific amount of shares
/// Returns the required SUI amount in MIST (1 SUI = 10^9 MIST)
public fun calculate_sui_needed_for_shares(
    events_obj: &Events,
    event_id: u64,
    is_yes: bool,
    shares_amount: u64,
): u64 {
    assert!(table::contains(&events_obj.events, event_id), EEventNotFound);
    let event = table::borrow(&events_obj.events, event_id);

    // Calculate required SUI based on current price
    if (is_yes) {
        // For YES shares: amount = shares * price
        // Convert price from basis points (10000 = 100%) to decimal
        let price_decimal = (event.yes_price as u128) * 100 / (BASIS_POINTS as u128);
        // Calculate required amount (price is per share)
        // price_decimal is in percentage format (0-100), so we divide by 100 to get actual multiplier
        let sui_amount = (shares_amount as u128) * price_decimal / 100;
        (sui_amount as u64)
    } else {
        // For NO shares: similar calculation with NO price
        let price_decimal = (event.no_price as u128) * 100 / (BASIS_POINTS as u128);
        let sui_amount = (shares_amount as u128) * price_decimal / 100;
        (sui_amount as u64)
    }
}

/// Allows a user to buy YES or NO shares (outcome tokens) in a event.
public entry fun buy_shares(
    events_obj: &mut Events,
    event_id: u64,
    is_yes: bool,
    sui_payment: Coin<SUI>,
    clock: &Clock,
    _slip: u64,
    ctx: &mut TxContext,
) {
    // 1. Get event and check status/time
    assert!(table::contains(&events_obj.events, event_id), EEventNotFound);
    let event = table::borrow_mut(&mut events_obj.events, event_id);
    assert!(event.status == EVENT_STATUS_ACTIVE, EEventAlreadyClosed);

    let current_timestamp = clock::timestamp_ms(clock);
    assert!(current_timestamp < event.end_time, EEventAlreadyClosed);

    // 2. Get payment amount and current balances
    let sui_amount = coin::value(&sui_payment);
    assert!(sui_amount > 0, EInsufficientFunds);
    // We no longer need these variables, as the price is now stored directly in the event structure
    // let y_balance = balance::value(&event.yes_shares);
    // let n_balance = balance::value(&event.no_shares);

    // 3. Elevate to u128 for calculation
    let amount_u128 = sui_amount as u128;
    // Remove unused variables
    // let y_u128 = y_balance as u128;
    // let n_u128 = n_balance as u128;
    // let v_u128 = VIRTUAL_LIQUIDITY as u128;

    // 4. Calculate shares based on current price (which is the probability)
    let shares_bought: u64;

    if (is_yes) {
        // Shares = amount / price (higher price = fewer shares per SUI)
        let price_decimal = (event.yes_price as u128) * 100 / (BASIS_POINTS as u128); // Convert to decimal (0-100)
        assert!(price_decimal > 0, ECalculationError); // Ensure price isn't zero
        // Calculate shares: amount * 100 / price (normalized to percentage)
        let shares_bought_u128 = (amount_u128 * 100) / price_decimal;
        assert!(shares_bought_u128 <= u64::max_value!() as u128, ECalculationError);
        shares_bought = shares_bought_u128 as u64;

        // 5. Add payment to YES balance
        balance::join(&mut event.yes_liquidity, coin::into_balance(sui_payment));

        // Update event prices - increase YES price, decrease NO price
        // The price change is proportional to the amount being added relative to existing liquidity
        let price_change = calculate_price_change(sui_amount, event.total_liquidity);

        // Ensure we don't exceed 100% or go below 0%
        if (price_change < event.no_price) {
            event.yes_price = event.yes_price + price_change;
            event.no_price = event.no_price - price_change;
        } else {
            // Cap at 99% probability to avoid extreme prices
            event.yes_price = 9900; // 99%
            event.no_price = 100; // 1%
        }
    } else {
        // Shares = amount / price (higher price = fewer shares per SUI)
        let price_decimal = (event.no_price as u128) * 100 / (BASIS_POINTS as u128); // Convert to decimal (0-100)
        assert!(price_decimal > 0, ECalculationError); // Ensure price isn't zero
        // Calculate shares: amount * 100 / price (normalized to percentage)
        let shares_bought_u128 = (amount_u128 * 100) / price_decimal;
        assert!(shares_bought_u128 <= u64::max_value!() as u128, ECalculationError);
        shares_bought = shares_bought_u128 as u64;

        // 5. Add payment to NO balance
        balance::join(&mut event.no_liquidity, coin::into_balance(sui_payment));

        // Update event prices - increase NO price, decrease YES price
        let price_change = calculate_price_change(sui_amount, event.total_liquidity);

        // Ensure we don't exceed 100% or go below 0%
        if (price_change < event.yes_price) {
            event.no_price = event.no_price + price_change;
            event.yes_price = event.yes_price - price_change;
        } else {
            // Cap at 99% probability to avoid extreme prices
            event.no_price = 9900; // 99%
            event.yes_price = 100; // 1%
        }
    };

    // Ensure prices always sum to 100%
    assert!(event.yes_price + event.no_price == BASIS_POINTS, ECalculationError);

    // 6. Update event total liquidity tracking (simple sum of actual balances)
    // Recalculate based on balances *after* adding the payment
    event.total_liquidity =
        balance::value(&event.yes_liquidity) + balance::value(&event.no_liquidity);

    // 7. Update user position in the positions table
    let sender = tx_context::sender(ctx);
    let user_positions_map = if (table::contains(&events_obj.positions, sender)) {
        table::borrow_mut(&mut events_obj.positions, sender)
    } else {
        // First time this user interacts with the contract
        table::add(&mut events_obj.positions, sender, vec_map::empty<u64, UserPosition>());
        table::borrow_mut(&mut events_obj.positions, sender)
    };

    let user_event_position = if (vec_map::contains(user_positions_map, &event_id)) {
        vec_map::get_mut(user_positions_map, &event_id)
    } else {
        // First time this user interacts with THIS event
        vec_map::insert(
            user_positions_map,
            event_id,
            UserPosition { yes_shares: 0, no_shares: 0 },
        );
        vec_map::get_mut(user_positions_map, &event_id)
    };

    // Add the bought shares to the user's position
    if (is_yes) {
        user_event_position.yes_shares = user_event_position.yes_shares + shares_bought;
        event.yes_shares = event.yes_shares + shares_bought;
    } else {
        user_event_position.no_shares = user_event_position.no_shares + shares_bought;
        event.no_shares = event.no_shares + shares_bought;
    };

    // 8. Emit event
    event::emit(PositionOpened {
        event_id: event_id,
        user: sender,
        is_yes: is_yes,
        sui_amount: sui_amount,
        shares_bought: shares_bought,
    });
}

/// Allows a user to sell YES or NO shares they previously bought in a event.
public entry fun sell_shares(
    events_obj: &mut Events,
    event_id: u64,
    is_yes: bool,
    shares_amount: u64,
    clock: &Clock,
    _slip: u64,
    ctx: &mut TxContext,
) {
    // 1. Get event and check status/time
    assert!(table::contains(&events_obj.events, event_id), EEventNotFound);
    let event = table::borrow_mut(&mut events_obj.events, event_id);
    assert!(event.status == EVENT_STATUS_ACTIVE, EEventAlreadyClosed);

    let current_timestamp = clock::timestamp_ms(clock);
    assert!(current_timestamp < event.end_time, EEventAlreadyClosed);

    // 2. Check that the user has sufficient shares to sell
    let sender = tx_context::sender(ctx);
    assert!(table::contains(&events_obj.positions, sender), EPositionNotFound);

    let user_positions_map = table::borrow_mut(&mut events_obj.positions, sender);
    assert!(vec_map::contains(user_positions_map, &event_id), EPositionNotFound);

    let user_event_position = vec_map::get_mut(user_positions_map, &event_id);

    if (is_yes) {
        assert!(user_event_position.yes_shares >= shares_amount, EInsufficientFunds);
    } else {
        assert!(user_event_position.no_shares >= shares_amount, EInsufficientFunds);
    };

    // 3. Calculate SUI amount to return based on current price and execute the trade
    let sui_return_amount: u64; // Define the return amount outside both branches

    if (is_yes) {
        // Calculate SUI to return: shares * price / 100 (price is in percentage)
        let price_decimal = (event.yes_price as u128) * 100 / (BASIS_POINTS as u128); // Convert to decimal (0-100)
        let sui_amount_u128 = (shares_amount as u128) * price_decimal / 100;
        sui_return_amount = (sui_amount_u128 as u64);

        // 4. Update user position
        user_event_position.yes_shares = user_event_position.yes_shares - shares_amount;
        event.yes_shares = event.yes_shares - shares_amount;

        // 5. Update event prices - decrease YES price, increase NO price
        let price_change = calculate_price_change(sui_return_amount, event.total_liquidity);

        // Ensure we don't exceed 100% or go below 0%
        if (price_change < event.yes_price) {
            event.yes_price = event.yes_price - price_change;
            event.no_price = event.no_price + price_change;
        } else {
            // Cap at 99% probability to avoid extreme prices
            event.yes_price = 100; // 1%
            event.no_price = 9900; // 99%
        };

        // 6. Take SUI from YES balance and return to user
        // Create a coin from the split balance and transfer to the user
        let balance_split = balance::split(&mut event.yes_liquidity, sui_return_amount);
        let coin_to_return = coin::from_balance(balance_split, ctx);
        sui::transfer::public_transfer(coin_to_return, sender);
    } else {
        // Calculate SUI to return: shares * price / 100 (price is in percentage)
        let price_decimal = (event.no_price as u128) * 100 / (BASIS_POINTS as u128); // Convert to decimal (0-100)
        let sui_amount_u128 = (shares_amount as u128) * price_decimal / 100;
        sui_return_amount = (sui_amount_u128 as u64);

        // 4. Update user position
        user_event_position.no_shares = user_event_position.no_shares - shares_amount;
        event.no_shares = event.no_shares - shares_amount;

        // 5. Update event prices - decrease NO price, increase YES price
        let price_change = calculate_price_change(sui_return_amount, event.total_liquidity);

        // Ensure we don't exceed 100% or go below 0%
        if (price_change < event.no_price) {
            event.no_price = event.no_price - price_change;
            event.yes_price = event.yes_price + price_change;
        } else {
            // Cap at 99% probability to avoid extreme prices
            event.no_price = 100; // 1%
            event.yes_price = 9900; // 99%
        };

        // 6. Take SUI from NO balance and return to user
        // Create a coin from the split balance and transfer to the user
        let balance_split = balance::split(&mut event.no_liquidity, sui_return_amount);
        let coin_to_return = coin::from_balance(balance_split, ctx);
        sui::transfer::public_transfer(coin_to_return, sender);
    };

    // Ensure prices always sum to 100%
    assert!(event.yes_price + event.no_price == BASIS_POINTS, ECalculationError);

    // 7. Update event total liquidity tracking
    event.total_liquidity =
        balance::value(&event.yes_liquidity) + balance::value(&event.no_liquidity);

    // 8. Check if position is now empty and clean up if needed
    if (user_event_position.yes_shares == 0 && user_event_position.no_shares == 0) {
        vec_map::remove(user_positions_map, &event_id);

        // Clean up user's position map if it becomes empty
        if (vec_map::is_empty(user_positions_map)) {
            table::remove(&mut events_obj.positions, sender);
        }
    };

    // 9. Emit event for position close
    let event = PositionClosed {
        event_id,
        user: sender,
        is_yes,
        sui_amount: sui_return_amount,
        shares_sold: shares_amount,
    };
    event::emit(event);
}

/// Resolves a event with the final outcome (YES or NO)
/// Only the event creator can call this function
/// Event must be active and its end time must have passed
public entry fun resolve_event(
    _: &AdminCap,
    events_obj: &mut Events,
    event_id: u64,
    outcome: u8, // true for YES, false for NO
    clock: &Clock,
    _: &mut TxContext,
) {
    assert!(outcome > 0, EOutcomeError);

    // 1. Check that event exists and get mutable reference
    assert!(table::contains(&events_obj.events, event_id), EEventNotFound);
    let event = table::borrow_mut(&mut events_obj.events, event_id);

    // 2. Check that caller is the event creator
    // let sender = tx_context::sender(ctx);
    // assert!(sender == event.creator, EUnauthorized);

    // 3. Check that event is active and not already resolved
    assert!(event.status == EVENT_STATUS_ACTIVE, EEventAlreadyResolved);

    // 4. Check that event end time has passed
    let current_timestamp = clock::timestamp_ms(clock);
    assert!(current_timestamp >= event.end_time, EEventNotClosed);

    // 5. Update event status and set resolved outcome
    event.status = EVENT_STATUS_RESOLVED;
    event.resolved_outcome = outcome;

    if (outcome == 1) {
        let no_balance = balance::withdraw_all(&mut event.no_liquidity);
        balance::join(&mut event.yes_liquidity, no_balance);
    } else {
        let yes_balance = balance::withdraw_all(&mut event.yes_liquidity);
        balance::join(&mut event.no_liquidity, yes_balance);
    };

    event::emit(EventResolved {
        event_id: event_id,
        outcome: outcome,
    });
}

/// Allows a user to claim their winnings from a resolved event
/// The event must be resolved before claiming
/// Only users who bet on the winning outcome can claim rewards
public entry fun claim_winnings(events_obj: &mut Events, event_id: u64, ctx: &mut TxContext) {
    // 1. Check that event exists and is resolved
    assert!(table::contains(&events_obj.events, event_id), EEventNotFound);
    let event = table::borrow_mut(&mut events_obj.events, event_id);
    assert!(event.status == EVENT_STATUS_RESOLVED, EEventNotClosed);

    // 2. Get resolved outcome (should be Some since event is resolved)
    let resolved_outcome = if (&event.resolved_outcome == 1) {
        true
    } else {
        false
    };

    // 3. Check if user has a position in this event
    let sender = tx_context::sender(ctx);
    assert!(table::contains(&events_obj.positions, sender), EPositionNotFound);

    let positions_map = table::borrow_mut(&mut events_obj.positions, sender);
    assert!(vec_map::contains(positions_map, &event_id), EPositionNotFound);

    // 4. Get user position and check if they have shares in the winning outcome
    // vec_map::remove returns a tuple (K, V) where K is the key (event_id) and V is the value (UserPosition)
    let (_, user_position) = vec_map::remove(positions_map, &event_id);

    let winning_shares = if (resolved_outcome) {
        // YES outcome won
        user_position.yes_shares
    } else {
        // NO outcome won
        user_position.no_shares
    };

    // 5. Ensure user has winning shares
    assert!(winning_shares > 0, EInsufficientFunds);

    // 6. Calculate winnings (proportional to share of winning pool)
    let total_winning_pool_size = if (resolved_outcome) {
        // YES outcome won, total winning pool is all YES shares
        balance::value(&event.yes_liquidity)
    } else {
        // NO outcome won, total winning pool is all NO shares
        balance::value(&event.no_liquidity)
    };

    let total_winning_shares = if (resolved_outcome) {
        event.yes_shares
    } else {
        event.no_shares
    };

    // Calculate user's share of the total winning pool
    let total_liquidity = event.total_liquidity;
    // Avoid division by zero if the winning pool somehow has zero balance (shouldn't happen if winning_shares > 0)
    assert!(total_winning_pool_size > 0, ECalculationError);
    // Use u128 for intermediate calculation to prevent overflow
    let user_share_percentage_numerator = (winning_shares as u128) * 10000;
    let user_share_percentage = user_share_percentage_numerator / (total_winning_shares as u128);

    // Calculate winnings as proportion of total liquidity
    let user_winnings_numerator = (total_liquidity as u128) * user_share_percentage;
    let mut user_winnings = (user_winnings_numerator / 10000) as u64;

    // 7. Transfer winnings to user
    let winning_pool_balance = if (resolved_outcome) {
        &mut event.yes_liquidity
    } else {
        &mut event.no_liquidity
    };

    // Ensure we don't try to split more than available in the pool
    // fixme: A rough solution to the precision problem is to use the entire remaining amount if > the remaining amount
    if (user_winnings > balance::value(winning_pool_balance)){
        user_winnings = balance::value(winning_pool_balance);
    };

    let reward_balance = balance::split(winning_pool_balance, user_winnings);
    let reward_coin = coin::from_balance(reward_balance, ctx);
    transfer::public_transfer(reward_coin, sender);

    // 8. Update event total liquidity
    event.total_liquidity = event.total_liquidity - user_winnings;

    // Optional: Clean up user's position map if it becomes empty
    if (vec_map::is_empty(positions_map)) {
        table::remove(&mut events_obj.positions, sender);
    }
}

// === Test-only functions ===

/// Create a Events object for testing
#[test_only]
public fun create_events_test_only(ctx: &mut TxContext) {
    let events_obj = Events {
        id: object::new(ctx),
        next_event_id_counter: 0,
        events: table::new<u64, Event>(ctx),
        positions: table::new<address, VecMap<u64, UserPosition>>(ctx),
    };
    // Share the object immediately after creation
    transfer::share_object(events_obj);
}

#[test_only]
/// Helper for creating a event in tests
public fun create_event_test_only(
    events_obj: &mut Events,
    round_id: u64,
    name: String,
    _clock: &Clock,
    ctx: &mut TxContext,
) {
    // Use fixed end time in test environment
    let end_time = 1719735321000; // Set a fixed future timestamp for testing

    let event_id_counter = events_obj.next_event_id_counter;
    events_obj.next_event_id_counter = event_id_counter + 1;

    let sender = tx_context::sender(ctx);
    let name_bytes = *ascii::as_bytes(&name);

    let new_event = Event {
        id: object::new(ctx),
        round_id: round_id,
        name: name,
        end_time: end_time,
        yes_price: INITIAL_PRICE, // Initial price of 0.5 (50%) for YES
        no_price: INITIAL_PRICE, // Initial price of 0.5 (50%) for NO
        status: EVENT_STATUS_ACTIVE,
        yes_shares: 0,
        no_shares: 0,
        resolved_outcome: 0,
        yes_liquidity: balance::zero<SUI>(),
        no_liquidity: balance::zero<SUI>(),
        total_liquidity: 0,
        creator: sender,
    };

    // Add the event to the table
    table::add(&mut events_obj.events, event_id_counter, new_event);

    // Emit an event
    event::emit(EventCreated {
        event_id: event_id_counter,
        round_id: round_id,
        name_bytes: name_bytes,
        end_time: end_time,
        creator: sender,
    });
}

#[test_only]
/// Get the prices of a event for testing
public fun get_event_prices_test_only(events_obj: &Events, event_id: u64): (u64, u64, u64) {
    let event = table::borrow(&events_obj.events, event_id);
    (event.yes_price, event.no_price, event.total_liquidity)
}

#[test_only]
/// Get event state including status and resolved outcome for testing
public fun get_event_state_test_only(events_obj: &Events, event_id: u64): (u64, u64, u8, bool) {
    let event = table::borrow(&events_obj.events, event_id);
    let outcome = if (&event.resolved_outcome == 1) {
        true
    } else {
        false // Default value if not resolved
    };
    (event.yes_price, event.no_price, event.status, outcome)
}

#[test_only]
/// Helper function to resolve a event in tests
public fun resolve_event_test_only(
    events_obj: &mut Events,
    event_id: u64,
    outcome: u8,
    _ctx: &mut TxContext,
) {
    let event = table::borrow_mut(&mut events_obj.events, event_id);

    // Set event status to resolved
    event.status = EVENT_STATUS_RESOLVED;
    event.resolved_outcome = outcome;

    // Emit event
    event::emit(EventResolved {
        event_id: event_id,
        outcome: outcome,
    });
}

#[test_only]
/// Buy shares in a event for testing
public fun buy_shares_test_only(
    events_obj: &mut Events,
    event_id: u64,
    is_yes: bool,
    sui_payment: Coin<SUI>,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    // todo: _slip
    // Delegate to the main implementation
    buy_shares(events_obj, event_id, is_yes, sui_payment, clock, 0, ctx)
}
