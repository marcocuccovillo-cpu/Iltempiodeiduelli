import type { Config } from "tailwindcss";

const config: Config = {
  content: ["./src/**/*.{ts,tsx}"],
  theme: {
    extend: {
      fontFamily: {
        display: ["var(--font-display)", "Impact", "sans-serif"],
        sans: ["var(--font-body)", "ui-sans-serif", "system-ui", "sans-serif"],
      },
      colors: {
        void: "#0a0a0b",
        iron: "#17181a",
        steel: "#2a2c30",
        ash: "#9a9ca3",
        bone: "#e8e6e1",
        blood: "#9b1c1f",
        gold: "#c8a24a",
      },
    },
  },
  plugins: [],
};
export default config;
