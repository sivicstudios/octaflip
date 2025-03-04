use octa_flip::models::{Game, GameCounter, PlayerAtPosition, PlayerInGame, Tile};
use starknet::ContractAddress;

// define the interface
#[starknet::interface]
pub trait IActions<T> {
    fn create_game(ref self: T) -> u64;
    fn join_game(ref self: T, game_id: u64);
    fn start_game(ref self: T, game_id: u64);
    fn claim_tile(ref self: T, game_id: u64, x: u8, y: u8);
    fn game_winner(self: @T, game_id: u64) -> ContractAddress;
    fn start_and_end_time(self: @T, game_id: u64) -> (u64, u64);
    fn players_tiles_flipped(self: @T, game_id: u64) -> (u8, u8);
}

// dojo decorator
#[dojo::contract]
pub mod actions {
    use super::{IActions, Game, GameCounter, PlayerAtPosition, PlayerInGame, Tile};
    use starknet::{ContractAddress, get_caller_address, get_block_timestamp};
    use octa_flip::utils::{zero_address};
    use octa_flip::constants::{GRID_SIZE, PVP};
    use octa_flip::utils::{bitmask_session, unmask_session};

    use dojo::model::ModelStorage;
    use dojo::event::EventStorage;

    /// Event emitted when a game is created.
    #[derive(Copy, Drop, Serde)]
    #[dojo::event]
    pub struct GameCreated {
        #[key]
        pub game_id: u64,
        pub board_width: u8,
        pub board_height: u8,
        pub number_of_players: u8,
    }

    /// Event emitted when a player joins a game.
    #[derive(Copy, Drop, Serde)]
    #[dojo::event]
    pub struct PlayerJoined {
        #[key]
        pub game_id: u64,
        #[key]
        pub player_id: u8,
        #[key]
        pub player_address: ContractAddress,
        pub timestamp: u64,
    }

    /// Event emitted when a game starts.
    #[derive(Copy, Drop, Serde)]
    #[dojo::event]
    pub struct GameStarted {
        #[key]
        pub game_id: u64,
        #[key]
        pub start_time: u64,
        pub timestamp: u64,
    }

    /// Event emitted when a game ends.
    #[derive(Copy, Drop, Serde)]
    #[dojo::event]
    pub struct GameEnded {
        #[key]
        pub game_id: u64,
        #[key]
        pub end_time: u64,
        #[key]
        pub winner: ContractAddress,
        pub timestamp: u64,
    }

    /// Event emitted when a player claims a tile.
    #[derive(Copy, Drop, Serde)]
    #[dojo::event]
    pub struct TileClaim {
        #[key]
        pub game_id: u64,
        #[key]
        pub player: ContractAddress,
        #[key]
        pub x: u8,
        #[key]
        pub y: u8,
        pub timestamp: u64,
    }

    #[abi(embed_v0)]
    impl ActionsImpl of IActions<ContractState> {
        /// Creates a new game instance.
        ///
        /// This function initializes a new game with default settings, assigns a unique ID,
        /// and stores the game data. It also emits a `GameCreated` event to notify listeners
        /// that a new game has been created.
        ///
        /// # Arguments
        ///
        /// * `self`: A mutable reference to the `ContractState`.  This allows the function
        ///   to access and modify the contract's storage.
        ///
        /// # Returns
        ///
        /// This function doesn't explicitly return a value.  It modifies the contract state
        /// and emits an event.
        ///
        /// # Events
        ///
        /// * `GameCreated`: Emitted when a new game is successfully created.  Includes
        ///   the `game_id`, `board_width`, `board_height`, and `number_of_players`.
        fn create_game(ref self: ContractState) -> u64 {
            let mut world = self.world_default();
            let game_id = self.game_uid();

            let new_game = Game {
                id: game_id,
                board_width: GRID_SIZE,
                board_height: GRID_SIZE,
                number_of_players: 0,
                data: 'PENDING',
                is_live: false,
                //winner: zero_address(), // If winner state should be tracked.
            };

            world.write_model(@new_game);

            world
                .emit_event(
                    @GameCreated {
                        game_id,
                        board_width: GRID_SIZE,
                        board_height: GRID_SIZE,
                        number_of_players: 0,
                    },
                );
            game_id
        }

