pub mod utils;
pub mod constants;

// pub mod tests {
//     mod test_world;
// }

pub mod models {
    pub mod game;
    pub mod player;
}

pub mod systems {
    pub mod game_actions;
    pub mod player_actions;
}

pub mod interfaces {
    pub mod game;
    pub mod player;
}

pub mod events {
    pub mod game;
    pub mod player;
}

pub mod errors {
    pub mod game;
    pub mod player;
}
