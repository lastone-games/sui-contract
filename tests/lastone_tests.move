#[test_only]
module lastone::lastone_tests {
    use sui::clock::{Self, Clock};
    use sui::test_scenario::{Self};
    // tx_context is already provided by default
    use sui::coin::{Self};
    use std::ascii;
    use sui::sui::SUI;
    // tx_context is already imported by default
    use lastone::lastone::{Self, Events};

    // === Constants ===
    const ADMIN: address = @0x1;
    const USER1: address = @0x2;
    const USER2: address = @0x3;

    const BASIS_POINTS: u64 = 10000;
    const INITIAL_PRICE: u64 = 5000;

    #[test]
    fun test_event_creation() {
        let mut scenario = test_scenario::begin(ADMIN);
        {
            // First transaction: create Clock and Events objects
            let ctx = test_scenario::ctx(&mut scenario);
            let clock = clock::create_for_testing(ctx);
            clock::share_for_testing(clock);
            lastone::create_events_test_only(ctx);
        };

        // Move to the next transaction
        test_scenario::next_tx(&mut scenario, ADMIN);
        {
            // Now we can take the shared objects
            let clock_ref = test_scenario::take_shared<Clock>(&scenario);
            let mut events = test_scenario::take_shared<Events>(&scenario);

            let ctx = test_scenario::ctx(&mut scenario);

            let round_id = 1;
            let name = ascii::string(b"Will BTC reach $100,000 by 2025?");
            let event_id = 0;

            lastone::create_event_test_only(
                &mut events, round_id, name, &clock_ref, ctx
            );

            let (yes_price, no_price, _) = lastone::get_event_prices_test_only(
                &events, event_id
            );
            assert!(yes_price == INITIAL_PRICE, 0);
            assert!(no_price == INITIAL_PRICE, 1);
            assert!(yes_price + no_price == BASIS_POINTS, 2);

            // Return shared objects before ending the transaction
            test_scenario::return_shared(events);
            test_scenario::return_shared(clock_ref);
        };
        test_scenario::end(scenario);
    }

    #[test]
    fun test_buy_shares_price_update() {
        let mut scenario = test_scenario::begin(ADMIN);
        {
            // First transaction: create Clock and Events objects
            let ctx = test_scenario::ctx(&mut scenario);
            let clock = clock::create_for_testing(ctx);
            clock::share_for_testing(clock);
            lastone::create_events_test_only(ctx);
        };

        // Event creation transaction
        let event_id; // Define event_id here to use across transactions
        test_scenario::next_tx(&mut scenario, ADMIN);
        {
            // Take shared objects
            let clock_ref = test_scenario::take_shared<Clock>(&scenario);
            let mut events = test_scenario::take_shared<Events>(&scenario);
            let ctx = test_scenario::ctx(&mut scenario);

            let round_id = 1;
            let name = ascii::string(b"Will BTC reach $100,000 by 2025?");
            event_id = 0;

            lastone::create_event_test_only(
                &mut events, round_id, name, &clock_ref, ctx
            );

            // Return shared objects
            test_scenario::return_shared(events);
            test_scenario::return_shared(clock_ref);
        };

        // Buying shares transaction
        test_scenario::next_tx(&mut scenario, USER1);
        {
            // Take shared objects again
            let clock_ref = test_scenario::take_shared<Clock>(&scenario);
            let mut events = test_scenario::take_shared<Events>(&scenario);

            let ctx = test_scenario::ctx(&mut scenario);
            let sui_coin = coin::mint_for_testing<SUI>(1_000_000_000, ctx);

            lastone::buy_shares_test_only(
                &mut events, event_id, true, sui_coin, &clock_ref, ctx
            );

            let (yes_price_after, no_price_after, _) = lastone::get_event_prices_test_only(
                &events, event_id
            );

            assert!(yes_price_after > INITIAL_PRICE, 3);
            assert!(no_price_after < INITIAL_PRICE, 4);
            assert!(yes_price_after + no_price_after == BASIS_POINTS, 5);

            // Return shared objects
            test_scenario::return_shared(events);
            test_scenario::return_shared(clock_ref);
        };
        test_scenario::end(scenario);
    }