        /// Allows a player to join a game.
        ///
        /// This function adds a player to a game, ensuring that the game has not yet started,
        /// is not full, and that the player's address is not already in the game. It updates
        /// the game's player count and stores the player's information.  It also emits a
        /// `PlayerJoined` event.
        ///
        /// # Arguments
        ///
        /// * `self`: A mutable reference to the `ContractState`.
        /// * `game_id`: The ID of the game to join.
        ///
        /// # Panics
        ///
        /// * If the game has already started.
        /// * If the game is full.
        /// * If the game does not exist.
        /// * If the player's address is already in the game.
        ///
        /// # Events
        ///
        /// * `PlayerJoined`: Emitted when a player successfully joins a game.  Includes
        ///   the `game_id`, `player_address`, and `player_id`.
        fn join_game(ref self: ContractState, game_id: u64) {
            let mut world = self.world_default();
            let player_address = get_caller_address();

            let mut game: Game = world.read_model(game_id);
            assert(game.board_width != 0, 'Game Does Not Exist');
            assert(!game.is_live, 'Game already started');
            assert(game.number_of_players < PVP, 'Game is full');

            game.number_of_players += 1;
            let player_id = game.number_of_players;

            // Check for duplicate player addresses *before* writing the new player.
            if player_id > 1 {
                let player_one: PlayerInGame = world.read_model((game_id, 1));
                assert(player_one.player_address != player_address, 'Address cannot be same');
            }

            let new_player = PlayerInGame { player_address, game_id, player_id };
            world.write_model(@new_player);
            world.write_model(@game);

            world
                .emit_event(
                    @PlayerJoined {
                        game_id, player_address, player_id, timestamp: get_block_timestamp(),
                    },
                );
        }

        // Open ended question, who should start the game?
        /// Starts a game.
        ///
        /// This function initiates a game, ensuring that the required number of players have joined
        /// and that the game has not already started. It sets the game's `is_live` flag to `true`,
        /// generates game data using `bitmask_session`, and records the start time. It also emits
        /// a `GameStarted` event.
        ///
        /// # Arguments
        ///
        /// * `self`: A mutable reference to the `ContractState`.
        /// * `game_id`: The ID of the game to start.
        ///
        /// # Panics
        ///
        /// * If the game does not have the required number of players (PVP).
        /// * If the game data is invalid (not 'PENDING').
        /// * If the game has already started.
        /// * If there's an error calculating the session end time.
        ///
        /// # Events
        ///
        /// * `GameStarted`: Emitted when a game is successfully started. Includes the
        ///   `game_id` and `start_time`.
        fn start_game(ref self: ContractState, game_id: u64) {
            let mut world = self.world_default();
            let mut game: Game = world.read_model(game_id);

            assert(game.number_of_players == PVP, 'Need 2 players to start');
            assert(!game.is_live, 'Game already started');
            assert(game.data == 'PENDING', 'Invalid Game Data');

            let start_time = get_block_timestamp();
            let end_time = start_time + (3 * 60);

            assert(end_time > start_time, 'Session Error');

            game.data = bitmask_session(start_time, end_time);
            game.is_live = true;

            world.write_model(@game);

            world
                .emit_event(@GameStarted { game_id, start_time, timestamp: get_block_timestamp() });
        }

