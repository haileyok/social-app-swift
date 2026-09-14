// RichText golden fixtures.
//
// Inputs are plain strings; generate.mjs runs them through the real TS engine
// (@bsky/sdk@1.1.0 richtext: RichText#detectFacets, UnicodeString index math,
// segment iteration) and records byte-offset facets, grapheme/utf16 lengths,
// and segments. Byte offsets are UTF-8 byte indices in the source string -
// the single most bug-prone part of a Swift port (String.Index is grapheme
// based), which is exactly why these cases lean on emoji/CJK/combining text.

export const cases = [
  { name: 'plain', text: 'just a normal sentence' },
  { name: 'url-simple', text: 'look at https://example.com here' },
  { name: 'url-trailing-punctuation', text: 'check this out https://example.com/path.' },
  { name: 'url-with-query-and-fragment', text: 'see https://example.com/a/b?x=1&y=2#frag end' },
  { name: 'mention', text: 'hello @alice.test welcome' },
  { name: 'hashtag', text: 'a post #about #Things and #notatag' },
  { name: 'mixed-facets', text: '@alice.test posted #news from https://example.com' },
  { name: 'cjk-plus-url', text: '中文测试 https://example.com 结束' },
  { name: 'family-emoji-then-url', text: '👨‍👩‍👧‍👦 family then https://example.com' },
  { name: 'flag-emoji-pair', text: 'flags 🇺🇸🇯🇸 done' },
  { name: 'combining-diacritics', text: 'café résumé #tág' },
  { name: 'emoji-skin-tone', text: '👍🏽 thumbs https://example.com 👍🏽' },
  { name: 'multiline', text: 'line one\nline two https://example.com\nline three' },
  { name: 'no-facets-punctuation-only', text: '!!! ??? ... ---' },
  { name: 'long-grapheme-count', text: 'あ'.repeat(120) + ' end' },
]
