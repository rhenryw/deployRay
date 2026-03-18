# deployRay
Easily deploy XTLS/Xray-core to replace traditional wisp servers

#### ⭐️ if you use!

[![Join Our Discord](https://img.shields.io/badge/Join%20Our-Discord-purple)](https://discord.gg/redlv) [![maintenance-status](https://img.shields.io/badge/maintenance-passively--maintained-yellowgreen.svg)](https://github.com/rhenryw/deployWisp/commits/main/)

## An easily deployable repo for [Xray by XTLS](https://github.com/XTLS/Xray-core) through [WCJ by Hg Workshop](https://github.com/MercuryWorkshop/wisp-client-js)

Why Xray?
---

Xray uses VLESS to make traffic MUCH more undetectable than traditional wisp. It's a little slower, but more secure and harder to detect. It also uses compiled Golang binaries so it's heavily optimized.

How to use:
---


START WITH A FRESH UBUNTU SERVER


Point your desired domain/subdomain to the server that you want to install WISP on (Using an `A` record, you can run `hostname -I` if you don't know the IP)

Then run
```bash
curl -fsSL https://raw.githubusercontent.com/rhenryw/deployRay/refs/heads/main/install.sh | bash -s yourdomain.tld --port 8080

```
Replace `yourdomain.tld` with your domain or subdomain. If you need an SSL cert (non-proxied through CloudFlare or `Strict` SSL) run with the `-c` flag:

```bash
curl -fsSL https://raw.githubusercontent.com/rhenryw/deployRay/refs/heads/main/install.sh | bash -s yourdomain.tld -c --port 8080

```

It will install and start by itself!

It's that easy!

Your brand new shiny wisp server will be at `wss://domain.tld/wisp` or `wss://your.domain.tld/wisp`

To test
---
Go to [Websocket Tester](https://piehost.com/websocket-tester)

Enter `wss://yourdomain.tld/wisp` and hit connect, if it says 

```
- Connection failed, see your browser's developer console for reason and error code.
- Connection closed
```

Open an issue

NOTE: This has only been tested on newer ubuntu and debian
