use starknet::{ContractAddress, get_block_timestamp};

// Player model
#[derive(Drop, Copy, Serde)]
#[dojo::model]
pub struct Player {
    #[key]
    pub username: felt252,
    pub owner: ContractAddress, 
    pub birthed_at: u64,
    pub number_of_games_played: u256, 
    pub number_of_games_won: u256,
    pub number_of_games_created: u256,
    pub number_of_tiles_flipped: u256,
}


#[derive(Drop, Copy, Serde)]
#[dojo::model]
pub struct UsernameToAddress {
    #[key]
    pub username: felt252,
    pub address: ContractAddress,
}

#[derive(Drop, Copy, Serde)]
#[dojo::model]
pub struct AddressToUsername {
    #[key]
    pub address: ContractAddress,
    pub username: felt252,
}

pub trait PlayerTrait {
    // Create a new player
    fn new(username: felt252, owner: ContractAddress) -> Player;
}

impl PlayerImpl of PlayerTrait {
    fn new(username: felt252, owner: ContractAddress) -> Player {
        Player {
            username,
            owner,
            birthed_at: get_block_timestamp(),
            number_of_games_played: 0,
            number_of_games_won: 0,
            number_of_games_created: 0,
            number_of_tiles_flipped: 0,
        }
    }
}
