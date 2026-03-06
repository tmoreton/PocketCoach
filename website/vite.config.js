import { resolve } from 'path'
import { defineConfig } from 'vite'

export default defineConfig({
  build: {
    rollupOptions: {
      input: {
        main: resolve(__dirname, 'index.html'),
        support: resolve(__dirname, 'support/index.html'),
        privacy: resolve(__dirname, 'privacy/index.html'),
      },
    },
  },
})
