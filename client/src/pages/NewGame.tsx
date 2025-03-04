import { useDojoSDK } from "@dojoengine/sdk/react";
import { getEvents } from "@dojoengine/utils";
import { useAccount } from "@starknet-react/core";
import { useEffect, useState } from "react";
import { useQuery, useSubscription } from "@apollo/client";
import { toast } from "react-toastify";
import { delay, extractErrorMessageFromJSONRPCError } from "../utils/helpers";
import { useNavigate } from "react-router";
import { DELAY_MILLISECONDS } from "../utils/constants";
import Header from "../components/Header";
import { QUERY_PLAYERS_IN_GAME } from "../utils/queries";
import { PLAYER_JOINED_SUBSCRIPTION } from "../utils/subscriptions";

const NewGame = () => {
  const [gameId, setGameId] = useState<string>("");
  const [creatingNewGame, setCreatingNewGame] = useState(false);
  const [joiningGame, setJoiningGame] = useState(false);
  const { client } = useDojoSDK();
  const { account } = useAccount();

  const navigate = useNavigate();

  const {
    data: queryPlayersInGameData,
    startPolling: startPollingPlayersInGame,
  } = useQuery(QUERY_PLAYERS_IN_GAME, {
    variables: { gameId },
  });

  const playersInGame =
    queryPlayersInGameData?.octaFlipPlayerInGameModels?.edges;

  // if (playersInGame?.length > 1) {
  //   navigate(`/play/${gameId}`);
  // }

  const { data } = useSubscription(PLAYER_JOINED_SUBSCRIPTION);
  console.log("DATA: ", data);

  // Create and join game
  const createNewGame = async () => {
    if (!account) {
      toast.error("Account not connected");
      return;
    }

    try {
      setCreatingNewGame(true);

      const { transaction_hash } = await client.actions.createGame(account);
      getEvents(
        await account.waitForTransaction(transaction_hash, {
          retryInterval: 100,
        })
      );

      const tx: any = await account.getTransactionReceipt(transaction_hash);
      const gameId = tx.events[0].data[3];

      if (!gameId) {
        toast.error("Failed to create new game");
        // Delay for 3.5 seconds
        await delay(DELAY_MILLISECONDS);
        navigate("/");
      }

      setGameId(gameId);
      return gameId;
    } catch (e: any) {
      toast.error(e);
      console.error(e);
    } finally {
      setCreatingNewGame(false);
    }
  };

  const joinGame = async (gameId: string) => {
    if (!account) {
      toast.error("Account not connected");
      return;
    }

    try {
      setJoiningGame(true);
      const join = await client.actions.joinGame(account, gameId);

      const transaction_hash = join.transaction_hash;
      getEvents(
        await account.waitForTransaction(transaction_hash, {
          retryInterval: 100,
        })
      );

      const tx = await account.getTransactionReceipt(transaction_hash);
      if (!tx.isSuccess()) {
        toast.error("Failed to join");
        throw new Error("Failed to join game");
      }
    } catch (e: any) {
      const errorMessage = extractErrorMessageFromJSONRPCError(
        JSON.stringify(e)
      );
      toast.error(errorMessage);
      console.error(e);
    } finally {
      setJoiningGame(false);
    }
  };

  startPollingPlayersInGame(500);

  useEffect(() => {
    const createAndJoinGame = async () => {
      await createNewGame().then(async (gameId) => await joinGame(gameId));
    };

    if (account) {
      createAndJoinGame();
    }

    return () => {};
  }, [account]);

  return (
    <>
      <Header />
      <div className="bg-stone-900 w-full min-h-screen h-full">
        {creatingNewGame ? (
          <div className="text-white text-2xl w-full h-screen flex justify-center items-center">
            Creating new game...
          </div>
        ) : (
          <div
            className={`w-full h-full min-h-[80vh] justify-center items-center mx-auto flex flex-col space-y-6 relative`}
          >
            <div className="w-full mx-auto flex flex-col items-center justify-center space-y-8">
              <span
                className={`text-md py-2 px-4 text-center font-black text-stone-600 `}
              >
                Share game code..
              </span>
              <input
                type="text"
                readOnly
                className="outline-none w-full max-w-[400px] bg-transparent border-b-2 p-4 uppercase border-stone-600 text-center text-6xl text-stone-300 font-bold tracking-wide"
                placeholder="1234"
                value={gameId}
              />
              <span
                className={`text-md py-2 px-4 text-center font-black text-stone-100 `}
              >
                Waiting for opponent
              </span>
            </div>
            <button
              type="button"
              onClick={async () => navigate(`/play/${gameId}`)}
              className={`text-md cursor-pointer py-2 px-4 sm:text-2xl sm:py-4 sm:px-8 text-center font-black text-stone-100 bg-stone-600 rounded-xl border-2 border-stone-600 shadow-inner`}
            >
              PLAY
            </button>
          </div>
        )}
      </div>
    </>
  );
};

export default NewGame;
