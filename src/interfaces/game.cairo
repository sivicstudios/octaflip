// define the interface
#[starknet::interface]
pub trait IGame<T> {
    /// Creates a new competitive game with the given grid size and duration.
    ///
    /// This function initializes a new competitive game with default settings, assigns a unique
    /// ID, and stores the game data. It also emits a `GameCreated` event to notify listeners
    /// that a new game has been created.
    ///
    /// # Arguments
    ///
    /// * `self`: A mutable reference to the `ContractState`. This allows the function
    ///   to access and modify the contract's storage.
    /// * `grid_size`: The size of the game board in both width and height.
    /// * `duration`: The duration of the game in seconds.
    ///
    /// # Returns
    ///
    /// The ID of the newly created game.
    ///
    /// # Events
    ///
    /// * `GameCreated`: Emitted when a new game is successfully created.  Includes
    ///   the `game_id`, `board_width`, `board_height`, and `number_of_players`.
    fn create_game(ref self: T, grid_size: u8, duration: u64) -> u64;

    /// Allows a player to join a competitive game.
    ///
    /// This function performs the following actions:
    /// 1.  Retrieves the game state and player address.
    /// 2.  Validates that the game exists and is in the 'WAITING' status.
    /// 3.  Checks if the player has already joined the game.
    /// 4.  Assigns a unique color to the player based on the game's current player count.
    /// 5.  Creates or updates a `PlayerInCompetitiveGame` model with the player's information.
    /// 6.  Increments the game's player count.
    /// 7.  Emits a `CompetitivePlayerJoined` event.
    ///
    /// # Arguments
    ///
    /// * `self`: A mutable reference to the contract's state.
    /// * `game_id`: The unique identifier of the game to join.
    ///
    /// # Panics
    ///
    /// This function panics if:
    /// * The game with the given `game_id` does not exist (board_width is 0).
    /// * The game is not in the `WAITING` status.
    /// * The player has already joined the game.
    ///
    /// # Events
    ///
    /// Emits a `CompetitivePlayerJoined` event with the following data:
    /// * `game_id`: The ID of the game.
    /// * `player_address`: The address of the player who joined.
    /// * `color`: The color assigned to the player.
    /// * `timestamp`: The block timestamp when the player joined.
    fn join_game(ref self: T, game_id: u64);

    /// Starts a competitive game, transitioning it from 'WAITING' to 'ONGOING'.
    ///
    /// This function performs the following actions:
    /// 1.  Retrieves the game state.
    /// 2.  Validates that there are at least two players in the game.
    /// 3.  Checks if the game is in the 'WAITING' status.
    /// 4.  Verifies that the caller is the game's pilot (creator).
    /// 5.  Calculates the start and end times for the game session.
    /// 6.  Updates the game's status to 'ONGOING' and sets 'is_live' to true.
    /// 7.  Emits a `GameStarted` event.
    ///
    /// # Arguments
    ///
    /// * `self`: A mutable reference to the contract's state.
    /// * `game_id`: The unique identifier of the game to start.
    ///
    /// # Panics
    ///
    /// This function panics if:
    /// * The game has fewer than two players.
    /// * The game is not in the `WAITING` status.
    /// * The caller is not the game's pilot.
    /// * The calculated end time is not greater than the start time (invalid duration).
    ///
    /// # Events
    ///
    /// Emits a `GameStarted` event with the following data:
    /// * `game_id`: The ID of the started game.
    /// * `start_time`: The block timestamp when the game started.
    /// * `timestamp`: The block timestamp when the event was emitted.
    fn start_game(ref self: T, game_id: u64);

    /// Allows a player to claim a tile on the competitive game board.
    ///
    /// This function performs the following actions:
    /// 1.  Retrieves the game state and current block timestamp.
    /// 2.  Checks if the game has started and is currently ongoing.
    /// 3.  If the game has ended, it calculates the winner, updates the game status, and emits
    /// a `CompetitiveGameEnded` event.
    /// 4.  If the game is ongoing, it validates that the given tile coordinates are within the
    /// board's bounds.
    /// 5.  Checks if the caller is a player in the game.
    /// 6.  Creates or updates `PlayerAtPosition` and `TileCompetitive` models to record the
    /// tile claim.
    /// 7.  Emits a `TileClaim` event.
    ///
    /// # Arguments
    ///
    /// * `self`: A mutable reference to the contract's state.
    /// * `game_id`: The unique identifier of the game.
    /// * `x`: The x-coordinate of the tile to claim.
    /// * `y`: The y-coordinate of the tile to claim.
    ///
    /// # Panics
    ///
    /// This function panics if:
    /// * The game has not started.
    /// * The game is not in the `ONGOING` status.
    /// * The given tile coordinates are out of bounds.
    /// * The caller is not a player in the game.
    ///
    /// # Events
    ///
    /// Emits a `TileClaim` event with the following data:
    /// * `game_id`: The ID of the game.
    /// * `x`: The x-coordinate of the claimed tile.
    /// * `y`: The y-coordinate of the claimed tile.
    /// * `player`: The address of the player who claimed the tile.
    /// * `timestamp`: The block timestamp when the tile was claimed.
    ///
    /// Emits a `CompetitiveGameEnded` event if the game has ended with the following data:
    /// * `game_id`: The ID of the ended game.
    /// * `end_time`: The block timestamp when the game ended.
    /// * `winner`: The address of the game's winner.
    /// * `timestamp`: The block timestamp when the event was emitted.
    fn claim_tile(ref self: T, game_id: u64, x: u8, y: u8);

    /// Determines the winner of a competitive game based on the number of tiles claimed.
    ///
    /// This function performs the following actions:
    /// 1.  Retrieves the game state and initializes a dictionary to count tile claims by color.
    /// 2.  Iterates through all tiles on the game board.
    /// 3.  For each tile, it retrieves the tile's color and increments the corresponding color
    /// count.
    /// 4.  Determines the color with the highest count of claimed tiles.
    /// 5.  Returns the color of the winning player or `TIE` if the game is a tie.
    ///
    /// # Arguments
    ///
    /// * `self`: A read-only reference to the contract's state.
    /// * `game_id`: The unique identifier of the game.
    ///
    /// # Returns
    ///
    /// The color (`felt252`) of the player who claimed the most tiles, representing the winner.
    fn game_winner(self: @T, game_id: u64) -> felt252;
}
