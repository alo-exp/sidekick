#!/usr/bin/env node
import { chromium } from 'playwright';
import { mkdir } from 'fs/promises';
import path from 'path';

const OUT = '/Users/shafqat/projects/sidekick/repo/.visual-audit/lrtb';
const BASE = 'http://localhost:8080';
const WIDTHS = [375, 768, 1280];

const PAGES = [
  { slug: 'index', path: '/' },
  { slug: 'help', path: '/help/' },
  { slug: 'help-getting-started', path: '/help/getting-started/' },
  { slug: 'help-concepts', path: '/help/concepts/' },
  { slug: 'help-workflows', path: '/help/workflows/' },
  { slug: 'help-reference', path: '/help/reference/' },
  { slug: 'help-troubleshooting', path: '/help/troubleshooting/' },
  { slug: 'terms', path: '/terms/' },
  { slug: 'privacy', path: '/privacy/' },
];

await mkdir(OUT, { recursive: true });

const browser = await chromium.launch();
const results = [];

for (const page of PAGES) {
  for (const width of WIDTHS) {
    const context = await browser.newContext({
      viewport: { width, height: 800 },
      deviceScaleFactor: 1,
    });
    const pg = await context.newPage();
    const url = `${BASE}${page.path}`;
    const filename = `${page.slug}-${width}.png`;
    const filepath = path.join(OUT, filename);

    try {
      const resp = await pg.goto(url, { waitUntil: 'networkidle', timeout: 30000 });
      await pg.waitForTimeout(500);
      await pg.screenshot({ path: filepath, fullPage: true });
      const scrollWidth = await pg.evaluate(() => document.documentElement.scrollWidth);
      const clientWidth = await pg.evaluate(() => document.documentElement.clientWidth);
      const hasHScroll = scrollWidth > clientWidth + 1;
      results.push({
        file: filename,
        url,
        width,
        status: resp?.status() ?? 0,
        hasHScroll,
        scrollWidth,
        clientWidth,
      });
    } catch (err) {
      results.push({ file: filename, url, width, error: String(err) });
    } finally {
      await context.close();
    }
  }
}

await browser.close();
console.log(JSON.stringify(results, null, 2));