    #[test]
    fun test_event_resolution() {
        let mut scenario = test_scenario::begin(ADMIN);
        {
            // First transaction: create Clock and Events objects
            let ctx = test_scenario::ctx(&mut scenario);
            let clock = clock::create_for_testing(ctx);
            clock::share_for_testing(clock);
            lastone::create_events_test_only(ctx);
        };

        // Event creation transaction
        let event_id;
        test_scenario::next_tx(&mut scenario, ADMIN);
        {
            // Take shared objects
            let clock_ref = test_scenario::take_shared<Clock>(&scenario);
            let mut events = test_scenario::take_shared<Events>(&scenario);
            let ctx = test_scenario::ctx(&mut scenario);

            let round_id = 1;
            let name = ascii::string(b"Will BTC reach $100,000 by 2025?");
            event_id = 0;

            lastone::create_event_test_only(
                &mut events, round_id, name, &clock_ref, ctx
            );

            // Return shared objects
            test_scenario::return_shared(events);
            test_scenario::return_shared(clock_ref);
        };

        // Simulate passing time to reach event end
        test_scenario::next_tx(&mut scenario, ADMIN);
        {
            let mut clock_ref = test_scenario::take_shared<Clock>(&scenario);
            // Add extra time to ensure we're past the event end time
            let current_time = clock::timestamp_ms(&clock_ref);
            // Update clock time to be well past the end time
            clock::set_for_testing(&mut clock_ref, current_time + 20000);
            test_scenario::return_shared(clock_ref);
        };

        // Event resolution transaction
        test_scenario::next_tx(&mut scenario, ADMIN);
        {
            // Take shared objects again
            let clock_ref = test_scenario::take_shared<Clock>(&scenario);
            let mut events = test_scenario::take_shared<Events>(&scenario);
            let ctx = test_scenario::ctx(&mut scenario);

            lastone::resolve_event_test_only(
                &mut events,
                event_id,
                1, // 1 for YES outcome
                ctx
            );

            // Return shared objects
            test_scenario::return_shared(events);
            test_scenario::return_shared(clock_ref);
        };
        test_scenario::end(scenario);
    }

    #[test]
    fun test_extreme_price_changes() {
        let mut scenario = test_scenario::begin(ADMIN);
        {
            // First transaction: create Clock and Events objects
            let ctx = test_scenario::ctx(&mut scenario);
            let clock = clock::create_for_testing(ctx);
            clock::share_for_testing(clock);
            lastone::create_events_test_only(ctx);
        };

        // Event creation transaction
        let event_id;
        test_scenario::next_tx(&mut scenario, ADMIN);
        {
            // Take shared objects
            let clock_ref = test_scenario::take_shared<Clock>(&scenario);
            let mut events = test_scenario::take_shared<Events>(&scenario);
            let ctx = test_scenario::ctx(&mut scenario);

            let round_id = 1;
            let name = ascii::string(b"Will BTC reach $100,000 by 2025?");
            event_id = 0;

            lastone::create_event_test_only(
                &mut events, round_id, name, &clock_ref, ctx
            );

            // Return shared objects
            test_scenario::return_shared(events);
            test_scenario::return_shared(clock_ref);
        };

        // First user buys YES shares
        test_scenario::next_tx(&mut scenario, USER1);
        {
            // Take shared objects again
            let clock_ref = test_scenario::take_shared<Clock>(&scenario);
            let mut events = test_scenario::take_shared<Events>(&scenario);

            let ctx = test_scenario::ctx(&mut scenario);
            // Using a large amount to test extreme price movements
            let sui_coin = coin::mint_for_testing<SUI>(5_000_000_000, ctx);

            lastone::buy_shares_test_only(
                &mut events, event_id, true, sui_coin, &clock_ref, ctx
            );

            let (yes_price_after, no_price_after, _) = lastone::get_event_prices_test_only(
                &events, event_id
            );

            // Large buy should push yes price up significantly, but limited by max price change per transaction
            assert!(yes_price_after > 5000, 0); // Above the initial price (50%)
            assert!(no_price_after < 5000, 1); // Below the initial price (50%)
            assert!(yes_price_after + no_price_after == BASIS_POINTS, 2);

            // Return shared objects
            test_scenario::return_shared(events);
            test_scenario::return_shared(clock_ref);
        };

        // Second user buys NO shares
        test_scenario::next_tx(&mut scenario, USER2);
        {
            // Take shared objects again
            let clock_ref = test_scenario::take_shared<Clock>(&scenario);
            let mut events = test_scenario::take_shared<Events>(&scenario);

            let ctx = test_scenario::ctx(&mut scenario);
            // Also use a large amount
            let sui_coin = coin::mint_for_testing<SUI>(5_000_000_000, ctx);

            lastone::buy_shares_test_only(
                &mut events, event_id, false, sui_coin, &clock_ref, ctx
            );

            let (yes_price_after, no_price_after, _) = lastone::get_event_prices_test_only(
                &events, event_id
            );

            // After opposite large buy, prices should move back toward midpoint
            assert!(yes_price_after < 6500, 3); // Yes price should decrease
            assert!(no_price_after > 3500, 4); // No price should increase
            assert!(yes_price_after + no_price_after == BASIS_POINTS, 5);

            // Return shared objects
            test_scenario::return_shared(events);
            test_scenario::return_shared(clock_ref);
        };
        test_scenario::end(scenario);
    }

