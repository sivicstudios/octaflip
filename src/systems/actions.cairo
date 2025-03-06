use octa_flip::models::{
    CompetitiveGame, Game, GameCounter, PlayerAtPosition, PlayerInCompetitiveGame, PlayerInGame,
    Tile, TileCompetitive,
};
use starknet::ContractAddress;

// define the interface
#[starknet::interface]
pub trait IActions<T> {
    /// Creates a new game instance.
    fn create_game(ref self: T) -> u64;

    /// Creates a new competitive game instance.
    ///
    /// # Arguments
    ///
    /// * `grid_size`: The size of the game grid (e.g., 8 for an 8x8 grid).
    /// * `duration`: The duration of the game in seconds.
    fn create_competitive_game(ref self: T, grid_size: u8, duration: u64) -> u64;

    /// Allows a player to join an existing game.
    fn join_game(ref self: T, game_id: u64);

    /// Allows a player to join an existing competitive game.
    fn join_competitive_game(ref self: T, game_id: u64);

    /// Starts a game, transitioning it from 'PENDING' to 'ONGOING'.
    fn start_game(ref self: T, game_id: u64);

    /// Starts a competitive game, transitioning it from 'WAITING' to 'ONGOING'.
    fn start_competitive_game(ref self: T, game_id: u64);

    /// Allows a player to claim a tile on the game board.
    fn claim_tile(ref self: T, game_id: u64, x: u8, y: u8);

    /// Allows a player to claim a tile on a competitive game board.
    fn claim_tile_competitive(ref self: T, game_id: u64, x: u8, y: u8);

    /// Determines the winner of a game.
    fn game_winner(self: @T, game_id: u64) -> ContractAddress;

    /// Determines the winner of a competitive game.
    fn competitive_game_winner(self: @T, game_id: u64) -> felt252;

    /// Retrieves the start and end times of a game.
    fn start_and_end_time(self: @T, game_id: u64) -> (u64, u64);

    /// Retrieves the number of tiles flipped by each player in a game.
    fn players_tiles_flipped(self: @T, game_id: u64) -> (u8, u8);
}

// dojo decorator
#[dojo::contract]
pub mod actions {
    use super::{
        IActions, CompetitiveGame, Game, GameCounter, PlayerAtPosition, PlayerInCompetitiveGame,
        PlayerInGame, Tile, TileCompetitive,
    };
    use starknet::{ContractAddress, get_caller_address, get_block_timestamp};
    use core::dict::Felt252Dict;
    use core::num::traits::Bounded;
    use octa_flip::utils::{zero_address};
    use octa_flip::constants::{ENDED, GRID_SIZE, PVP, ONGOING, WAITING};
    use octa_flip::utils::{bitmask_session, unmask_session, colors};

    use dojo::model::ModelStorage;
    use dojo::event::EventStorage;

    /// Event emitted when a new game is created.
    #[derive(Copy, Drop, Serde)]
    #[dojo::event]
    pub struct GameCreated {
        /// The unique identifier of the created game.
        #[key]
        pub game_id: u64,
        /// The width of the game board.
        pub board_width: u8,
        /// The height of the game board.
        pub board_height: u8,
        /// The initial number of players in the game (always 0).
        pub number_of_players: u8,
    }

    /// Event emitted when a player joins a game.
    #[derive(Copy, Drop, Serde)]
    #[dojo::event]
    pub struct PlayerJoined {
        /// The unique identifier of the game the player joined.
        #[key]
        pub game_id: u64,
        /// The unique ID assigned to the player within the game.
        #[key]
        pub player_id: u8,
        /// The contract address of the player who joined.
        #[key]
        pub player_address: ContractAddress,
        /// The block timestamp when the player joined.
        pub timestamp: u64,
    }

    /// Event emitted when a player joins a competitive game.
    #[derive(Copy, Drop, Serde)]
    #[dojo::event]
    pub struct CompetitivePlayerJoined {
        /// The unique identifier of the competitive game the player joined.
        #[key]
        pub game_id: u64,
        /// The contract address of the player who joined.
        #[key]
        pub player_address: ContractAddress,
        /// The color assigned to the player in the competitive game.
        pub color: felt252,
        /// The block timestamp when the player joined.
        pub timestamp: u64,
    }

    /// Event emitted when a game starts.
    #[derive(Copy, Drop, Serde)]
    #[dojo::event]
    pub struct GameStarted {
        /// The unique identifier of the started game.
        #[key]
        pub game_id: u64,
        /// The block timestamp when the game started.
        #[key]
        pub start_time: u64,
        /// The block timestamp when the event was emitted.
        pub timestamp: u64,
    }

