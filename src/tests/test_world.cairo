#[cfg(test)]
mod tests {
    use core::starknet::ContractAddress;
    use starknet::{testing, contract_address_const};
    use dojo_cairo_test::WorldStorageTestTrait;
    use dojo::model::{ModelStorage, ModelValueStorage, ModelStorageTest};
    use dojo::world::{WorldStorageTrait, WorldStorage};
    use dojo::world::{world, IWorldDispatcherTrait};
    use dojo::event::Event;
    use dojo_cairo_test::{
        spawn_test_world, NamespaceDef, TestResource, ContractDefTrait, ContractDef,
    };

    use octa_flip::systems::actions::{actions, IActionsDispatcher, IActionsDispatcherTrait};
    use octa_flip::models::{
        Game, m_Game, GameCounter, m_GameCounter, PlayerAtPosition, m_PlayerAtPosition,
        PlayerInGame, m_PlayerInGame, Tile, m_Tile,
    };
    use octa_flip::constants::{GRID_SIZE, PVP};

    fn namespace_def() -> NamespaceDef {
        let ndef = NamespaceDef {
            namespace: "octa_flip",
            resources: [
                TestResource::Model(m_Game::TEST_CLASS_HASH),
                TestResource::Model(m_GameCounter::TEST_CLASS_HASH),
                TestResource::Model(m_PlayerAtPosition::TEST_CLASS_HASH),
                TestResource::Model(m_PlayerInGame::TEST_CLASS_HASH),
                TestResource::Model(m_Tile::TEST_CLASS_HASH),
                TestResource::Contract(actions::TEST_CLASS_HASH),
                TestResource::Event(actions::e_GameCreated::TEST_CLASS_HASH),
                TestResource::Event(actions::e_PlayerJoined::TEST_CLASS_HASH),
                TestResource::Event(actions::e_GameStarted::TEST_CLASS_HASH),
                TestResource::Event(actions::e_GameEnded::TEST_CLASS_HASH),
                TestResource::Event(actions::e_TileClaim::TEST_CLASS_HASH),
            ]
                .span(),
        };
        ndef
    }

    fn contract_defs() -> Span<ContractDef> {
        [
            ContractDefTrait::new(@"octa_flip", @"actions")
                .with_writer_of([dojo::utils::bytearray_hash(@"octa_flip")].span())
        ]
            .span()
    }

    fn test_setup() -> (WorldStorage, IActionsDispatcher) {
        let ndef = namespace_def();
        let mut world = spawn_test_world([ndef].span());
        world.sync_perms_and_inits(contract_defs());
        let (contract_address, _) = world.dns(@"actions").unwrap();
        let game_actions = IActionsDispatcher { contract_address };
        (world, game_actions)
    }

    #[test]
    #[available_gas(300000000000)]
    fn test_create_game() {
        let (world, game_actions) = test_setup();
        let caller = contract_address_const::<'player1'>();
        testing::set_contract_address(caller);

        let game_id: u64 = game_actions.create_game();

        let created_game: Game = world.read_model(game_id);
        assert(created_game.id == game_id, 'Wrong game ID');
        assert(created_game.board_width == GRID_SIZE, 'Wrong board width');
        assert(created_game.board_height == GRID_SIZE, 'Wrong board height');
        assert(!created_game.is_live, 'Game should not be live');
        assert(created_game.number_of_players == 0, 'Should have no players');
    }

    #[test]
    #[available_gas(300000000000)]
    fn test_join_game() {
        let (world, game_actions) = test_setup();
        let player1 = contract_address_const::<'player1'>();

        // Create game
        testing::set_contract_address(player1);
        game_actions.create_game();

        // Join game
        game_actions.join_game(1);

        // Verify game state
        let game: Game = world.read_model(1);
        assert(game.number_of_players == 1, 'Should have one player');

        // Verify player state
        let player_in_game: PlayerInGame = world.read_model((1, 1));
        assert(player_in_game.player_id == 1, 'Wrong player ID');
        assert(player_in_game.player_address == player1, 'Wrong player address');
    }