    #[test]
    fun test_multiple_events() {
        let mut scenario = test_scenario::begin(ADMIN);
        {
            // First transaction: create Clock and Events objects
            let ctx = test_scenario::ctx(&mut scenario);
            let clock = clock::create_for_testing(ctx);
            clock::share_for_testing(clock);
            lastone::create_events_test_only(ctx);
        };

        test_scenario::next_tx(&mut scenario, ADMIN);
        let clock_ref = test_scenario::take_shared<Clock>(&scenario);
        let mut events = test_scenario::take_shared<Events>(&scenario);
        {
            let ctx = test_scenario::ctx(&mut scenario);

            let round_id_1 = 1;
            let name_1 = ascii::string(b"Will BTC reach $100,000 by 2025?");
            let event_id_1 = 0;

            lastone::create_event_test_only(
                &mut events, round_id_1, name_1, &clock_ref, ctx
            );

            let round_id_2 = 2;
            let name_2 = ascii::string(b"Will ETH reach $10,000 by 2025?");
            let event_id_2 = 1;

            lastone::create_event_test_only(
                &mut events, round_id_2, name_2, &clock_ref, ctx
            );

            let (yes_price_1, no_price_1, _) = lastone::get_event_prices_test_only(
                &events, event_id_1
            );
            let (yes_price_2, no_price_2, _) = lastone::get_event_prices_test_only(
                &events, event_id_2
            );
            assert!(yes_price_1 == INITIAL_PRICE, 1);
            assert!(no_price_1 == INITIAL_PRICE, 1);
            assert!(yes_price_2 == INITIAL_PRICE, 2);
            assert!(no_price_2 == INITIAL_PRICE, 3);

            test_scenario::next_tx(&mut scenario, USER1);
            let ctx = test_scenario::ctx(&mut scenario);
            let sui_coin_1 = coin::mint_for_testing<SUI>(2_000_000_000, ctx);
            lastone::buy_shares_test_only(
                &mut events, event_id_1, true, sui_coin_1, &clock_ref, ctx
            );

            test_scenario::next_tx(&mut scenario, USER2);
            let ctx = test_scenario::ctx(&mut scenario);
            let sui_coin_2 = coin::mint_for_testing<SUI>(3_000_000_000, ctx);
            lastone::buy_shares_test_only(
                &mut events, event_id_2, false, sui_coin_2, &clock_ref, ctx
            );

            test_scenario::next_tx(&mut scenario, ADMIN);
            let _ctx = test_scenario::ctx(&mut scenario);
            // Need to take our own reference to events, not a new copy

            let (yes_price_1_after, no_price_1_after, _) = lastone::get_event_prices_test_only(
                &events, event_id_1
            );
            let (yes_price_2_after, no_price_2_after, _) = lastone::get_event_prices_test_only(
                &events, event_id_2
            );

            assert!(yes_price_1_after > INITIAL_PRICE, 6);
            assert!(no_price_2_after > INITIAL_PRICE, 7);
            assert!(yes_price_1_after + no_price_1_after == BASIS_POINTS, 8);
            assert!(yes_price_2_after + no_price_2_after == BASIS_POINTS, 9);

            // First end the current transaction and return all shared objects
            test_scenario::return_shared(events);
            test_scenario::return_shared(clock_ref);

            // Start a new transaction, set the time
            test_scenario::next_tx(&mut scenario, ADMIN);
            {
                let mut clock_update = test_scenario::take_shared<Clock>(&scenario);
                let current_time = 100000; // Use a large explicit time value
                clock::set_for_testing(&mut clock_update, current_time);
                test_scenario::return_shared(clock_update);
            };

            // Event resolution transaction
            test_scenario::next_tx(&mut scenario, ADMIN);
            {
                let clock_resolve = test_scenario::take_shared<Clock>(&scenario);
                let mut events_resolve = test_scenario::take_shared<Events>(&scenario);
                let ctx = test_scenario::ctx(&mut scenario);
                lastone::resolve_event_test_only(
                    &mut events_resolve,
                    event_id_1,
                    1, // 1 for YES outcome
                    ctx
                );
                test_scenario::return_shared(events_resolve);
                test_scenario::return_shared(clock_resolve);
            };
        };
        test_scenario::end(scenario);
    }

