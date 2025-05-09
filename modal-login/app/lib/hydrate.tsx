// app/lib/hydrate.tsx
"use client";

import { useEffect } from "react";
import { hydrate, defaultAccountState, AlchemyClientState } from "@account-kit/core";

export function Hydrate(props: {
  config: Parameters<typeof hydrate>[0];
  initialState?: AlchemyClientState;
  children: React.ReactNode;
}) {
  // never pass undefined
  const state = props.initialState ?? defaultAccountState(props.config);

  // only runs on the client
  useEffect(() => {
    const { onMount } = hydrate(props.config, state);
    onMount().catch((err) => console.error("AccountKit hydrate failed:", err));
  }, [props.config, state]);

  return <>{props.children}</>;
}