        /// Claims a tile on the game board.
        ///
        /// This function allows a player to claim a tile on the game board during a live game.
        /// It checks if the game is ongoing, if the coordinates are within bounds, and if the
        /// player is part of the game. It then records the tile claim and emits a `TileClaim`
        /// event. If the game time has expired, it determines the winner, ends the game, and
        /// emits a `GameEnded` event.
        ///
        /// # Arguments
        ///
        /// * `self`: A mutable reference to the `ContractState`.
        /// * `game_id`: The ID of the game.
        /// * `x`: The x-coordinate of the tile to claim.
        /// * `y`: The y-coordinate of the tile to claim.
        ///
        /// # Panics
        ///
        /// * If the game has not started.
        /// * If the game has ended.
        /// * If the x or y coordinates are out of bounds.
        /// * If the player is not in the game.
        /// * If the player addresses are invalid.
        ///
        /// # Events
        ///
        /// * `TileClaim`: Emitted when a tile is successfully claimed. Includes the
        ///   `game_id`, `x`, `y`, and `player` (address).
        /// * `GameEnded`: Emitted when the game ends due to time expiration. Includes
        ///   the `game_id`, `end_time`, and `winner` (address).
        fn claim_tile(ref self: ContractState, game_id: u64, x: u8, y: u8) {
            let mut world = self.world_default();
            let mut game: Game = world.read_model(game_id);

            let (start_time, end_time) = unmask_session(game.data);
            let current_time = get_block_timestamp();

            assert(current_time >= start_time, 'Game has not started');

            if current_time >= end_time {
                let winner: ContractAddress = self.game_winner(game_id);
                game.is_live = false;
                game.data = 'ENDED';
                //game.winner = winner;
                world.write_model(@game);
                world
                    .emit_event(
                        @GameEnded { game_id, end_time, winner, timestamp: get_block_timestamp() },
                    );
                return;
            }

            assert(x < GRID_SIZE, 'X is out of bounds');
            assert(y < GRID_SIZE, 'Y is out of bounds');

            let player = get_caller_address();
            let player_one: PlayerInGame = world.read_model((game_id, 1));
            let player_two: PlayerInGame = world.read_model((game_id, 2));

            assert(
                player_one.player_address != zero_address()
                    || player_two.player_address != zero_address(),
                'Invalid player address',
            );
            assert(
                player_one.player_address == player || player_two.player_address == player,
                'Player not in game',
            );

            let player_at_position = PlayerAtPosition { game_id, x, y, player };
            let tile = Tile { x, y, game_id, claimed: player };

            world.write_model(@player_at_position);
            world.write_model(@tile);
            world
                .emit_event(@TileClaim { game_id, x, y, player, timestamp: get_block_timestamp() });
        }

        /// Determines the winner of a game.
        ///
        /// This function calculates the winner of a game by counting the number of tiles claimed
        /// by each player. It iterates through all the tiles on the board and checks which player
        /// has claimed each tile. The player with the most claimed tiles is declared the winner.
        /// If both players have claimed an equal number of tiles, or if no tiles have been claimed,
        /// the function returns the zero address, indicating a draw or an unfinished game.
        ///
        /// # Arguments
        ///
        /// * `self`: A reference to the `ContractState`.
        /// * `game_id`: The ID of the game.
        ///
        /// # Returns
        ///
        /// The address of the winning player, or the zero address if there is no winner (draw
        /// or unfinished game).
        ///
        /// # Panics
        ///
        /// * If either player's address is the zero address (meaning they are not in the game).
        fn game_winner(self: @ContractState, game_id: u64) -> ContractAddress {
            let (player_one_address, player_two_address) = self.players_in_game(game_id);
            let (player_one_tiles, player_two_tiles) = self.player_claimed_tiles_count(game_id);

            if player_one_tiles > player_two_tiles {
                player_one_address
            } else if player_two_tiles > player_one_tiles {
                player_two_address
            } else {
                zero_address()
            }
        }

        /// Returns the start and end time of a game.
        ///
        /// This function retrieves the start and end time of a game based on its ID.
        /// It provides a convenient way to access the game's time information.
        ///
        /// # Arguments
        ///
        /// * `self` - The contract state.
        /// * `game_id` - The ID of the game.
        ///
        /// # Returns
        ///
        /// A tuple containing the start and end time of the game.
        fn start_and_end_time(self: @ContractState, game_id: u64) -> (u64, u64) {
            let mut world = self.world_default();
            let mut game: Game = world.read_model(game_id);

            let (start_time, end_time) = unmask_session(game.data);
            (start_time, end_time)
        }

        /// Returns the number of tiles flipped by each player in a game.
        ///
        /// This function retrieves the number of tiles flipped by each player in a game based on
        /// its ID.
        /// It provides a convenient way to access the game's tile flip information.
        ///
        /// # Arguments
        ///
        /// * `self` - The contract state.
        /// * `game_id` - The ID of the game.
        ///
        /// # Returns
        ///
        /// A tuple containing the number of tiles flipped by player 1 and player 2.
        fn players_tiles_flipped(self: @ContractState, game_id: u64) -> (u8, u8) {
            let (player1_tiles, player2_tiles) = self.player_claimed_tiles_count(game_id);
            (player1_tiles, player2_tiles)
        }
    }

