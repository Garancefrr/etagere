import type { Config } from "tailwindcss";
const config: Config = {
  content: ["./src/**/*.{js,ts,jsx,tsx,mdx}"],
  theme: {
    extend: {
      colors: {
        bg: "var(--bg)",
        surface: "var(--surface)",
        surface2: "var(--surface2)",
        border: "var(--border)",
        border2: "var(--border2)",
        txt1: "var(--txt1)",
        txt2: "var(--txt2)",
        txt3: "var(--txt3)",
        accent: "var(--accent)",
        "accent-l": "var(--accent-l)",
        "nav-bg": "var(--nav-bg)",
        "card-bg": "var(--card-bg)",
        "miss-bg": "var(--miss-bg)",
        "miss-t": "var(--miss-t)",
        "have-bg": "var(--have-bg)",
        "have-t": "var(--have-t)",
      },
      fontFamily: { sans: ["DM Sans", "sans-serif"] },
    },
  },
  plugins: [],
};
export default config;
