import type { Config } from "tailwindcss";

const config: Config = {
  darkMode: ["class"],
  content: [
    "./pages/**/*.{js,ts,jsx,tsx,mdx}",
    "./components/**/*.{js,ts,jsx,tsx,mdx}",
    "./app/**/*.{js,ts,jsx,tsx,mdx}",
    "./lib/**/*.{js,ts,jsx,tsx,mdx}",
  ],
  theme: {
    extend: {
      colors: {
        // LANDER brand
        brand: {
          DEFAULT: "#0EA5E9",
          dark: "#0284C7",
          light: "#38BDF8",
        },
        // Readiness status colours
        status: {
          green: "#22C55E",
          yellow: "#EAB308",
          red: "#EF4444",
          "green-bg": "#DCFCE7",
          "yellow-bg": "#FEF9C3",
          "red-bg": "#FEE2E2",
          "green-text": "#15803D",
          "yellow-text": "#854D0E",
          "red-text": "#B91C1C",
        },
        surface: {
          DEFAULT: "#F8FAFC",
          card: "#FFFFFF",
          border: "#E2E8F0",
        },
      },
      borderRadius: {
        lg: "var(--radius)",
        md: "calc(var(--radius) - 2px)",
        sm: "calc(var(--radius) - 4px)",
      },
      fontFamily: {
        sans: ["Inter", "system-ui", "sans-serif"],
        mono: ["JetBrains Mono", "monospace"],
      },
    },
  },
  plugins: [],
};
export default config;