    #[test]
    #[available_gas(30000000)]
    #[should_panic(expected: ('Game Does Not Exist', 'ENTRYPOINT_FAILED'))]
    fn test_join_nonexistent_game() {
        let (_, game_actions) = test_setup();
        let player1 = contract_address_const::<'player1'>();

        // Create game
        testing::set_contract_address(player1);
        game_actions.create_game();

        // Join game
        game_actions.join_game(2);
    }

    #[test]
    #[available_gas(3000000000000)]
    #[should_panic(expected: ('Game already started', 'ENTRYPOINT_FAILED'))]
    fn test_join_started_game() {
        let (_, game_actions) = test_setup();
        let player1 = contract_address_const::<'player1'>();
        let player2 = contract_address_const::<'player2'>();
        let player3 = contract_address_const::<'player3'>();

        // Setup and start game
        testing::set_contract_address(player1);
        game_actions.create_game();
        game_actions.join_game(1);

        testing::set_contract_address(player2);
        game_actions.join_game(1);
        game_actions.start_game(1);

        // Try to join started game
        testing::set_contract_address(player3);
        game_actions.join_game(1);
    }

    #[test]
    #[available_gas(3000000000000)]
    #[should_panic(expected: ('Address cannot be same', 'ENTRYPOINT_FAILED'))]
    fn test_same_address_join() {
        let (_, game_actions) = test_setup();
        let player1 = contract_address_const::<'player1'>();

        // Join first time
        testing::set_contract_address(player1);
        game_actions.create_game();
        game_actions.join_game(1);

        // Try to join again with same address
        game_actions.join_game(1);
    }

    #[test]
    #[available_gas(3000000000000)]
    fn test_join_multiple_games() {
        let (world, game_actions) = test_setup();
        let player1 = contract_address_const::<'player1'>();

        testing::set_contract_address(player1);

        // Create and join first game
        game_actions.create_game();
        game_actions.join_game(1);

        // Create and join second game
        game_actions.create_game();
        game_actions.join_game(2);

        // Verify player is in both games
        let player_in_game1: PlayerInGame = world.read_model((1, 1));
        let player_in_game2: PlayerInGame = world.read_model((2, 1));

        assert(player_in_game1.game_id == 1, 'Wrong game 1 ID');
        assert(player_in_game2.game_id == 2, 'Wrong game 2 ID');
    }

    #[test]
    #[available_gas(3000000000000)]
    fn test_sequential_player_ids() {
        let (world, game_actions) = test_setup();
        let player1 = contract_address_const::<'player1'>();
        let player2 = contract_address_const::<'player2'>();

        // Create game
        testing::set_contract_address(player1);
        game_actions.create_game();

        // First player joins
        game_actions.join_game(1);
        let player1_state: PlayerInGame = world.read_model((1, 1));
        assert(player1_state.player_id == 1, 'First player should be ID 1');

        // Second player joins
        testing::set_contract_address(player2);
        game_actions.join_game(1);
        let player2_state: PlayerInGame = world.read_model((1, 2));
        assert(player2_state.player_id == 2, 'Second player should be ID 2');
    }

    #[test]
    #[available_gas(300000000000)]
    #[should_panic(expected: ('Game is full', 'ENTRYPOINT_FAILED'))]
    fn test_join_full_game() {
        let (_, game_actions) = test_setup();
        let player1 = contract_address_const::<'player1'>();
        let player2 = contract_address_const::<'player2'>();
        let player3 = contract_address_const::<'player3'>();

        // Create and fill game
        testing::set_contract_address(player1);
        game_actions.create_game();
        game_actions.join_game(1);

        testing::set_contract_address(player2);
        game_actions.join_game(1);

        // Try to join full game
        testing::set_contract_address(player3);
        game_actions.join_game(1);
    }