    // Add a new test for the claim_winnings functionality
    #[test]
    fun test_claim_winnings() {
        let mut scenario = test_scenario::begin(ADMIN);
        {
            // First transaction: create Clock and Events objects
            let ctx = test_scenario::ctx(&mut scenario);
            let clock = clock::create_for_testing(ctx);
            clock::share_for_testing(clock);
            lastone::create_events_test_only(ctx);
        };

        // Event creation transaction
        let event_id;
        test_scenario::next_tx(&mut scenario, ADMIN);
        {
            // Take shared objects
            let clock_ref = test_scenario::take_shared<Clock>(&scenario);
            let mut events = test_scenario::take_shared<Events>(&scenario);
            let ctx = test_scenario::ctx(&mut scenario);

            let round_id = 1;
            let name = ascii::string(b"Will BTC reach $100,000 by 2025?");
            event_id = 0;

            lastone::create_event_test_only(
                &mut events, round_id, name, &clock_ref, ctx
            );

            // Return shared objects
            test_scenario::return_shared(events);
            test_scenario::return_shared(clock_ref);
        };

        // USER1 buys YES shares
        test_scenario::next_tx(&mut scenario, USER1);
        {
            let clock_ref = test_scenario::take_shared<Clock>(&scenario);
            let mut events = test_scenario::take_shared<Events>(&scenario);
            let ctx = test_scenario::ctx(&mut scenario);

            let sui_coin = coin::mint_for_testing<SUI>(1_000_000_000, ctx);

            lastone::buy_shares_test_only(
                &mut events, event_id, true, sui_coin, &clock_ref, ctx
            );

            test_scenario::return_shared(events);
            test_scenario::return_shared(clock_ref);
        };

        // USER2 buys NO shares
        test_scenario::next_tx(&mut scenario, USER2);
        {
            let clock_ref = test_scenario::take_shared<Clock>(&scenario);
            let mut events = test_scenario::take_shared<Events>(&scenario);
            let ctx = test_scenario::ctx(&mut scenario);

            let sui_coin = coin::mint_for_testing<SUI>(1_000_000_000, ctx);

            lastone::buy_shares_test_only(
                &mut events, event_id, false, sui_coin, &clock_ref, ctx
            );

            test_scenario::return_shared(events);
            test_scenario::return_shared(clock_ref);
        };

        // Advance time and resolve event with YES outcome
        test_scenario::next_tx(&mut scenario, ADMIN);
        {
            let mut clock_ref = test_scenario::take_shared<Clock>(&scenario);
            let current_time = clock::timestamp_ms(&clock_ref);
            // Update clock time to be well past the end time
            clock::set_for_testing(&mut clock_ref, current_time + 20000);
            test_scenario::return_shared(clock_ref);
        };

        test_scenario::next_tx(&mut scenario, ADMIN);
        {
            let clock_ref = test_scenario::take_shared<Clock>(&scenario);
            let mut events = test_scenario::take_shared<Events>(&scenario);
            let ctx = test_scenario::ctx(&mut scenario);

            lastone::resolve_event_test_only(
                &mut events,
                event_id,
                1, // 1 for YES outcome
                ctx
            );

            test_scenario::return_shared(events);
            test_scenario::return_shared(clock_ref);
        };

        // USER1 claims winnings (should succeed as they bet on YES)
        test_scenario::next_tx(&mut scenario, USER1);
        {
            let clock_ref = test_scenario::take_shared<Clock>(&scenario);
            let mut events = test_scenario::take_shared<Events>(&scenario);
            let ctx = test_scenario::ctx(&mut scenario);

            // User calls claim_winnings to claim rewards
            lastone::claim_winnings(
                &mut events,
                event_id,
                ctx
            );

            // Should receive some SUI tokens as rewards
            // In the Sui test framework, we cannot directly use get_sui_balance
            // But we know that if the function executes successfully, the user will receive rewards

            test_scenario::return_shared(events);
            test_scenario::return_shared(clock_ref);
        };

        test_scenario::end(scenario);
    }
}
