#!/bin/bash -x

##############################################################################
# requirements

# Check if yq is installed
if ! command -v yq >/dev/null 2>&1; then
  echo "Error: yq is not installed." >&2
  exit 1
fi


##############################################################################
# arguments

APP_NAME="${1:-testapp}"


##############################################################################
# Vite project
# see https://vite.dev/guide/

# install Vite project with React + TypeScript template
npm create vite@latest "${APP_NAME}" -- --template react-ts --no-interactive


# WORKAROUND
# add allowScripts to package.json to avoid warnings
npm -C "${APP_NAME}" pkg set allowScripts.esbuild=true --json


# install @types/node for TypeScript support
npm -C "${APP_NAME}" install --save-dev @types/node


##############################################################################
# Tailwind
# see https://tailwindcss.com/docs/installation/using-vite

# Install tailwindcss and the peer dependencies
npm -C "${APP_NAME}" install tailwindcss @tailwindcss/vite


# Configure vite.config.ts (Step 1/2)
#   Before
#     import ...
#     import ...
#   
#   After
#     import ...
#     import ...
#     import tailwindcss from '@tailwindcss/vite'
sed -i -E -z 's#(.*import[^\n]*\n)#\1import tailwindcss from "@tailwindcss/vite";\n#' "${APP_NAME}/vite.config.ts"


# Configure vite.config.ts (Step 2/2)
#   Before
#     plugins: [...],
#
#   After
#     plugins: [..., tailwindcss()],
sed -i -E 's/^( *plugins: *.*)(\].*)/\1, tailwindcss()\2/g' "${APP_NAME}/vite.config.ts"


##############################################################################
# Hono
# see https://hono.dev/

npm -C "${APP_NAME}" install hono


##############################################################################
# Cloudflare Wrangler
# see https://developers.cloudflare.com/workers/vite-plugin/get-started/

# WORKAROUND
# Add allowScripts to package.json to avoid warnings
npm -C "${APP_NAME}" pkg set allowScripts.workerd=true --json


# Install wrangler and vite plugin
npm -C "${APP_NAME}" install --save-dev @cloudflare/vite-plugin wrangler


# Configure vite.config.ts (Step 1/3)
#   Before
#     import ...
#     import ...
#   
#   After
#     import ...
#     import ...
#     import tailwindcss from "@tailwindcss/vite"
sed -i -E -z 's#(.*import[^\n]*\n)#\1import { cloudflare } from "@cloudflare/vite-plugin";\n#' "${APP_NAME}/vite.config.ts"


# Configure vite.config.ts (Step 2/3)
#   Before
#     plugins: [...],
#
#   After
#     plugins: [..., cloudflare({ viteEnvironment: { name: "worker" } })],
sed -i -E 's/^( *plugins: *.*)(\].*)/\1, cloudflare({ viteEnvironment: { name: "worker" } })\2/g' "${APP_NAME}/vite.config.ts"


# Configure vite.config.ts (Step 3/3)
# Before
#   export default defineConfig({
#     plugins: [...],
#   })
#
# After
#   export default defineConfig({
#     plugins: [...],
#     environments: { worker: { build: { sourcemap: true } } },
#   })
sed -i -E -z 's#(( +)plugins:[^\n]*\n)#\1\2environments: { worker: { build: { sourcemap: true } } },\n#' "${APP_NAME}/vite.config.ts"


# Create worker config file (wrangler.jsonc)
sed "s/PLACEHOLDER/$(date +%Y-%m-%d)/g" <<'EOF' > "${APP_NAME}/wrangler.jsonc"
{
  "$schema": "./node_modules/wrangler/config-schema.json",
  "name": "my-app",
  "compatibility_date": "PLACEHOLDER",
  "main": "./src/worker/index.ts",
  "assets": {
    "not_found_handling": "single-page-application"
  }
}
EOF


