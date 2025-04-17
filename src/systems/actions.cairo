// dojo decorator
#[dojo::contract]
pub mod GameActions {
    use core::dict::Felt252Dict;
    use core::num::traits::Bounded;
    use dojo::event::EventStorage;
    use dojo::model::ModelStorage;
    use octa_flip::constants::{ENDED, GRID_SIZE, ONGOING, WAITING};
    use octa_flip::errors::game::GameErrors::{
        ALREADY_JOINED, ATLEAST_TWO_PLAYERS, GAME_DOES_NOT_EXIST, GAME_HAS_ENDED,
        GAME_HAS_NOT_STARTED, GAME_IS_NOT_ONGOING, GAME_NOT_IN_SESSION, INVALID_CALLER,
        INVALID_GAME_SESSION, PLAYER_NOT_IN_GAME, X_IS_OUT_OF_BOUNDS, Y_IS_OUT_OF_BOUNDS,
    };
    use octa_flip::errors::player::PlayerErrors::{
        PLAYER_NOT_REGISTERED, USERNAME_ALREADY_CREATED, USERNAME_ALREADY_TAKEN,
        USERNAME_CANNOT_BE_ZERO,
    };
    use octa_flip::events::game::GameEvents::{GameCreated, GameEnded, GameStarted, TileClaim};
    use octa_flip::events::player::PlayerEvents::{PlayerBirthed, PlayerJoined};
    use octa_flip::interfaces::actions::IAction;
    use octa_flip::models::game::{Game, GameCounter, GameTag, PlayerAtPosition, PlayerInGame, Tile};
    use octa_flip::models::player::{AddressToUsername, Player, PlayerTrait, UsernameToAddress};
    use octa_flip::utils::{colors, zero_address};
    use starknet::{
        ContractAddress, contract_address_const, get_block_timestamp, get_caller_address,
    };

    #[abi(embed_v0)]
    impl ActionsImpl of IAction<ContractState> {
        fn create_game(ref self: ContractState, grid_size: u8, duration: u64) -> u64 {
            // Get the account address of the caller
            let caller_address = get_caller_address();
            let caller_username: felt252 = self.get_username_from_address(caller_address);
            assert(caller_username != 0, PLAYER_NOT_REGISTERED);

            let mut world = self.world_default();
            let game_id = self.game_uid();

            assert(duration > 0, INVALID_GAME_SESSION);

            let grid_size = match grid_size == 0 || grid_size > Bounded::<u8>::MAX {
                true => GRID_SIZE,
                false => grid_size,
            };

            let new_game: Game = Game {
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
                winner: 0,
            };

            let mut player: Player = world.read_model(caller_username);
            player.number_of_games_created += 1;

            world.write_model(@new_game);
            world.write_model(@player);

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

            // Get the account address of the caller
            let caller_username: felt252 = self.get_username_from_address(player_address);
            assert(caller_username != 0, PLAYER_NOT_REGISTERED);

            let mut game: Game = world.read_model(game_id);
            let mut player: Player = world.read_model(caller_username);
            assert(game.board_width != 0, GAME_DOES_NOT_EXIST);
            assert(game.status == WAITING, GAME_NOT_IN_SESSION);

            let already_joined_player: PlayerInGame = world.read_model((game_id, player_address));
            assert(!already_joined_player.joined, ALREADY_JOINED);

            let colors = colors();
            let colorindex: u32 = (game.number_of_players % colors.len().into())
                .try_into()
                .unwrap();
            let color = *colors.at(colorindex);

            let newly_joined_player = PlayerInGame { game_id, player_address, color, joined: true };
            world.write_model(@newly_joined_player);

            game.number_of_players += 1;
            world.write_model(@game);

            player.number_of_games_played += 1;
            world.write_model(@player);

            let game_tag: GameTag = GameTag {
                game_id, player_id: game.number_of_players, color, player_address,
            };
            world.write_model(@game_tag);

            world
                .emit_event(
                    @PlayerJoined {
                        game_id, player_address, color, timestamp: get_block_timestamp(),
                    },
                );
        }

