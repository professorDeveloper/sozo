# Security policy

## Reporting a vulnerability

**Do not open a public issue for a security problem.** An issue is visible to
everyone the moment it is filed, including to people who would use it before it
is fixed.

Report it privately through GitHub's own channel:

> **[Report a vulnerability](https://github.com/professorDeveloper/sozo/security/advisories/new)**

That opens a draft advisory only the maintainers and you can read. If you cannot
use it for any reason, say so in a normal issue **without any detail** — just
"I would like to report a security issue privately" — and you will be contacted.

### What helps

- What an attacker can do, in one sentence. That is what decides how fast this
  moves.
- The version — the one on the About screen, or a commit hash.
- The platform and OS version.
- The smallest reproduction you have. A log with the secret parts removed is
  worth more than a description of a log.

You do not need a proof-of-concept exploit, and you do not need to write the
fix. A clear description of the flaw is enough.

### What to expect

- An acknowledgement within a few days.
- An assessment, and the reasoning behind it, once the report has been read
  properly — including when the answer is that it is not a vulnerability.
- Credit in the advisory and the release notes, under whatever name you choose,
  unless you ask not to be named.

Please give a fix a reasonable chance to ship before disclosing publicly. If a
report goes unanswered, that is a failure on this end and not a reason to keep
waiting indefinitely.

## What is in scope

Anything in this repository, and anything the app does on a user's device:

- The app itself, on every platform it ships to.
- The stored data. The session and tracker tokens and the PIN-hidden private
  list are AES-encrypted at rest with a key held in the platform keystore; a way
  to read any of it without the keystore is a vulnerability.
- The app lock, and any way around it.
- The deep-link handlers (`sozo://`, `https://`) and the "Open with" paths.
- Anything that lets a source, an extension or a page it loads reach further
  than the content it is meant to serve — the file system, the keystore, another
  source's cookies, or the app's own JavaScript runtime.
- Secrets in the repository or in a shipped artifact.

## What is not

- **Third-party sources.** Sozo does not host content; a source's site being
  hostile, wrong or down is that site's business. If a source can escape the
  sandbox it runs in, that IS in scope — report it.
- A vulnerability in a dependency that Sozo does not actually reach. Report it
  upstream; mention it here if you believe our usage makes it exploitable.
- Reports that only say a scanner flagged something, with no path to an effect.
- Anything requiring a rooted or jailbroken device and physical access, unless
  it defeats the app lock or the encryption at rest, which are the two things
  that exist for exactly that case.

## Supported versions

The latest release. Fixes go into the next release rather than into patches of
older ones — there is no long-term support branch, and asking users to stay on
an old version is not a security answer.
