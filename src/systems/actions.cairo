use octa_flip::models::{
    CompetitiveGame, GameCounter, PlayerAtPosition, PlayerInCompetitiveGame, PlayerInGame,
    TileCompetitive,
};

use octa_flip::interfaces::actions::IActions;

// dojo decorator
#[dojo::contract]
pub mod actions {
    use super::{
        IActions, CompetitiveGame, GameCounter, PlayerAtPosition, PlayerInCompetitiveGame,
        PlayerInGame, TileCompetitive,
    };
    use starknet::{ContractAddress, get_caller_address, get_block_timestamp};
    use core::dict::Felt252Dict;
    use core::num::traits::Bounded;
    use octa_flip::utils::{zero_address};
    use octa_flip::constants::{ENDED, GRID_SIZE, ONGOING, WAITING};
    use octa_flip::utils::{colors};

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
        fn create_game(ref self: ContractState, grid_size: u8, duration: u64) -> u64 {
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

        fn join_game(ref self: ContractState, game_id: u64) {
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

        fn start_game(ref self: ContractState, game_id: u64) {
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

        fn claim_tile(ref self: ContractState, game_id: u64, x: u8, y: u8) {
            let mut world = self.world_default();
            let mut game: CompetitiveGame = world.read_model(game_id);

            let starts_at = game.starts_at;
            let ends_at = game.ends_at;
            let current_time = get_block_timestamp();
            assert(current_time >= starts_at, 'Game has not started');

            if current_time >= ends_at {
                let winner: felt252 = self.game_winner(game_id);
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

        fn game_winner(self: @ContractState, game_id: u64) -> felt252 {
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

                if count == winning_count {
                    winner = 'TIE';
                    continue;
                }

                if count > winning_count {
                    winning_count = count;
                    winner = color;
                }
            };

            winner
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