    /// Event emitted when a game ends.
    #[derive(Copy, Drop, Serde)]
    #[dojo::event]
    pub struct GameEnded {
        /// The unique identifier of the ended game.
        #[key]
        pub game_id: u64,
        /// The block timestamp when the game ended.
        #[key]
        pub end_time: u64,
        /// The contract address of the game's winner.
        #[key]
        pub winner: ContractAddress,
        /// The block timestamp when the event was emitted.
        pub timestamp: u64,
    }

    /// Event emitted when a competitive game ends.
    #[derive(Copy, Drop, Serde)]
    #[dojo::event]
    pub struct CompetitiveGameEnded {
        /// The unique identifier of the ended competitive game.
        #[key]
        pub game_id: u64,
        /// The block timestamp when the competitive game ended.
        #[key]
        pub end_time: u64,
        /// The color of the winning player in the competitive game.
        #[key]
        pub winner: felt252,
        /// The block timestamp when the event was emitted.
        pub timestamp: u64,
    }

    /// Event emitted when a tile is claimed by a player.
    #[derive(Copy, Drop, Serde)]
    #[dojo::event]
    pub struct TileClaim {
        /// The unique identifier of the game in which the tile was claimed.
        #[key]
        pub game_id: u64,
        /// The contract address of the player who claimed the tile.
        #[key]
        pub player: ContractAddress,
        /// The x-coordinate of the claimed tile.
        #[key]
        pub x: u8,
        /// The y-coordinate of the claimed tile.
        #[key]
        pub y: u8,
        /// The block timestamp when the tile was claimed.
        pub timestamp: u64,
    }

    #[abi(embed_v0)]
    impl ActionsImpl of IActions<ContractState> {
        /// Creates a new game instance.
        ///
        /// This function performs the following actions:
        /// 1.  Retrieves a unique game ID.
        /// 2.  Creates a new `Game` model with default values, including the game ID, grid size,
        /// and initial status.
        /// 3.  Writes the new `Game` model to the world state.
        /// 4.  Emits a `GameCreated` event.
        /// 5.  Returns the generated game ID.
        ///
        /// # Arguments
        ///
        /// * `self`: A mutable reference to the contract's state.
        ///
        /// # Returns
        ///
        /// The unique identifier (`u64`) of the newly created game.
        ///
        /// # Events
        ///
        /// Emits a `GameCreated` event with the following data:
        /// * `game_id`: The ID of the created game.
        /// * `board_width`: The width of the game board.
        /// * `board_height`: The height of the game board.
        /// * `number_of_players`: The initial number of players (0).
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

