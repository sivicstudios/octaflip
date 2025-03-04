// Two players claim tiles on an 8x8 grid
use starknet::ContractAddress;

/// Game model
/// Represents a game with a unique identifier, board dimensions, and number of players.
#[derive(Drop, Copy, Serde)]
#[dojo::model]
pub struct Game {
    #[key]
    pub id: u64,
    // 8 x 8 grid
    pub board_width: u8,
    pub board_height: u8,
    // 2 Players
    pub number_of_players: u8,
    // starts_at | ends_at (block timestamp)
    pub data: felt252,
    pub is_live: bool,
    // Should a game winner be tracked?
// Address 0 -> Default state, Tie.
// Address of the winner.
//pub winner: ContractAddress,
}

/// Player in Game
/// Maps a player(contract address) to their player_id
/// player_id is their index in number of players.
#[derive(Drop, Copy, Serde)]
#[dojo::model]
pub struct PlayerInGame {
    #[key]
    pub game_id: u64,
    #[key]
    pub player_id: u8,
    pub player_address: ContractAddress,
}

/// Tile
/// Represents a tile on the game board, and contains information about the piece placed on it.
#[derive(Serde, Copy, Drop)]
#[dojo::model]
pub struct Tile {
    #[key]
    pub x: u8,
    #[key]
    pub y: u8,
    #[key]
    pub game_id: u64,
    // address | 0x0
    pub claimed: ContractAddress,
}

/// PlayerAtPosition
/// Represents a player at a specific position on the game board.
#[derive(Drop, Copy, Serde)]
#[dojo::model]
pub struct PlayerAtPosition {
    #[key]
    pub game_id: u64,
    #[key]
    pub player: ContractAddress,
    pub x: u8,
    pub y: u8,
}

/// GameCounter
/// Represents a counter for the number of games played.
#[derive(Serde, Copy, Drop, Introspect, PartialEq)]
#[dojo::model]
pub struct GameCounter {
    #[key]
    pub id: felt252,
    pub current_val: u64,
}
