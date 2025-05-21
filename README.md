# LastOne - A Prediction Market Platform on Sui

[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

## Overview

LastOne is a decentralized prediction market platform built on the Sui blockchain. It allows users to create, participate in, and resolve prediction events by betting on the outcomes ("Yes" or "No"). The platform uses a dynamic pricing mechanism based on liquidity pools to reflect the market's belief in each outcome's probability.

## Features

- **Event Creation**: Administrators can create prediction events with a specified round ID, name, and duration.
- **Betting**: Users can buy shares representing "Yes" or "No" outcomes for an event, with prices adjusting dynamically based on the amount bet and existing liquidity.
- **Selling Shares**: Users can sell their shares back to the pool before the event resolves, receiving SUI based on current prices.
- **Event Resolution**: After an event's end time, administrators can resolve it by declaring the final outcome ("Yes" or "No").
- **Winnings Claim**: Users who bet on the correct outcome can claim their proportional share of the total liquidity pool after resolution.

## Contract Structure

### Core Components

- **Events**: A shared object that manages all prediction events and user positions.
  - `next_event_id_counter`: Auto-incrementing ID for new events.
  - `events`: A table mapping event IDs to `Event` structs.
  - `positions`: A table mapping user addresses to their positions in various events.
- **Event**: Represents a single prediction event.
  - `round_id`: Identifier for the game round.
  - `name`: Descriptive name of the event.
  - `end_time`: Timestamp when the event ends.
  - `yes_price` & `no_price`: Current prices (in basis points) for "Yes" and "No" outcomes, summing to 100%.
  - `status`: Current state of the event (Active or Resolved).
  - `resolved_outcome`: Final outcome after resolution (1 for Yes, 2 for No).
  - `yes_shares` & `no_shares`: Total shares issued for each outcome.
  - `yes_liquidity` & `no_liquidity`: SUI balances for each outcome pool.
  - `total_liquidity`: Total SUI locked in the event.
  - `creator`: Address of the event creator.
- **UserPosition**: Tracks a user's shares in a specific event.
  - `yes_shares`: Number of "Yes" shares owned.
  - `no_shares`: Number of "No" shares owned.
- **AdminCap**: A capability object granting administrative privileges to manage the protocol.

### Key Functions

- **create_event**: Creates a new prediction event with a given round ID, name, and duration.
- **buy_shares**: Allows users to buy shares for "Yes" or "No" outcomes, adjusting prices based on the bet size relative to liquidity.
- **sell_shares**: Enables users to sell their shares back to the pool before the event resolves.
- **resolve_event**: Allows administrators to set the final outcome of an event after its end time.
- **claim_winnings**: Lets users claim their winnings from resolved events if they bet on the correct outcome.
- **get_events_list**: Retrieves a paginated list of events with their details.
- **get_user_position**: Returns a user's share holdings for a specific event.
- **get_event_prices**: Fetches the current prices and total liquidity for an event.

## Pricing Mechanism

LastOne uses an Automated Market Maker (AMM) style pricing model:

- Initial prices for "Yes" and "No" are set at 50% each (5000 basis points).
- Prices adjust based on the ratio of bets placed and a virtual liquidity constant to prevent extreme price swings.
- Buying shares for one outcome increases its price and decreases the other, reflecting market sentiment.
- The sum of "Yes" and "No" prices always equals 100% (10000 basis points).

## Getting Started

### Prerequisites

- Sui CLI installed and configured.
- A Sui wallet with some SUI tokens for gas fees and betting.

### Deployment

1. Clone the repository:

   ```bash
   git clone https://github.com/lastone-games/lastone.git
   cd lastone
   ```

3. Build and publish the contract:

   ```bash
   sui client publish --gas-budget 100000000
   ```

   Save the published package ID for interaction.

4. Initialize the protocol (run once after publishing):

   - Use a script or client to call the `init` function, which creates the shared `Events` object and transfers the `AdminCap` to the deployer.

### Usage

#### Creating an Event

Administrators can create events using the `create_event` function, specifying the round ID, event name, and duration in minutes.

#### Betting on an Event

1. Fetch the list of active events using `get_events_list`.
2. Choose an event and check its current prices with `get_event_prices`.
3. Call `buy_shares` with the event ID, whether to bet on "Yes" or "No", and the SUI amount to bet.

#### Selling Shares

Before an event resolves, users can sell their shares using `sell_shares`, specifying the event ID, outcome type, and number of shares to sell.

#### Resolving an Event

After the event's end time, administrators can call `resolve_event` with the event ID and the final outcome (1 for Yes, 2 for No).

#### Claiming Winnings

Post-resolution, users who bet on the winning outcome can call `claim_winnings` with the event ID to receive their share of the pool.

## Development

### Testing

Run the test suite to verify contract functionality:

```bash
sui move test
```

### Contributing

Contributions are welcome! Please fork the repository, make your changes, and submit a pull request.

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
