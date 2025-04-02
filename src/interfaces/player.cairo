use starknet::{ContractAddress};

// define the interface
#[starknet::interface]
pub trait IPlayer<T> {
    fn create_new_player(ref self: T, username: felt252);
    fn get_username_from_address(self: @T, address: ContractAddress) -> felt252;
    fn get_address_from_username(self: @T, username: felt252) -> ContractAddress;
}
