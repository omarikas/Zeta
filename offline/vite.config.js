import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { defineConfig, loadEnv } from 'vite';
import basicSsl from '@vitejs/plugin-basic-ssl';
import { transformSync } from '@lwc/compiler';

const root = path.dirname(fileURLToPath(import.meta.url));
const lwcDir = path.resolve(root, '../force-app/main/default/lwc');
const engineDom = path.resolve(root, 'node_modules/@lwc/engine-dom/dist/index.js');

const ASSET_PREFIX = '\0lwc-asset:';

function encodeAsset(kind, filename, scoped) {
    const scopedFlag = scoped ? '1' : '0';
    return `${ASSET_PREFIX}${kind}:${scopedFlag}:${filename}.virtual.js`;
}

function decodeAsset(id) {
    if (!id.startsWith(ASSET_PREFIX) || !id.endsWith('.virtual.js')) {
        return null;
    }
    const rest = id.slice(ASSET_PREFIX.length, -'.virtual.js'.length);
    const kindEnd = rest.indexOf(':');
    const kind = rest.slice(0, kindEnd);
    const scopedEnd = rest.indexOf(':', kindEnd + 1);
    const scoped = rest.slice(kindEnd + 1, scopedEnd) === '1';
    const filename = rest.slice(scopedEnd + 1);
    return { kind, scoped, filename };
}

function virtualFromImporter(id, importer) {
    if (!importer || (!id.endsWith('.html') && !id.includes('.css'))) {
        return null;
    }
    const decodedImporter = decodeAsset(importer);
    const importerFile = decodedImporter ? decodedImporter.filename : importer.split('?')[0];
    if (!isSfdxLwcFile(importerFile)) {
        return null;
    }
    const bare = id.split('?')[0];
    const filename = path.normalize(path.resolve(path.dirname(importerFile), bare));
    if (bare.endsWith('.html')) {
        return encodeAsset('html', filename, false);
    }
    if (bare.endsWith('.css')) {
        const scoped = id.includes('scoped=true') || bare.endsWith('.scoped.css');
        return encodeAsset('css', filename, scoped);
    }
    return null;
}

const stubsLightningDir = path.resolve(root, 'src/stubs/lightning');

function componentMeta(filename) {
    const normalized = path.normalize(filename);
    if (normalized.startsWith(stubsLightningDir + path.sep)) {
        return {
            name: path.basename(path.dirname(filename)),
            namespace: 'lightning'
        };
    }
    return {
        name: path.basename(path.dirname(filename)),
        namespace: 'c'
    };
}

function isSfdxLwcFile(filename) {
    const normalized = path.normalize(filename);
    return (
        normalized.startsWith(lwcDir + path.sep) ||
        normalized.startsWith(stubsLightningDir + path.sep)
    );
}

function compileLwcSource(src, filename, extra = {}) {
    const { name, namespace } = componentMeta(filename);
    return transformSync(src, filename, {
        name,
        namespace,
        enableStaticContentOptimization: false,
        ...extra
    });
}