        fn start_game(ref self: ContractState, game_id: u64) {
            let mut world = self.world_default();
            let mut game: Game = world.read_model(game_id);

            // Get the account address of the caller
            let caller_address = get_caller_address();
            let caller_username: felt252 = self.get_username_from_address(caller_address);
            assert(caller_username != 0, PLAYER_NOT_REGISTERED);

            let game_status = game.status;
            assert(game.number_of_players > 1, ATLEAST_TWO_PLAYERS);
            assert(game_status == WAITING, GAME_NOT_IN_SESSION);
            assert(game.pilot == caller_address, INVALID_CALLER);

            let starts_at = get_block_timestamp();
            let ends_at = starts_at + game.duration;
            assert(ends_at > starts_at, INVALID_GAME_SESSION);

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
            let mut game: Game = world.read_model(game_id);

            // Get the account address of the caller
            let caller_address = get_caller_address();
            let caller_username: felt252 = self.get_username_from_address(caller_address);
            assert(caller_username != 0, PLAYER_NOT_REGISTERED);

            let starts_at = game.starts_at;
            let ends_at = game.ends_at;
            let current_time = get_block_timestamp();
            assert(current_time >= starts_at, GAME_HAS_NOT_STARTED);
            assert(game.status != ENDED, GAME_HAS_ENDED);

            // Game time has elapsed
            if current_time >= ends_at {
                let winner: felt252 = self.game_winner(game_id);
                game.is_live = false;
                game.status = ENDED;
                game.winner = winner;
                world.write_model(@game);
                self.update_player_win_count(game_id, winner);
                world
                    .emit_event(
                        @GameEnded {
                            game_id, end_time: ends_at, winner, timestamp: get_block_timestamp(),
                        },
                    );
                return;
            }

            assert(game.status == ONGOING, GAME_IS_NOT_ONGOING);
            assert(x < game.board_width, X_IS_OUT_OF_BOUNDS);
            assert(y < game.board_height, Y_IS_OUT_OF_BOUNDS);

            let in_game: PlayerInGame = world.read_model((game_id, caller_address));
            assert(in_game.joined, PLAYER_NOT_IN_GAME);

            let player_at_position = PlayerAtPosition { game_id, x, y, player: caller_address };
            let tile = Tile { x, y, game_id, claimed: caller_address, color: in_game.color };

            let mut player: Player = world.read_model(caller_username);
            player.number_of_tiles_claimed += 1;

            world.write_model(@player_at_position);
            world.write_model(@tile);
            world.write_model(@player);
            world
                .emit_event(
                    @TileClaim {
                        game_id,
                        x,
                        y,
                        player: caller_address,
                        color: in_game.color,
                        timestamp: get_block_timestamp(),
                    },
                );
        }

        fn game_winner(self: @ContractState, game_id: u64) -> felt252 {
            let world = self.world_default();
            let game: Game = world.read_model(game_id);

            let colors = colors();
            let mut colors_count: Felt252Dict<u64> = Default::default();
            for i in 0..colors.len() {
                colors_count.insert(*colors.at(i), 0);
            };

            let board_height = game.board_height;
            let board_width = game.board_width;
            for i in 0..(board_height * board_width) {
                let x = i % board_width;
                let y = i / board_height;

                let tile: Tile = world.read_model((x, y, game_id));
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

        fn get_game_data(self: @ContractState, game_id: u64) -> Game {
            let world = self.world_default();
            let game: Game = world.read_model(game_id);
            game
        }


        /// /// ///

        /// /// ///

        fn create_new_player(ref self: ContractState, username: felt252) {
            let mut world = self.world_default();

            let caller: ContractAddress = get_caller_address();

            let zero_address: ContractAddress = contract_address_const::<0x0>();

            // Validate username
            assert(username != 0, USERNAME_CANNOT_BE_ZERO);

            let existing_player: Player = world.read_model(username);

            // Ensure player username is unique
            assert(existing_player.owner == zero_address, USERNAME_ALREADY_TAKEN);

            // Ensure player cannot update username by calling this function
            let existing_username = self.get_username_from_address(caller);

            assert(existing_username == 0, USERNAME_ALREADY_CREATED);

            let new_player: Player = PlayerTrait::new(username, caller);
            let username_to_address: UsernameToAddress = UsernameToAddress {
                username, address: caller,
            };
            let address_to_username: AddressToUsername = AddressToUsername {
                address: caller, username,
            };

            world.write_model(@new_player);
            world.write_model(@username_to_address);
            world.write_model(@address_to_username);

            world.emit_event(@PlayerBirthed { username, timestamp: get_block_timestamp() });
        }

        fn get_username_from_address(self: @ContractState, address: ContractAddress) -> felt252 {
            let mut world = self.world_default();

            let address_map: AddressToUsername = world.read_model(address);

            address_map.username
        }

        fn get_address_from_username(self: @ContractState, username: felt252) -> ContractAddress {
            let mut world = self.world_default();

            let username_map: UsernameToAddress = world.read_model(username);

            username_map.address
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
            let mut game_counter: GameCounter = world.read_model('v2');
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

            assert(player_one.player_address != zero_address(), PLAYER_NOT_IN_GAME);
            assert(player_two.player_address != zero_address(), PLAYER_NOT_IN_GAME);

            (player_one.player_address, player_two.player_address)
        }

        fn update_player_win_count(ref self: ContractState, game_id: u64, winning_team: felt252) {
            let mut world = self.world_default();
            let game: Game = world.read_model(game_id);

            for player_id in 1..game.number_of_players + 1 {
                let tag: GameTag = world.read_model((game_id, player_id));
                let caller_username: felt252 = self.get_username_from_address(tag.player_address);
                let mut player: Player = world.read_model(caller_username);

                if tag.color == winning_team {
                    player.number_of_games_won += 1;
                    world.write_model(@player);
                }
            }
        }
    }
}
