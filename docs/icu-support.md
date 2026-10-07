# ICU portability

The original [ICU change was reverted in #12](https://github.com/theseus-rs/postgresql-binaries/pull/12)
because ICU 72 and 74 libraries are not ABI-compatible. Enabling `--with-icu`
alone would repeat that failure. GNU builds now use the same recursive dependency
bundling as macOS and musl; the matching ICU common, internationalization and data
libraries accompany PostgreSQL and use relative library paths.

All archive tests create the nondeterministic `und-u-ks-level2` collation from
[#9](https://github.com/theseus-rs/postgresql-binaries/issues/9), check case equality,
accent inequality, and distinct-value behavior. GNU x64/ARM64 additionally run in
Ubuntu 24.04 with system ICU 74, after passing a Debian 12 base-container test.
The Debian build's ICU 72 closure must work in both environments. macOS and musl
execute the same SQL checks; configuration inspection alone is not a passing
result.

Bundling fixes library resolution, not changes in collation semantics across ICU
upgrades. Review PostgreSQL collation version warnings and reindex affected
indexes when upgrading an existing database to a different bundled ICU version.

Alpine packages ICU data as a separate archive and ships a stub data library.
The build embeds the full matching data archive into a relative-loadable ICU
data library, recording the input digest in `icu-data-input.json`; it does not
require an `ICU_DATA` environment variable or `/usr/share/icu` at runtime.
