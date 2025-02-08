import { resolve as resolveTs } from 'ts-node/esm'
import * as tsConfigPaths from 'tsconfig-paths'
import { pathToFileURL } from 'url'

const { absoluteBaseUrl, paths } = tsConfigPaths.loadConfig()
const matchPath = tsConfigPaths.createMatchPath(absoluteBaseUrl, paths)

export function resolve(specifier, context, defaultResolver) {
  const match = matchPath(specifier)
  return match 
    ? resolveTs(pathToFileURL(`${match}`).href, context, defaultResolver)
    : resolveTs(specifier, context, defaultResolver)
}

export { load, getFormat, transformSource } from 'ts-node/esm' 