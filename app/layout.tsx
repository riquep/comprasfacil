import type { Metadata } from "next";
import { Zilla_Slab, Inter, IBM_Plex_Mono } from "next/font/google";
import "./globals.css";

const zillaSlab = Zilla_Slab({
  subsets: ["latin"],
  weight: ["400", "500", "600", "700"],
  variable: "--font-title",
});

const inter = Inter({
  subsets: ["latin"],
  variable: "--font-body",
});

const ibmPlexMono = IBM_Plex_Mono({
  subsets: ["latin"],
  weight: ["400", "500"],
  variable: "--font-mono",
});

export const metadata: Metadata = {
  title: "Compras Fácil",
  description: "Organize notas fiscais, categorize gastos e acompanhe preços por produto.",
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="pt-BR">
      <body
        className={`${zillaSlab.variable} ${inter.variable} ${ibmPlexMono.variable}`}
      >
        {children}
      </body>
    </html>
  );
}
