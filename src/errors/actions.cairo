pub mod ActionErrors {
    pub const INVALID_GAME_SESSION: felt252 = 'Invalid game session';
    pub const GAME_DOES_NOT_EXIST: felt252 = 'Game does not exist';
    pub const GAME_NOT_IN_SESSION: felt252 = 'Game not in session';
    pub const ALREADY_JOINED: felt252 = 'Already joined';
    pub const ATLEAST_TWO_PLAYERS: felt252 = 'Atleast two players';
    pub const INVALID_CALLER: felt252 = 'Invalid caller';
    pub const GAME_HAS_NOT_STARTED: felt252 = 'Game has not started';
    pub const GAME_IS_NOT_ONGOING: felt252 = 'Game is not ongoing';
    pub const X_IS_OUT_OF_BOUNDS: felt252 = 'X is out of bounds';
    pub const Y_IS_OUT_OF_BOUNDS: felt252 = 'Y is out of bounds';
    pub const PLAYER_NOT_IN_GAME: felt252 = 'Player not in game';
}