        /// Creates a new competitive game with the given grid size and duration.
        ///
        /// This function initializes a new competitive game with default settings, assigns a unique
        /// ID, and stores the game data. It also emits a `GameCreated` event to notify listeners
        /// that a new game has been created.
        ///
        /// # Arguments
        ///
        /// * `self`: A mutable reference to the `ContractState`. This allows the function
        ///   to access and modify the contract's storage.
        /// * `grid_size`: The size of the game board in both width and height.
        /// * `duration`: The duration of the game in seconds.
        ///
        /// # Returns
        ///
        /// The ID of the newly created game.
        ///
        /// # Events
        ///
        /// * `GameCreated`: Emitted when a new game is successfully created.  Includes
        ///   the `game_id`, `board_width`, `board_height`, and `number_of_players`.
        fn create_competitive_game(ref self: ContractState, grid_size: u8, duration: u64) -> u64 {
            let mut world = self.world_default();
            let game_id = self.game_uid();

            assert(duration > 0, 'Invalid Game Session');

            let grid_size = match grid_size == 0 || grid_size > Bounded::<u8>::MAX {
                true => GRID_SIZE,
                false => grid_size,
            };

            let new_game: CompetitiveGame = CompetitiveGame {
                id: game_id,
                board_width: grid_size,
                board_height: grid_size,
                number_of_players: 0,
                status: WAITING,
                is_live: false,
                starts_at: 0,
                ends_at: 0,
                pilot: get_caller_address(),
                duration,
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

        /// Allows a player to join an existing game.
        ///
        /// This function performs the following actions:
        /// 1.  Retrieves the game state and player address.
        /// 2.  Validates that the game exists, has not started, and is not full.
        /// 3.  Increments the game's player count and assigns a unique player ID.
        /// 4.  Checks if the player address is already in the game to prevent duplicates.
        /// 5.  Creates a new `PlayerInGame` model with the player's information.
        /// 6.  Writes the updated game state and player model to the world state.
        /// 7.  Emits a `PlayerJoined` event.
        ///
        /// # Arguments
        ///
        /// * `self`: A mutable reference to the contract's state.
        /// * `game_id`: The unique identifier of the game to join.
        ///
        /// # Panics
        ///
        /// This function panics if:
        /// * The game with the given `game_id` does not exist (board_width is 0).
        /// * The game has already started (is_live is true).
        /// * The game is full (number_of_players >= PVP).
        /// * The player address is already in the game.
        ///
        /// # Events
        ///
        /// Emits a `PlayerJoined` event with the following data:
        /// * `game_id`: The ID of the game.
        /// * `player_address`: The address of the player who joined.
        /// * `player_id`: The unique ID assigned to the player within the game.
        /// * `timestamp`: The block timestamp when the player joined.
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

        /// Allows a player to join a competitive game.
        ///
        /// This function performs the following actions:
        /// 1.  Retrieves the game state and player address.
        /// 2.  Validates that the game exists and is in the 'WAITING' status.
        /// 3.  Checks if the player has already joined the game.
        /// 4.  Assigns a unique color to the player based on the game's current player count.
        /// 5.  Creates or updates a `PlayerInCompetitiveGame` model with the player's information.
        /// 6.  Increments the game's player count.
        /// 7.  Emits a `CompetitivePlayerJoined` event.
        ///
        /// # Arguments
        ///
        /// * `self`: A mutable reference to the contract's state.
        /// * `game_id`: The unique identifier of the game to join.
        ///
        /// # Panics
        ///
        /// This function panics if:
        /// * The game with the given `game_id` does not exist (board_width is 0).
        /// * The game is not in the `WAITING` status.
        /// * The player has already joined the game.
        ///
        /// # Events
        ///
        /// Emits a `CompetitivePlayerJoined` event with the following data:
        /// * `game_id`: The ID of the game.
        /// * `player_address`: The address of the player who joined.
        /// * `color`: The color assigned to the player.
        /// * `timestamp`: The block timestamp when the player joined.
        fn join_competitive_game(ref self: ContractState, game_id: u64) {
            let mut world = self.world_default();
            let player_address = get_caller_address();

            let mut game: CompetitiveGame = world.read_model(game_id);
            assert(game.board_width != 0, 'Game Does Not Exist');
            assert(game.status == WAITING, 'Game not in Session');

            let player: PlayerInCompetitiveGame = world.read_model((game_id, player_address));
            assert(!player.joined, 'Already Joined');

            let colors = colors();
            let colorindex: u32 = (game.number_of_players % colors.len().into())
                .try_into()
                .unwrap();
            let color = *colors.at(colorindex);

            let player = PlayerInCompetitiveGame { game_id, player_address, color, joined: true };
            world.write_model(@player);

            game.number_of_players += 1;
            world.write_model(@game);

            world
                .emit_event(
                    @CompetitivePlayerJoined {
                        game_id, player_address, color, timestamp: get_block_timestamp(),
                    },
                );
        }

        // Open ended question, who should start the game?
        /// Starts a game, transitioning it from 'PENDING' to 'ONGOING'.
        ///
        /// This function performs the following actions:
        /// 1.  Retrieves the game state.
        /// 2.  Validates that the game has exactly two players.
        /// 3.  Checks if the game has not already started and has 'PENDING' data.
        /// 4.  Calculates the start and end times for the game session. The duration is set to 3
        /// minutes.
        /// 5.  Updates the game's data with the session information (start and end times) and sets
        /// 'is_live' to true.
        /// 6.  Emits a `GameStarted` event.
        ///
        /// # Arguments
        ///
        /// * `self`: A mutable reference to the contract's state.
        /// * `game_id`: The unique identifier of the game to start.
        ///
        /// # Panics
        ///
        /// This function panics if:
        /// * The game does not have exactly two players.
        /// * The game has already started.
        /// * The game's data is not 'PENDING'.
        /// * The calculated end time is not greater than the start time (invalid duration).
        ///
        /// # Events
        ///
        /// Emits a `GameStarted` event with the following data:
        /// * `game_id`: The ID of the started game.
        /// * `start_time`: The block timestamp when the game started.
        /// * `timestamp`: The block timestamp when the event was emitted.
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

        /// Starts a competitive game, transitioning it from 'WAITING' to 'ONGOING'.
        ///
        /// This function performs the following actions:
        /// 1.  Retrieves the game state.
        /// 2.  Validates that there are at least two players in the game.
        /// 3.  Checks if the game is in the 'WAITING' status.
        /// 4.  Verifies that the caller is the game's pilot (creator).
        /// 5.  Calculates the start and end times for the game session.
        /// 6.  Updates the game's status to 'ONGOING' and sets 'is_live' to true.
        /// 7.  Emits a `GameStarted` event.
        ///
        /// # Arguments
        ///
        /// * `self`: A mutable reference to the contract's state.
        /// * `game_id`: The unique identifier of the game to start.
        ///
        /// # Panics
        ///
        /// This function panics if:
        /// * The game has fewer than two players.
        /// * The game is not in the `WAITING` status.
        /// * The caller is not the game's pilot.
        /// * The calculated end time is not greater than the start time (invalid duration).
        ///
        /// # Events
        ///
        /// Emits a `GameStarted` event with the following data:
        /// * `game_id`: The ID of the started game.
        /// * `start_time`: The block timestamp when the game started.
        /// * `timestamp`: The block timestamp when the event was emitted.
        fn start_competitive_game(ref self: ContractState, game_id: u64) {
            let mut world = self.world_default();
            let mut game: CompetitiveGame = world.read_model(game_id);

            let game_status = game.status;
            assert(game.number_of_players > 1, 'At least two players');
            assert(game_status == WAITING, 'Game not in Session');
            assert(game.pilot == get_caller_address(), 'Invalid Caller');

            let starts_at = get_block_timestamp();
            let ends_at = starts_at + game.duration;
            assert(ends_at > starts_at, 'Invalid Game Session');

            game.status = ONGOING;
            game.is_live = true;
            game.starts_at = starts_at;
            game.ends_at = ends_at;

            world.write_model(@game);

            world
                .emit_event(
                    @GameStarted {
                        game_id, start_time: starts_at, timestamp: get_block_timestamp(),
                    },
                );
        }

        /// Allows a player to claim a tile on the game board.
        ///
        /// This function performs the following actions:
        /// 1.  Retrieves the game state and extracts the start and end times from the game's data.
        /// 2.  Checks if the game has started and is currently ongoing.
        /// 3.  If the game has ended, it calculates the winner, updates the game status, and emits
        /// a `GameEnded` event.
        /// 4.  If the game is ongoing, it validates that the given tile coordinates are within the
        /// board's bounds.
        /// 5.  Checks if the caller is a player in the game.
        /// 6.  Creates or updates `PlayerAtPosition` and `Tile` models to record the tile claim.
        /// 7.  Emits a `TileClaim` event.
        ///
        /// # Arguments
        ///
        /// * `self`: A mutable reference to the contract's state.
        /// * `game_id`: The unique identifier of the game.
        /// * `x`: The x-coordinate of the tile to claim.
        /// * `y`: The y-coordinate of the tile to claim.
        ///
        /// # Panics
        ///
        /// This function panics if:
        /// * The game has not started.
        /// * The given tile coordinates are out of bounds.
        /// * Neither player one nor player two has a valid address.
        /// * The caller is not a player in the game.
        ///
        /// # Events
        ///
        /// Emits a `TileClaim` event with the following data:
        /// * `game_id`: The ID of the game.
        /// * `x`: The x-coordinate of the claimed tile.
        /// * `y`: The y-coordinate of the claimed tile.
        /// * `player`: The address of the player who claimed the tile.
        /// * `timestamp`: The block timestamp when the tile was claimed.
        ///
        /// Emits a `GameEnded` event if the game has ended with the following data:
        /// * `game_id`: The ID of the ended game.
        /// * `end_time`: The block timestamp when the game ended.
        /// * `winner`: The address of the game's winner.
        /// * `timestamp`: The block timestamp when the event was emitted.
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

        /// Allows a player to claim a tile on the competitive game board.
        ///
        /// This function performs the following actions:
        /// 1.  Retrieves the game state and current block timestamp.
        /// 2.  Checks if the game has started and is currently ongoing.
        /// 3.  If the game has ended, it calculates the winner, updates the game status, and emits
        /// a `CompetitiveGameEnded` event.
        /// 4.  If the game is ongoing, it validates that the given tile coordinates are within the
        /// board's bounds.
        /// 5.  Checks if the caller is a player in the game.
        /// 6.  Creates or updates `PlayerAtPosition` and `TileCompetitive` models to record the
        /// tile claim.
        /// 7.  Emits a `TileClaim` event.
        ///
        /// # Arguments
        ///
        /// * `self`: A mutable reference to the contract's state.
        /// * `game_id`: The unique identifier of the game.
        /// * `x`: The x-coordinate of the tile to claim.
        /// * `y`: The y-coordinate of the tile to claim.
        ///
        /// # Panics
        ///
        /// This function panics if:
        /// * The game has not started.
        /// * The game is not in the `ONGOING` status.
        /// * The given tile coordinates are out of bounds.
        /// * The caller is not a player in the game.
        ///
        /// # Events
        ///
        /// Emits a `TileClaim` event with the following data:
        /// * `game_id`: The ID of the game.
        /// * `x`: The x-coordinate of the claimed tile.
        /// * `y`: The y-coordinate of the claimed tile.
        /// * `player`: The address of the player who claimed the tile.
        /// * `timestamp`: The block timestamp when the tile was claimed.
        ///
        /// Emits a `CompetitiveGameEnded` event if the game has ended with the following data:
        /// * `game_id`: The ID of the ended game.
        /// * `end_time`: The block timestamp when the game ended.
        /// * `winner`: The address of the game's winner.
        /// * `timestamp`: The block timestamp when the event was emitted.
        fn claim_tile_competitive(ref self: ContractState, game_id: u64, x: u8, y: u8) {
            let mut world = self.world_default();
            let mut game: CompetitiveGame = world.read_model(game_id);

            let starts_at = game.starts_at;
            let ends_at = game.ends_at;
            let current_time = get_block_timestamp();
            assert(current_time >= starts_at, 'Game has not started');

            if current_time >= ends_at {
                let winner: felt252 = self.competitive_game_winner(game_id);
                game.is_live = false;
                game.status = ENDED;
                //game.winner = winner;
                world.write_model(@game);
                world
                    .emit_event(
                        @CompetitiveGameEnded {
                            game_id, end_time: ends_at, winner, timestamp: get_block_timestamp(),
                        },
                    );
                return;
            }

            assert(game.status == ONGOING, 'Game is not ongoing');
            assert(x < game.board_width, 'X is out of bounds');
            assert(y < game.board_height, 'Y is out of bounds');

            let player = get_caller_address();
            let in_game: PlayerInCompetitiveGame = world.read_model((game_id, player));
            assert(in_game.joined, 'Player is not in the game');

            let player_at_position = PlayerAtPosition { game_id, x, y, player };
            let tile = TileCompetitive { x, y, game_id, claimed: player, color: in_game.color };

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

        /// Determines the winner of a competitive game based on the number of tiles claimed.
        ///
        /// This function performs the following actions:
        /// 1.  Retrieves the game state and initializes a dictionary to count tile claims by color.
        /// 2.  Iterates through all tiles on the game board.
        /// 3.  For each tile, it retrieves the tile's color and increments the corresponding color
        /// count.
        /// 4.  Determines the color with the highest count of claimed tiles.
        /// 5.  Returns the color of the winning player.
        ///
        /// # Arguments
        ///
        /// * `self`: A read-only reference to the contract's state.
        /// * `game_id`: The unique identifier of the game.
        ///
        /// # Returns
        ///
        /// The color (`felt252`) of the player who claimed the most tiles, representing the winner.
        ///
        /// # Note
        ///
        /// If there is a tie, this function returns the color of the first player found with the
        /// maximum tile count.
        fn competitive_game_winner(self: @ContractState, game_id: u64) -> felt252 {
            let world = self.world_default();
            let game: CompetitiveGame = world.read_model(game_id);

            let colors = colors();
            let mut colors_count: Felt252Dict<u64> = Default::default();
            for i in 0..colors.len() {
                colors_count.insert(*colors.at(i), 0);
            };

            let board_height = game.board_height;
            let board_width = game.board_width;
            for i in 0..(board_height * board_width) {
                let x = i % board_width;
                let y = i % board_height;

                let tile: TileCompetitive = world.read_model((x, y, game_id));
                let color_count = colors_count.get(tile.color);
                colors_count.insert(tile.color, color_count + 1)
            };

            let mut winning_count = Bounded::<u64>::MIN;
            let mut winner = '';

            for i in 0..colors.len() {
                let color = *colors.at(i);
                let count = colors_count.get(color);

                if count > winning_count {
                    winning_count = count;
                    winner = color;
                }
            };

            winner
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
