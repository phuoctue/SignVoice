#!/usr/bin/env tsx
/**
 * Check API route coverage in OpenAPI documentation
 * Compares actual Express routes with documented endpoints
 */
import * as fs from 'fs';
import * as path from 'path';
import * as yaml from 'yaml';

interface RouteInfo {
  method: string;
  path: string;
  file: string;
  line?: number;
}

// Extract routes from route files
function extractRoutesFromFile(filePath: string): RouteInfo[] {
  const content = fs.readFileSync(filePath, 'utf8');
  const routes: RouteInfo[] = [];
  const fileName = path.basename(filePath);

  // Match router.METHOD('path', ...)
  const routeRegex = /router\.(get|post|put|patch|delete)\s*\(\s*['"`]([^'"`]+)['"`]/gi;
  
  let match;
  while ((match = routeRegex.exec(content)) !== null) {
    const method = match[1].toUpperCase();
    const routePath = match[2];
    
    routes.push({
      method,
      path: routePath,
      file: fileName,
    });
  }

  return routes;
}

// Get all routes from backend
function getAllBackendRoutes(): Map<string, RouteInfo[]> {
  const routesDir = path.join(__dirname, '../src/routes');
  const routeFiles = fs.readdirSync(routesDir).filter(f => f.endsWith('.ts'));
  
  const routesByModule = new Map<string, RouteInfo[]>();

  for (const file of routeFiles) {
    const filePath = path.join(routesDir, file);
    const routes = extractRoutesFromFile(filePath);
    const moduleName = file.replace('.routes.ts', '');
    if (!modulePrefixMap[moduleName]) continue; // Files that are not mounted are not API endpoints.
    routesByModule.set(moduleName, routes);
  }

  return routesByModule;
}

// Get documented endpoints from OpenAPI
function getDocumentedEndpoints(): Set<string> {
  const openApiPath = path.join(__dirname, '../docs/openapi.yaml');
  const openApiContent = fs.readFileSync(openApiPath, 'utf8');
  const spec = yaml.parse(openApiContent);

  const documented = new Set<string>();

  for (const [path, methods] of Object.entries(spec.paths)) {
    for (const method of Object.keys(methods as object)) {
      if (['get', 'post', 'put', 'patch', 'delete'].includes(method)) {
        documented.add(`${method.toUpperCase()} ${path}`);
      }
    }
  }

  return documented;
}

// Map route module prefix to API path prefix
const modulePrefixMap: Record<string, string> = {};
const appSource = fs.readFileSync(path.join(__dirname, '../src/app.ts'), 'utf8');
const mounts = /app\.use\(\s*['"]([^'"]+)['"]\s*,\s*\(await import\(['"]\.\/routes\/([^'"]+)\.routes['"]\)\)\.default\s*\)/g;
for (const match of appSource.matchAll(mounts)) modulePrefixMap[match[2]] = match[1];

// Convert route path to full API path
function toFullPath(moduleName: string, routePath: string): string {
  const prefix = modulePrefixMap[moduleName] || `/api/v1/${moduleName}`;
  
  // Handle root routes
  if (routePath === '/') {
    return prefix;
  }
  
  return `${prefix}${routePath}`;
}

// Convert Express path params to OpenAPI format
// :id -> {id}, :slug -> {slug}
function toOpenApiPath(path: string): string {
  return path.replace(/:([a-zA-Z_][a-zA-Z0-9_]*)/g, '{$1}');
}

// Main coverage check
function checkCoverage() {
  console.log('🔍 Checking API documentation coverage...\n');

  const backendRoutes = getAllBackendRoutes();
  const documented = getDocumentedEndpoints();

  let totalRoutes = 0;
  let documentedCount = 0;
  const undocumented: string[] = [];

  console.log('📊 Routes by module:\n');

  for (const [moduleName, routes] of backendRoutes.entries()) {
    console.log(`  ${moduleName}.routes.ts:`);
    
    for (const route of routes) {
      totalRoutes++;
      const fullPath = toFullPath(moduleName, route.path);
      const openApiPath = toOpenApiPath(fullPath);
      const endpoint = `${route.method} ${openApiPath}`;
      
      if (documented.has(endpoint)) {
        documentedCount++;
        console.log(`    ✅ ${route.method} ${fullPath}`);
      } else {
        undocumented.push(endpoint);
        console.log(`    ❌ ${route.method} ${fullPath} - NOT DOCUMENTED`);
      }
    }
    console.log('');
  }

  // Check for documented but not implemented
  console.log('📄 Checking for documented-only endpoints:\n');
  
  const implementedSet = new Set<string>();
  for (const [moduleName, routes] of backendRoutes.entries()) {
    for (const route of routes) {
      const fullPath = toFullPath(moduleName, route.path);
      const openApiPath = toOpenApiPath(fullPath);
      implementedSet.add(`${route.method} ${openApiPath}`);
    }
  }

  const documentedOnly: string[] = [];
  for (const endpoint of documented) {
    if (!endpoint.startsWith('GET /health')) { // Skip health check endpoints
      if (!implementedSet.has(endpoint)) {
        documentedOnly.push(endpoint);
      }
    }
  }

  if (documentedOnly.length > 0) {
    console.log('  ⚠️  Documented but possibly not implemented:');
    for (const endpoint of documentedOnly) {
      console.log(`    - ${endpoint}`);
    }
  } else {
    console.log('  ✅ All documented endpoints appear to be implemented');
  }

  console.log('\n' + '='.repeat(60));
  console.log('📈 Coverage Summary:\n');
  console.log(`  Total Backend Routes: ${totalRoutes}`);
  console.log(`  Documented: ${documentedCount}`);
  console.log(`  Undocumented: ${undocumented.length}`);
  console.log(`  Coverage: ${((documentedCount / totalRoutes) * 100).toFixed(1)}%`);
  console.log('='.repeat(60) + '\n');

  if (undocumented.length > 0) {
    console.log('❌ Missing documentation for:');
    for (const endpoint of undocumented) {
      console.log(`   - ${endpoint}`);
    }
    console.log('');
  }

  if (undocumented.length === 0 && documentedOnly.length === 0) {
    console.log('✅ Perfect! All routes are documented and match implementation.\n');
    return 0;
  } else if (undocumented.length === 0) {
    console.log('✅ All implemented routes are documented.\n');
    return 0;
  } else {
    console.log('⚠️  Some routes are missing documentation. Please update openapi.yaml\n');
    return 1;
  }
}

// Run check
const exitCode = checkCoverage();
process.exit(exitCode);
