"use client";
import { PropsWithChildren } from "react";
import { QueryClientProvider } from "@tanstack/react-query";
import { AlchemyAccountProvider } from "@account-kit/react";
import { config, queryClient } from "@/config";
import { AlchemyClientState } from "@account-kit/core";
import { Hydrate } from "./lib/hydrate";

export const Providers = (
  props: PropsWithChildren<{ initialState?: AlchemyClientState }>,
) => {
  return (
    <QueryClientProvider client={queryClient}>
      <Hydrate config={config} initialState={props.initialState}>
      <AlchemyAccountProvider
        config={config}
        queryClient={queryClient}
        initialState={props.initialState}
      >
        {props.children}
      </AlchemyAccountProvider>
      </Hydrate>
    </QueryClientProvider>
  );
};
