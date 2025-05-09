import { config } from "@/config";
import { cookieToInitialState } from "@account-kit/core";
import type { Metadata } from "next";
import { Inter } from "next/font/google";
import { headers } from "next/headers";
import "./globals.css";
import { Providers } from "./providers";

const inter = Inter({ subsets: ["latin"] });

export const metadata: Metadata = {
  title: "Sign in to Gensyn Testnet",
  description: "Modal sign in for Gensyn Testnet",
};

export default async function RootLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  // await the headers() call
  const headersList = await headers();
  const cookieHeader = headersList.get("cookie") ?? undefined;
  const initialState = cookieToInitialState(config, cookieHeader);

  return (
    <html lang="en">
      <body className={inter.className}>
        <Providers initialState={initialState}>{children}</Providers>
      </body>
    </html>
  );
}