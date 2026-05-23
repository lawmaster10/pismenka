import { defineConfig } from "astro/config";

export default defineConfig({
  site: "https://pismenka.com",
  output: "static",
  build: {
    format: "directory",
    inlineStylesheets: "auto",
  },
  trailingSlash: "always",
});
