import { gql } from "@apollo/client";

export const PLAYER_JOINED_SUBSCRIPTION = gql`
  subscription playerJoinedSubscription {
    eventMessageUpdated {
      id
      keys
      eventId
      executedAt
      createdAt
      updatedAt
      models {
        __typename
      }
      __typename
    }
  }
`;
