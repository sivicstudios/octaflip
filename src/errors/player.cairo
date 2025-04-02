pub mod PlayerErrors {
    // Username is a zero value
    pub const USERNAME_CANNOT_BE_ZERO: felt252 = 'Username cannot be 0';
    // Username player intends to claim has already been taken
    pub const USERNAME_ALREADY_TAKEN: felt252 = 'Username already taken';
    // Player has already created username
    pub const USERNAME_ALREADY_CREATED: felt252 = 'Username already created';
}
