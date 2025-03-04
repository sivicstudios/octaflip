use starknet::{ContractAddress, contract_address_const};
use octa_flip::constants::{START_BIT_MASK, END_BIT_MASK};

pub fn zero_address() -> ContractAddress {
    contract_address_const::<0x0>()
}

pub fn bitmask_session(starts_at: u64, ends_at: u64) -> felt252 {
    let starts_at_u256: u256 = starts_at.into();
    let ends_at_u256: u256 = ends_at.into();

    let mut packed: u256 = 0_u256;
    packed = packed | ((starts_at_u256 * 0x10000000000000000_u256) & START_BIT_MASK);
    packed = packed | (ends_at_u256 & END_BIT_MASK);
    packed.try_into().unwrap()
}

pub fn unmask_session(data: felt252) -> (u64, u64) {
    let data_u256: u256 = data.into();
    let starts_at: u64 = ((data_u256 & START_BIT_MASK) / 0x10000000000000000_u256)
        .try_into()
        .unwrap();
    let ends_at: u64 = (data_u256 & END_BIT_MASK).try_into().unwrap();

    (starts_at, ends_at)
}
