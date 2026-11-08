// Checks authenticated TURN allocation from a real browser, without exposing credentials.
const fs = require('node:fs')
const crypto = require('node:crypto')
const { chromium } = require('../../tests/e2e/node_modules/playwright')
const env = Object.fromEntries(fs.readFileSync(require('node:path').join(__dirname, '../../.env'),'utf8').split(/\r?\n/).filter(l => l && !l.trim().startsWith('#') && l.includes('=')).map(l => {const i=l.indexOf('='); return [l.slice(0,i).trim(),l.slice(i+1).trim().replace(/^['"]|['"]$/g,'')]}))
;(async () => {
  const browser = await chromium.launch({channel:'chrome'})
  try {
    const page = await browser.newPage()
    const username = `${Math.floor(Date.now()/1000)+300}:smoke`
    const credential = crypto.createHmac('sha1', env.TURN_SHARED_SECRET).update(username).digest('base64')
    const result = await page.evaluate(async ({username,credential}) => {
      const pc = new RTCPeerConnection({iceServers:[{urls:'turn:127.0.0.1:3478?transport=udp',username,credential}],iceTransportPolicy:'relay'})
      pc.createDataChannel('probe')
      try {
        const candidate = new Promise((resolve,reject) => {
          const timer = setTimeout(() => reject(new Error('No authenticated relay candidate within 15s')),15000)
          pc.onicecandidate = e => {if(e.candidate?.type==='relay') {clearTimeout(timer);resolve(e.candidate.type)}}
        })
        await pc.setLocalDescription(await pc.createOffer())
        return await candidate
      } finally {pc.close()}
    },{username,credential})
    console.log('Authenticated TURN allocation:', result)
  } finally {await browser.close()}
})().catch(e => {console.error(e.message);process.exitCode=1})
