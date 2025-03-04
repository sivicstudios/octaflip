import { ApolloClient, InMemoryCache } from "@apollo/client";
import { GraphQLWsLink } from "@apollo/client/link/subscriptions";
import { createClient } from "graphql-ws";
import { split, HttpLink } from "@apollo/client";
import { getMainDefinition } from "@apollo/client/utilities";
import { CONFIG } from "./config";

const wsLink = new GraphQLWsLink(
  createClient({
    url: CONFIG.GRAPHQL_ENDPOINT,
  })
);

const httpLink = new HttpLink({
  uri: CONFIG.GRAPHQL_ENDPOINT,
});

// The split function takes three parameters:
//
// * A function that's called for each operation to execute
// * The Link to use for an operation if the function returns a "truthy" value
// * The Link to use for an operation if the function returns a "falsy" value
const splitLink = split(
  ({ query }) => {
    const definition = getMainDefinition(query);
    return (
      definition.kind === "OperationDefinition" &&
      definition.operation === "subscription"
    );
  },
  wsLink,
  httpLink
);

const apollo_client = new ApolloClient({
  link: splitLink,
  // uri: CONFIG.GRAPHQL_ENDPOINT,
  cache: new InMemoryCache(),
});

export default apollo_client;