    #[test]
    #[available_gas(300000000000)]
    fn test_start_game() {
        let (world, game_actions) = test_setup();
        let player1 = contract_address_const::<'player1'>();
        let player2 = contract_address_const::<'player2'>();

        // Setup game with two players
        testing::set_contract_address(player1);
        game_actions.create_game();
        game_actions.join_game(1);

        testing::set_contract_address(player2);
        game_actions.join_game(1);

        // Start game
        game_actions.start_game(1);

        let game: Game = world.read_model(1);
        assert(game.is_live, 'Game should be live');
        assert(game.data != 'PENDING', 'Game data should be set');
    }

    #[test]
    #[available_gas(3000000000000)]
    #[should_panic(expected: ('Need 2 players to start', 'ENTRYPOINT_FAILED'))]
    fn test_start_with_insufficient_players() {
        let (_, game_actions) = test_setup();
        let player1 = contract_address_const::<'player1'>();

        // Create game and join with only one player
        testing::set_contract_address(player1);
        game_actions.create_game();
        game_actions.join_game(1);

        // Try to start game with one player
        game_actions.start_game(1);
    }

    #[test]
    #[available_gas(30000000000)]
    #[should_panic(expected: ('Invalid Game Data', 'ENTRYPOINT_FAILED'))]
    fn test_start_with_invalid_game_data() {
        let (mut world, game_actions) = test_setup();
        let player1 = contract_address_const::<'player1'>();
        let player2 = contract_address_const::<'player2'>();

        // Setup game with two players
        testing::set_contract_address(player1);
        game_actions.create_game();
        game_actions.join_game(1);

        testing::set_contract_address(player2);
        game_actions.join_game(1);

        // Manually corrupt game data
        let mut game: Game = world.read_model(1);
        game.data = 'CORRUPTED';
        world.write_model_test(@game);

        // Try to start game with invalid data
        testing::set_contract_address(player1);
        game_actions.start_game(1);
    }

    #[test]
    #[available_gas(300000000000)]
    #[should_panic(expected: ('Game already started', 'ENTRYPOINT_FAILED'))]
    fn test_start_already_started_game() {
        let (world, game_actions) = test_setup();
        let player1 = contract_address_const::<'player1'>();
        let player2 = contract_address_const::<'player2'>();

        // Setup game with two players
        testing::set_contract_address(player1);
        game_actions.create_game();
        game_actions.join_game(1);

        testing::set_contract_address(player2);
        game_actions.join_game(1);

        // Start game
        game_actions.start_game(1);
        game_actions.start_game(1);
    }

    #[test]
    #[available_gas(300000000000)]
    fn test_claim_tile() {
        let (world, game_actions) = test_setup();
        let player1 = contract_address_const::<'player1'>();
        let player2 = contract_address_const::<'player2'>();

        // Setup and start game
        testing::set_contract_address(player1);
        game_actions.create_game();
        game_actions.join_game(1);

        testing::set_contract_address(player2);
        game_actions.join_game(1);
        game_actions.start_game(1);

        // Claim tile
        testing::set_contract_address(player1);
        game_actions.claim_tile(1, 0, 0);

        // Verify tile state
        let tile: Tile = world.read_model((0, 0, 1));
        assert(tile.claimed == player1, 'Wrong tile owner');
        let pos: PlayerAtPosition = world.read_model((1, player1));
        assert(pos.player == player1, 'Wrong position owner');
    }

    #[test]
    #[available_gas(30000000000)]
    fn test_game_winner() {
        let (_, game_actions) = test_setup();
        let player1 = contract_address_const::<'player1'>();
        let player2 = contract_address_const::<'player2'>();

        // Setup and start game
        testing::set_contract_address(player1);
        game_actions.create_game();
        game_actions.join_game(1);

        testing::set_contract_address(player2);
        game_actions.join_game(1);
        game_actions.start_game(1);

        // Player 1 claims more tiles
        testing::set_contract_address(player1);
        game_actions.claim_tile(1, 0, 0);
        game_actions.claim_tile(1, 0, 1);
        game_actions.claim_tile(1, 1, 0);

        testing::set_contract_address(player2);
        game_actions.claim_tile(1, 1, 1);

        let winner = game_actions.game_winner(1);
        assert(winner == player1, 'Wrong winner');
    }
}