function compileSfdxLwc() {
    return {
        name: 'compile-sfdx-lwc',
        enforce: 'pre',
        resolveId(id, importer) {
            if (id === 'lwc' || id === '@lwc/engine-dom') {
                return engineDom;
            }
            if (id.startsWith('c/')) {
                const name = id.slice(2);
                const file = path.join(lwcDir, name, `${name}.js`);
                if (fs.existsSync(file)) {
                    return file;
                }
            }
            if (id.startsWith('@salesforce/apex/')) {
                const parts = id.split('/');
                const method = parts[parts.length - 1].split('.')[1] || parts[parts.length - 1];
                const specificStub = path.resolve(root, `src/apex/${method}.js`);
                if (fs.existsSync(specificStub)) {
                    return specificStub;
                }
                return path.resolve(root, 'src/apex/noopApex.js');
            }
            if (id === 'lightning/navigation') {
                return path.resolve(root, 'src/stubs/navigation.js');
            }
            if (id === 'lightning/platformShowToastEvent') {
                return path.resolve(root, 'src/stubs/showToastEvent.js');
            }
            if (id === 'lightning/confirm') {
                return path.resolve(root, 'src/stubs/confirm.js');
            }
            if (id === 'lightning/alert') {
                return path.resolve(root, 'src/stubs/alert.js');
            }
            if (id === 'lightning/prompt') {
                return path.resolve(root, 'src/stubs/prompt.js');
            }
            if (id === 'lightning/platformResourceLoader') {
                return path.resolve(root, 'src/stubs/resourceLoader.js');
            }
            if (id.startsWith('lightning/')) {
                const name = id.slice('lightning/'.length);
                const file = path.resolve(stubsLightningDir, name, `${name}.js`);
                if (fs.existsSync(file)) {
                    return file;
                }
            }
            if (id === '@salesforce/user/Id') {
                return path.resolve(root, 'src/stubs/userId.js');
            }
            if (id.startsWith('@salesforce/resourceUrl/')) {
                return path.resolve(root, 'src/stubs/leafletUrl.js');
            }
            return virtualFromImporter(id, importer);
        },
        load(id) {
            const asset = decodeAsset(id);
            if (!asset) {
                return null;
            }
            const { kind, filename, scoped } = asset;
            if (kind === 'html') {
                const src = fs.existsSync(filename)
                    ? fs.readFileSync(filename, 'utf8')
                    : '<template></template>';
                const { code, warnings } = compileLwcSource(src, filename, {
                    isExplicitImport: true
                });
                if (warnings) {
                    for (const warning of warnings) {
                        this.warn(warning.message || String(warning));
                    }
                }
                return code;
            }
            if (kind === 'css') {
                if (!fs.existsSync(filename)) {
                    return 'export default undefined;';
                }
                const src = fs.readFileSync(filename, 'utf8');
                const { code } = compileLwcSource(src, filename, {
                    isExplicitImport: true,
                    scopedStyles: scoped
                });
                return code;
            }
            return null;
        },
        transform(src, id) {
            if (id.includes('@lwc/engine-dom') && src.includes('sourceMappingURL=')) {
                return {
                    code: src.replace(/\/\/# sourceMappingURL=.*$/m, ''),
                    map: null
                };
            }
            const filename = id.split('?')[0];
            if (!isSfdxLwcFile(filename) || path.extname(filename) !== '.js') {
                return null;
            }
            // Utility modules (no template) stay as plain JS.
            const htmlPath = filename.replace(/\.js$/, '.html');
            if (!fs.existsSync(htmlPath)) {
                return null;
            }
            const { code, warnings } = compileLwcSource(src, filename, { isExplicitImport: false });
            if (warnings) {
                for (const warning of warnings) {
                    this.warn(warning.message || String(warning));
                }
            }
            return { code, map: null };
        }
    };
}

function salesforceProxy(instanceUrl) {
    return {
        target: instanceUrl,
        changeOrigin: true,
        secure: true,
        configure(proxy) {
            proxy.on('error', (_err, _req, res) => {
                if (res && !res.headersSent && typeof res.writeHead === 'function') {
                    res.writeHead(503, { 'Content-Type': 'application/json' });
                    res.end(JSON.stringify({ message: 'Offline' }));
                }
            });
        }
    };
}

export default defineConfig(({ mode }) => {
    const env = loadEnv(mode, root, '');
    const instanceUrl = env.VITE_SF_INSTANCE_URL || 'https://zetapharma.my.salesforce.com';

    return {
        root,
        publicDir: 'public',
        plugins: [
            compileSfdxLwc(),
            basicSsl({
                name: 'zeta-field-pwa',
                domains: ['localhost']
            })
        ],
        optimizeDeps: {
            exclude: ['c/fieldRepHomeMetrics', 'c/clmOfflineStore']
        },
        server: {
            port: 5173,
            fs: {
                allow: [root, path.resolve(root, '..')]
            },
            proxy: {
                '/services': salesforceProxy(instanceUrl)
            }
        },
        preview: {
            port: 4173,
            proxy: {
                '/services': salesforceProxy(instanceUrl)
            }
        },
        build: {
            outDir: 'dist',
            emptyOutDir: true
        }
    };
});
