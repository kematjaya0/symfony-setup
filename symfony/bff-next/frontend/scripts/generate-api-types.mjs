import { createHash } from 'node:crypto';
import { existsSync } from 'node:fs';
import { mkdtemp, readFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';

const run = promisify(execFile);
const here = dirname(fileURLToPath(import.meta.url));
const root = resolve(here, '..');
const backend = resolve(root, '../backend');
const schema = join(tmpdir(), `boilerplate-openapi-${process.pid}.json`);
const output = resolve(root, 'src/types/api.generated.ts');
const check = process.argv.includes('--check');

async function generate(destination) {
    await run(
        'php',
        [
            'bin/console',
            'api:openapi:export',
            '--spec-version=3',
            `--output=${schema}`,
            '--no-interaction'
        ],
        { cwd: backend }
    );
    await run(
        resolve(root, 'node_modules/.bin/openapi-typescript'),
        [schema, '-o', destination],
        { cwd: root }
    );
}

async function hash(file) {
    return createHash('sha256')
        .update(await readFile(file))
        .digest('hex');
}

try {
    await generate(output);
    if (check) {
        if (existsSync(resolve(root, '../.git'))) {
            await run('git', ['diff', '--exit-code', '--', output], {
                cwd: resolve(root, '..')
            });
        } else {
            const dir = await mkdtemp(join(tmpdir(), 'boilerplate-api-types-'));
            const second = join(dir, 'api.generated.ts');
            try {
                await generate(second);
                if ((await hash(output)) !== (await hash(second)))
                    throw new Error(
                        'Generated API types are not deterministic.'
                    );
            } finally {
                await rm(dir, { recursive: true, force: true });
            }
        }
    }
} finally {
    await rm(schema, { force: true });
}
