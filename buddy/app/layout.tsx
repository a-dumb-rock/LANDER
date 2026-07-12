import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: "LANDER Buddy — Team Readiness",
  description:
    "Weekly knee readiness monitoring for sports teams, powered by LANDER computer vision.",
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="en">
      <body className="min-h-screen bg-surface font-sans">{children}</body>
    </html>
  );
}
