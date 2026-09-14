// Golden fixture generator (AC.4).
//
// Runs the pinned TypeScript engines from @bsky/sdk@1.1.0 (the exact version
// the RN social-app pins in its package.json) over the checked-in fixtures
// and writes deterministic golden files to
//   Packages/TestSupport/Fixtures/Golden/{moderation,richtext}.json
// Each golden case carries BOTH the serialized engine input and the projected
// engine output, so the Swift port test suites are self-contained: decode the
// input, run the Swift engine, compare against the output.
//
// Regenerate + verify with:
//   cd tools/golden-gen && npm ci && npm run generate
//   git diff --exit-code -- ../..//Packages/TestSupport/Fixtures/Golden
// (CI enforces this via the golden-idempotency job in linux.yml.)

import { writeFileSync, mkdirSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
import { dirname, resolve } from 'node:path'

import {
  moderatePost,
  moderateProfile,
  moderateUserList,
  moderateFeedGenerator,
} from '@bsky/sdk/moderation'
import { RichText, UnicodeString } from '@bsky/sdk/richtext'

import { cases as modCases, downgradeCase } from './fixtures/moderation.mjs'
import { cases as rtCases } from './fixtures/richtext.mjs'

const here = dirname(fileURLToPath(import.meta.url))
const outDir = resolve(here, '../../Packages/TestSupport/Fixtures/Golden')

const ENGINES = {
  moderatePost,
  moderateProfile,
  moderateUserList,
  moderateFeedGenerator,
}

// Every ModerationBehavior context, in fixed order.
const UI_CONTEXTS = [
  'profileList',
  'profileView',
  'avatar',
  'banner',
  'displayName',
  'contentList',
  'contentView',
  'contentMedia',
]

/** Stable projection of a ModerationCause. */
function projectCause(c) {
  const out = { type: c.type, source: c.source, priority: c.priority }
  if (c.downgraded !== undefined) out.downgraded = c.downgraded
  if (c.type === 'label') {
    out.target = c.target
    out.setting = c.setting
    out.label = { ver: c.label.ver, src: c.label.src, uri: c.label.uri, val: c.label.val }
    out.labelDefIdentifier = c.labelDef?.identifier
    out.noOverride = c.noOverride
  }
  if (c.type === 'muted-word') {
    out.matches = c.matches?.map((m) => ({
      value: m.value,
      targets: m.targets,
      actorTarget: m.actorTarget,
      matchedValue: m.matched_value ?? m.matchedValue,
    }))
  }
  if (c.type === 'muted-by-list' || c.type === 'blocking-by-list') {
    out.listUri = c.list?.uri
  }
  return out
}

/** Stable projection of a ModerationDecision incl. per-context UI. */
function projectDecision(d) {
  const ui = {}
  for (const ctx of UI_CONTEXTS) {
    const u = d.ui(ctx)
    ui[ctx] = {
      noOverride: u.noOverride,
      filter: u.filter,
      blur: u.blur,
      alert: u.alert,
      inform: u.inform,
      filters: u.filters.map(projectCause),
      blurs: u.blurs.map(projectCause),
      alerts: u.alerts.map(projectCause),
      informs: u.informs.map(projectCause),
    }
  }
  return {
    blocked: d.blocked,
    muted: d.muted,
    causes: d.causes.map(projectCause),
    ui,
  }
}

/** ModerationPrefs fields the engine reads unconditionally; fill defaults. */
function normPrefs(p) {
  return {
    adultContentEnabled: false,
    labels: {},
    labelers: [],
    mutedWords: [],
    hiddenPosts: [],
    ...p,
  }
}

const FIXED_TS = '2024-01-01T00:00:00.000Z'

/**
 * The SDK's mock builders stamp createdAt/indexedAt/cts with the current
 * time; freeze them so golden output is reproducible. The engine never
 * branches on timestamps, so mutation is behavior-neutral.
 */
function freezeTimes(value) {
  if (Array.isArray(value)) return value.map(freezeTimes)
  if (value && typeof value === 'object') {
    const out = {}
    for (const [k, v] of Object.entries(value)) {
      if ((k === 'createdAt' || k === 'indexedAt' || k === 'cts') && typeof v === 'string') {
        out[k] = FIXED_TS
      } else {
        out[k] = freezeTimes(v)
      }
    }
    return out
  }
  return value
}

function runModerationCase(c) {
  const engine = ENGINES[c.fn]
  if (!engine) throw new Error(`unknown engine fn: ${c.fn}`)
  const subject = freezeTimes(c.subject)
  const opts = { ...c.opts, prefs: normPrefs(c.opts.prefs) }
  const decision = engine(subject, opts)
  const projected = projectDecision(decision)
  if (c.downgrade) decision.downgrade()
  const downgraded = c.downgrade ? projectDecision(decision) : undefined
  const input = { fn: c.fn, subject, opts }
  const expected = c.downgrade ? { before: projected, afterDowngrade: downgraded } : projected
  return { name: c.name, input, expected }
}

function runRichTextCase(c) {
  const rt = new RichText({ text: c.text })
  // Sync detection (no handle-resolution network call). The Swift port's
  // detection is likewise local; mention resolution is a separate concern.
  rt.detectFacetsWithoutResolution()

  const us = new UnicodeString(c.text)
  // Probe utf16->utf8 conversion at real grapheme boundaries only (never mid-
  // surrogate); node's Intl.Segmenter gives us those boundaries portably.
  const segmenter = new Intl.Segmenter(undefined, { granularity: 'grapheme' })
  let acc = 0
  const boundaries = [0]
  for (const { segment } of segmenter.segment(us.utf16)) {
    acc += segment.length
    boundaries.push(acc)
  }
  const utf16Len = us.utf16.length
  const mid = boundaries[Math.floor(boundaries.length / 2)]
  const probes = [...new Set([0, boundaries[1] ?? utf16Len, mid, utf16Len])]
  const unicode = {
    // NOTE: the TS engine's `length` is a UTF-8 BYTE count (utf8.byteLength),
    // not a grapheme count - kept under this (historical) name for compat
    // with the ported suites. graphemeCount is the true cluster count.
    graphemeLength: us.length,
    graphemeCount: boundaries.length - 1,
    utf16Length: utf16Len,
    utf8ByteLength: us.utf8.length,
    utf16ToUtf8: probes.map((i) => [i, us.utf16IndexToUtf8Index(i)]),
  }

  return {
    name: c.name,
    input: { text: c.text },
    expected: {
      graphemeLength: rt.length,
      facets: (rt.facets ?? []).map((f) => ({
        index: { byteStart: f.index.byteStart, byteEnd: f.index.byteEnd },
        features: f.features.map((feat) => ({ ...feat })),
      })),
      segments: [...rt.segments()].map((s) => ({
        text: s.text,
        facet: s.facet
          ? {
              index: { byteStart: s.facet.index.byteStart, byteEnd: s.facet.index.byteEnd },
              features: s.facet.features.map((feat) => ({ ...feat })),
            }
          : null,
      })),
      unicode,
    },
  }
}

function writeGolden(name, cases) {
  const doc = {
    version: 1,
    generator: '@bsky/sdk@1.1.0 (pinned; matches RN social-app package.json)',
    cases,
  }
  const path = resolve(outDir, `${name}.json`)
  writeFileSync(path, JSON.stringify(doc, null, 2) + '\n')
  console.log(`wrote ${path} (${cases.length} cases)`)
}

mkdirSync(outDir, { recursive: true })
writeGolden('moderation', [...modCases, downgradeCase].map(runModerationCase))
writeGolden('richtext', rtCases.map(runRichTextCase))
console.log('done')
