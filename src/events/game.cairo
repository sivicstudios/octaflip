pub mod GameEvents {
    use starknet::ContractAddress;

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

    /// Event emitted when a competitive game ends.
    #[derive(Copy, Drop, Serde)]
    #[dojo::event]
    pub struct GameEnded {
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
}
