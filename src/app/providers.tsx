"use client";
import { SessionProvider } from "next-auth/react";
import { ThemeProvider } from "@/components/layout/ThemeProvider";
import { DataProvider } from "@/contexts/DataContext";
import { ImportBanner } from "@/components/import/ImportBanner";

export default function Providers({ children }: { children: React.ReactNode }) {
  return (
    <SessionProvider>
      <ThemeProvider>
        <DataProvider>
          {children}
          <ImportBanner />
        </DataProvider>
      </ThemeProvider>
    </SessionProvider>
  );
}
