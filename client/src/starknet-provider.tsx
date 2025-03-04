import { sepolia, mainnet, Chain } from "@starknet-react/chains";
import { constants } from "starknet";
import {
  Connector,
  StarknetConfig,
  jsonRpcProvider,
  starkscan,
} from "@starknet-react/core";
import ControllerConnector from "@cartridge/connector/controller";
import { dojoConfig } from "../dojoConfig";
import {
  predeployedAccounts,
  type PredeployedAccountsConnector,
} from "@dojoengine/predeployed-connector";
import { ENV_OPTIONS } from "./utils/constants";
import { CONFIG } from "./config";

// Initialize the connector
const connector = new ControllerConnector({
  policies: CONFIG.POLICIES,
  chains: [
    {
      rpcUrl:
        CONFIG.ENV == ENV_OPTIONS.SEPOLIA
          ? CONFIG.RPC_SEPOLIA_URL
          : CONFIG.RPC_MAINNET_URL,
    },
  ],
  defaultChainId:
    CONFIG.ENV == ENV_OPTIONS.SEPOLIA
      ? constants.StarknetChainId.SN_SEPOLIA
      : constants.StarknetChainId.SN_MAIN,
  // url:
  //     process.env.NEXT_PUBLIC_KEYCHAIN_DEPLOYMENT_URL ??
  //     process.env.NEXT_PUBLIC_KEYCHAIN_FRAME_URL,
  // profileUrl:
  //     process.env.NEXT_PUBLIC_PROFILE_DEPLOYMENT_URL ??
  //     process.env.NEXT_PUBLIC_PROFILE_FRAME_URL,
  // slot: "profile-example",
  slot: "octaflipdev2",
  preset: "octaflip",
  propagateSessionErrors: true,
  // namespace: "dopewars",
  // slot: "eternum-prod",
  // preset: "eternum",
  // namespace: "s0_eternum",
  // slot: "darkshuffle-mainnet",
  // preset: "dark-shuffle",
  // namespace: "darkshuffle_s0",
  // tokens: {
  //   erc20: [
  //     "0x0124aeb495b947201f5fac96fd1138e326ad86195b98df6dec9009158a533b49",
  //   ],
  // },
});

console.log("xdxxxdcwsc");

// Configure RPC provider
const provider = jsonRpcProvider({
  rpc: (chain: Chain) => {
    switch (chain) {
      case mainnet:
        return { nodeUrl: CONFIG.RPC_MAINNET_URL };
      case sepolia:
      default:
        return { nodeUrl: CONFIG.RPC_SEPOLIA_URL };
    }
  },
});

let pa: PredeployedAccountsConnector[] = [];
predeployedAccounts({
  rpc: dojoConfig.rpcUrl as string,
  id: "katana",
  name: "Katana",
}).then((p) => (pa = p));

export function StarknetProvider({ children }: { children: React.ReactNode }) {
  const localProvider = jsonRpcProvider({
    rpc: () => ({ nodeUrl: dojoConfig.rpcUrl as string }),
  });

  const decideProvider =
    CONFIG.ENV == ENV_OPTIONS.LOCAL ? localProvider : provider;

  return (
    <StarknetConfig
      autoConnect
      chains={[mainnet, sepolia]}
      provider={localProvider}
      connectors={pa as unknown as Connector[]}
      explorer={starkscan}
    >
      {children}
    </StarknetConfig>
  );
}