# Configure .gitignore
# Before
#   # Logs
#   logs
#   ...
#
# After
#   # cloudflare (wrangler)
#   .wrangler
#   .dev.vars*
#   
#   # Logs
#   logs
#   ...
sed -i '1i # cloudflare (wrangler)\n.wrangler\n.dev.vars*\n' "${APP_NAME}/.gitignore"


#Add Workers TypeScript types
npm -C "${APP_NAME}" install --save-dev @cloudflare/workers-types


# Create tsconfig.worker.json
cat << 'EOS' > "${APP_NAME}/tsconfig.worker.json"
{
	"extends": "./tsconfig.node.json",
	"compilerOptions": {
		"tsBuildInfoFile": "./node_modules/.tmp/tsconfig.worker.tsbuildinfo",
		"types": ["@cloudflare/workers-types/2023-07-01", "vite/client"],
	},
	"include": ["src/worker"],
}
EOS


# Configure tsconfig.json to reference tsconfig.worker.json
yq -i '.references += [{"path": "./tsconfig.worker.json"}]' "${APP_NAME}/tsconfig.json"


##############################################################################
# Material UI

# add MUI libraries
npm -C "${APP_NAME}" install @mui/material @emotion/react @emotion/styled


##############################################################################
# install libraries

npm -C "${APP_NAME}" install


##############################################################################
# remove src directory

rm -rf "${APP_NAME}/src"


##############################################################################
# generate app source files

# create src/app directory
mkdir -p "${APP_NAME}/src/app"


# change path src to src/app in files
sed -i 's#/src/#/src/app/#g' "${APP_NAME}/index.html"
sed -i 's#"src"#"src/app"#g' "${APP_NAME}/tsconfig.app.json"


# src/app/main.tsx
cat << 'EOS' > "${APP_NAME}/src/app/main.tsx"
import { StrictMode } from 'react'
import { createRoot } from 'react-dom/client'
import { StyledEngineProvider } from '@mui/material/styles';
import { GlobalStyles } from '@mui/material';

import './index.css'
import App from './App.tsx'


createRoot(document.getElementById('root')!).render(
  <StrictMode>
    <StyledEngineProvider enableCssLayer>   {/* for MUI + Tailwind */}
      <GlobalStyles styles="@layer theme, base, mui, components, utilities;" />   {/* for MUI + Tailwind */}
      <App />
    </StyledEngineProvider>
  </StrictMode>,
);
EOS


# src/app/index.css
cat << 'EOS' > "${APP_NAME}/src/app/index.css"
@import "tailwindcss";
EOS


# src/app/App.tsx
cat << 'EOS' > "${APP_NAME}/src/app/App.tsx"
import { useState } from 'react'
import Button from '@mui/material/Button'


function App() {
  const [count, setCount] = useState<number>(0)

  return (
    <>
        <Button
          variant="contained"
          className="rounded-full"
          onClick={() => setCount((count) => count + 1)}
        >
          Count is {count}
        </Button>
    </>
  )
}

export default App
EOS


##############################################################################
# generate worker source files
# see https://developers.cloudflare.com/workers/vite-plugin/tutorial/

# tsconfig.worker.json
cat << 'EOS' > "${APP_NAME}/tsconfig.worker.json"
{
	"extends": "./tsconfig.node.json",
	"compilerOptions": {
		"tsBuildInfoFile": "./node_modules/.tmp/tsconfig.worker.tsbuildinfo",
		"types": ["@cloudflare/workers-types", "vite/client"],
	},
	"include": ["worker"],
}
EOS


# create worker directory
mkdir -p "${APP_NAME}/src/worker"


# worker/index.ts
cat << 'EOS' > "${APP_NAME}/src/worker/index.ts"
import { Hono } from 'hono'
import data from './data.json' with { type: 'json' }


const app = new Hono()


app.get('/api/', (c) => {
  return c.json(data);
})


export default app
EOS


# worker/data.json
cat << 'EOS' > "${APP_NAME}/src/worker/data.json"
{
  "message": "Hello, World!"
}
EOS
