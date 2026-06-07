import { test, describe } from 'node:test'
import assert from 'node:assert/strict'
import { parseFlags } from '../lib/prompt.js'

describe('parseFlags', () => {
  test('parses --claude flag', () => {
    const flags = parseFlags(['--claude'])
    assert.deepEqual(flags.agents, ['claude'])
    assert.equal(flags.force, false)
    assert.equal(flags.uninstall, false)
  })

  test('parses --all flag', () => {
    const flags = parseFlags(['--all'])
    assert.deepEqual(flags.agents, ['claude', 'codex', 'hermes'])
  })

  test('parses multiple agent flags', () => {
    const flags = parseFlags(['--claude', '--hermes'])
    assert.deepEqual(flags.agents, ['claude', 'hermes'])
  })

  test('parses --force flag', () => {
    const flags = parseFlags(['--force', '--claude'])
    assert.equal(flags.force, true)
    assert.deepEqual(flags.agents, ['claude'])
  })

  test('parses --uninstall flag', () => {
    const flags = parseFlags(['--uninstall'])
    assert.equal(flags.uninstall, true)
  })

  test('parses --help flag', () => {
    const flags = parseFlags(['--help'])
    assert.equal(flags.help, true)
  })

  test('parses -h shorthand', () => {
    const flags = parseFlags(['-h'])
    assert.equal(flags.help, true)
  })

  test('ignores unknown flags', () => {
    const flags = parseFlags(['--unknown', '--claude'])
    assert.deepEqual(flags.agents, ['claude'])
  })

  test('empty args returns empty agents', () => {
    const flags = parseFlags([])
    assert.deepEqual(flags.agents, [])
    assert.equal(flags.force, false)
    assert.equal(flags.uninstall, false)
    assert.equal(flags.help, false)
  })
})