    #[generate_trait]
    impl InternalImpl of InternalTrait {
        /// Returns the default world storage for the contract.
        ///
        /// This function retrieves the world storage associated with the name "octa_flip".
        /// It provides a convenient way to access the contract's world data.
        ///
        /// # Arguments
        ///
        /// * `self`: A reference to the `ContractState`.
        ///
        /// # Returns
        ///
        /// A `dojo::world::WorldStorage` instance representing the contract's world.
        fn world_default(self: @ContractState) -> dojo::world::WorldStorage {
            self.world(@"octa_flip")
        }

        /// Generates a unique ID for a new game.
        ///
        /// This function retrieves the current game counter, increments it, and returns the new
        /// value as the unique game ID. It also updates the game counter in storage.
        ///
        /// # Arguments
        ///
        /// * `self`: A mutable reference to the `ContractState`.
        ///
        /// # Returns
        ///
        /// A unique `u64` representing the new game ID.
        fn game_uid(ref self: ContractState) -> u64 {
            let mut world = self.world_default();
            let mut game_counter: GameCounter = world.read_model('v0');
            let game_id = game_counter.current_val + 1;
            game_counter.current_val = game_id;
            world.write_model(@game_counter);
            game_id
        }

        /// Retrieves the address of the player who claimed a specific tile.
        ///
        /// This function reads the `Tile` model for the given coordinates and game ID and returns
        /// the address of the player who claimed that tile.
        ///
        /// # Arguments
        ///
        /// * `self`: A reference to the `ContractState`.
        /// * `game_id`: The ID of the game.
        /// * `x`: The x-coordinate of the tile.
        /// * `y`: The y-coordinate of the tile.
        ///
        /// # Returns
        ///
        /// The `ContractAddress` of the player who claimed the tile.
        fn player_at_position(self: @ContractState, game_id: u64, x: u8, y: u8) -> ContractAddress {
            let world = self.world_default();
            let tile: Tile = world.read_model((x, y, game_id));
            tile.claimed
        }

        /// This function reads the `PlayerInGame` model for the given game ID and returns
        /// the number of tiles claimed by each player.
        ///
        /// # Arguments
        ///
        /// * `self`: A reference to the `ContractState`.
        /// * `game_id`: The ID of the game.
        ///
        /// # Returns
        ///
        /// A tuple containing the number of tiles claimed by player one and player two.
        fn player_claimed_tiles_count(self: @ContractState, game_id: u64) -> (u8, u8) {
            let (player_one_address, player_two_address) = self.players_in_game(game_id);

            let mut player_one_tiles: u8 = 0;
            let mut player_two_tiles: u8 = 0;

            for i in 0..(GRID_SIZE * GRID_SIZE) {
                let x = i % GRID_SIZE;
                let y = i / GRID_SIZE;

                let player_at_position: ContractAddress = self.player_at_position(game_id, x, y);
                if player_at_position == player_one_address {
                    player_one_tiles += 1;
                } else if player_at_position == player_two_address {
                    player_two_tiles += 1;
                }
            };

            (player_one_tiles, player_two_tiles)
        }

        /// This function returns the addresses of the players in a game.
        ///
        /// # Arguments
        ///
        /// * `self` - The contract state.
        /// * `game_id` - The ID of the game.
        ///
        /// # Returns
        ///
        /// A tuple containing the addresses of the players in the game.
        fn players_in_game(
            self: @ContractState, game_id: u64,
        ) -> (ContractAddress, ContractAddress) {
            let world = self.world_default();
            let player_one: PlayerInGame = world.read_model((game_id, 1));
            let player_two: PlayerInGame = world.read_model((game_id, 2));

            assert(player_one.player_address != zero_address(), 'Player not in game');
            assert(player_two.player_address != zero_address(), 'Player not in game');

            (player_one.player_address, player_two.player_address)
        }
    }
}
