pub mod PlayerEvents {
    use starknet::ContractAddress;

    /// Event emitted when a player joins a competitive game.
    #[derive(Copy, Drop, Serde)]
    #[dojo::event]
    pub struct PlayerBirthed {
        #[key]
        pub username: felt252,
        /// The block timestamp when the player joined.
        pub timestamp: u64,
    }

    /// Event emitted when a player joins a competitive game.
    #[derive(Copy, Drop, Serde)]
    #[dojo::event]
    pub struct PlayerJoined {
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
}
