// dojo decorator
#[dojo::contract]
pub mod PlayerActions {
    use starknet::{
        ContractAddress, get_caller_address, contract_address_const, get_block_timestamp,
    };

    use dojo::model::ModelStorage;
    use dojo::event::EventStorage;

    use octa_flip::interfaces::player::IPlayer;
    use octa_flip::models::player::{Player, PlayerTrait, UsernameToAddress, AddressToUsername};
    use octa_flip::events::player::PlayerEvents::{PlayerBirthed};

    use octa_flip::errors::player::PlayerErrors::{
        USERNAME_CANNOT_BE_ZERO, USERNAME_ALREADY_TAKEN, USERNAME_ALREADY_CREATED,
    };

    #[abi(embed_v0)]
    impl ActionsImpl of IPlayer<ContractState> {
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
    }
}
