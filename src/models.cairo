// Two players claim tiles on an 8x8 grid
use starknet::ContractAddress;

/// Game model
/// Represents the state of a game.
#[derive(Drop, Copy, Serde)]
#[dojo::model]
pub struct Game {
    /// Unique identifier for the game.
    #[key]
    pub id: u64,
    /// Width of the game board (e.g., 8 for an 8x8 grid).
    pub board_width: u8,
    /// Height of the game board (e.g., 8 for an 8x8 grid).
    pub board_height: u8,
    /// Current number of players in the game (e.g., 2 for a two-player game).
    pub number_of_players: u8,
    /// Game data, storing encoded start and end times (block timestamps).
    pub data: felt252,
    /// Indicates whether the game is currently live (true) or not (false).
    pub is_live: bool,
    /// Should a game winner be tracked?
/// Address 0 -> Default state, Tie.
/// Address of the winner.
// pub winner: ContractAddress,
}

/// Represents the state of a competitive game.
#[derive(Drop, Copy, Serde)]
#[dojo::model]
pub struct CompetitiveGame {
    /// Unique identifier for the competitive game.
    #[key]
    pub id: u64,
    /// Width of the game board (e.g., 8 for an 8x8 grid).
    pub board_width: u8,
    /// Height of the game board (e.g., 8 for an 8x8 grid).
    pub board_height: u8,
    /// Current number of players in the competitive game.
    pub number_of_players: u64,
    /// Status of the game (WAITING, ONGOING, ENDED).
    pub status: felt252,
    /// Indicates whether the game is currently live (true) or not (false).
    pub is_live: bool,
    /// Start time of the game in seconds since epoch.
    pub starts_at: u64,
    /// End time of the game in seconds since epoch.
    pub ends_at: u64,
    /// Duration of the game in seconds.
    pub duration: u64,
    /// Address of the game pilot (creator).
    pub pilot: ContractAddress,
    /// Should a game winner be tracked?
/// color -> Default state, Tie.
/// color of the winning tile.
// pub winner: felt252,
}

/// Player in Game
/// Maps a player(contract address) to their player_id
/// player_id is their index in number of players.
#[derive(Drop, Copy, Serde)]
#[dojo::model]
pub struct PlayerInGame {
    /// The ID of the game the player is participating in.
    #[key]
    pub game_id: u64,
    /// The unique ID assigned to the player within the game.
    #[key]
    pub player_id: u8,
    /// The contract address of the player.
    pub player_address: ContractAddress,
}

/// Player in Competitive Game
/// Represents a player's participation in a competitive game.
#[derive(Drop, Copy, Serde)]
#[dojo::model]
pub struct PlayerInCompetitiveGame {
    /// The ID of the competitive game the player is participating in.
    #[key]
    pub game_id: u64,
    /// The contract address of the player.
    #[key]
    pub player_address: ContractAddress,
    /// The color assigned to the player in the game.
    pub color: felt252,
    /// Indicates whether the player has joined the game (true) or not (false).
    pub joined: bool,
}

/// Tile
/// Represents a tile on the game board, and contains information about the piece placed on it.
#[derive(Serde, Copy, Drop)]
#[dojo::model]
pub struct Tile {
    /// The x-coordinate of the tile.
    #[key]
    pub x: u8,
    /// The y-coordinate of the tile.
    #[key]
    pub y: u8,
    /// The ID of the game this tile belongs to.
    #[key]
    pub game_id: u64,
    /// The contract address of the player who claimed the tile, or 0x0 if unclaimed.
    pub claimed: ContractAddress,
}

/// TileCompetitive
/// Represents a tile on the game board, and contains information about the piece placed on it.
#[derive(Serde, Copy, Drop)]
#[dojo::model]
pub struct TileCompetitive {
    /// The x-coordinate of the tile.
    #[key]
    pub x: u8,
    /// The y-coordinate of the tile.
    #[key]
    pub y: u8,
    /// The ID of the competitive game this tile belongs to.
    #[key]
    pub game_id: u64,
    /// The contract address of the player who claimed the tile, or 0x0 if unclaimed.
    pub claimed: ContractAddress,
    /// The color of the tile, representing the player who claimed it.
    pub color: felt252,
}

/// PlayerAtPosition
/// Represents a player's position on a game board.
#[derive(Drop, Copy, Serde)]
#[dojo::model]
pub struct PlayerAtPosition {
    /// The ID of the game.
    #[key]
    pub game_id: u64,
    /// The contract address of the player.
    #[key]
    pub player: ContractAddress,
    /// The x-coordinate of the player's position.
    pub x: u8,
    /// The y-coordinate of the player's position.
    pub y: u8,
}

/// GameCounter
/// Represents a counter for the number of games played.
#[derive(Serde, Copy, Drop, Introspect, PartialEq)]
#[dojo::model]
pub struct GameCounter {
    /// The unique identifier for the counter (e.g., a constant string).
    #[key]
    pub id: felt252,
    /// The current value of the counter.
    pub current_val: u64,
}
