# Bible text release — 0.6.0 target

The owner requested **public-domain translations only**. Free access, an open API, a repository's MIT code license, and an attribution license are different from public-domain text. This release uses a conservative reviewed allowlist of **12 versions / six languages**. New versions require evidence and matching client/database changes; the live API catalog is not imported automatically.

Current App Store distribution is US only. This review does not certify every edition in every country. Expanding distribution requires another rights review. Excluding a version below is a release decision, not a claim that every use of that version is unlawful.

## Retained catalog and evidence

| ID | Retained edition | Public-domain / free commercial-use basis |
| --- | --- | --- |
| `web` | World English Bible | [Translator/publisher dedication](https://ebible.org/eng-web/copyright.htm); copy/distribute/sell allowed. Preserve the verbatim text when using the WEB name. |
| `bsb` | Berean Standard Bible | [Publisher dedication, April 30, 2023](https://berean.bible/terms.htm); all uses permitted, including commercial use. |
| `asv` | American Standard Version 1901 | Identified published edition predates 1931; provider's pinned metadata records public domain and source `eng-asv`. |
| `ylt` | Young's Literal Translation, 1862 / 1898 revision | [Original publisher preface (1898), preserved by CCEL](https://www.ccel.org/bible/ylt/ylt.htm), corroborates the API notice's historic edition date; the published text predates 1931. This API edition is not in the provider's current 32-version data repository. |
| `dra` | Douay-Rheims, Challoner revision / American edition 1899 | Identified published edition predates 1931; pinned metadata records public domain and source `engDRA`. |
| `bbe` | Bible in Basic English | [Cambridge rights-office confirmation preserved by its distributor](https://www.crosswire.org/pipermail/sword-devel/2020-March/047665.html), March 12, 2020: worldwide copyright expiry. This is separate evidence from the API's publication-without-notice rationale. |
| `geneva1599` | Geneva Bible 1599 | Historic published edition predates 1931; pinned metadata records public domain and source `enggnv`. |
| `rvr1909` | Reina-Valera revision 1909 | [United Bible Societies' distribution record](https://open.bible/bibles/reina-valera-1909) identifies the 1909 edition as public domain, corroborating the API notice. No substitution with copyrighted RVR1960 is permitted. |
| `svd` | Smith–Van Dyck 1865 | Identified published edition predates 1931; pinned metadata records public domain and source `arb-vd`. |
| `synodal` | Russian Synodal 1876 | Identified published edition predates 1931; pinned metadata records public domain and source `russyn`. |
| `luth1912` | Luther Bible 1912 | Identified published edition predates 1931; pinned metadata records public domain and source `deu1912`. |
| `riveduta` | Giovanni Luzzi / Riveduta 1927 | Identified published edition predates 1931; pinned metadata records public domain and source `ita1927`. |

The historic-edition US conclusion applies the [US Copyright Office's Circular 22](https://www.copyright.gov/circs/circ22.pdf), which explains expiry for works published/copyrighted before January 1, 1931. This is an inference from documented edition dates and the US rule, not a claim about every later revision or every country. Evidence: [immutable provider metadata and source-verification flags](bible-release-evidence/source-metadata.json), [version-specific API notices and matching returned IDs](bible-release-evidence/provider-contract.json), and [provider provenance](https://github.com/midvash/bible-data/blob/main/SOURCES.md). Every retained repository-backed edition has `sourceVerified: true`; API-only editions use their separately documented evidence above. Checking a returned ID/notice does not authenticate every verse byte: the review did not compare the entire remote corpus with historic printed editions. No royalty or separate text license is required for the identified public-domain editions in the current US distribution scope.

The [provider data license](https://github.com/midvash/bible-data/blob/main/DATA-LICENSE.md) distinguishes public-domain/CC0 from attribution and other licenses; its MIT license covers code, not all Bible text. Its age-based notices are evidence of the identified editions, not an independent legal guarantee about an arbitrary replacement dataset. The provider's terms also require respecting the underlying text's rights: [Midvash terms](https://midvash.com/terms).

## Excluded from the previous 20-version catalog

| ID | Reason for exclusion |
| --- | --- |
| `lsg` | The historic 1910 translation has an age-based US public-domain basis, but pinned provider metadata explicitly says `sourceVerified: false` and has no source URL. Excluded under this conservative release policy until the actual imported dataset has verifiable provenance. |
| `almeida-livre` | The 2018 revision is CC BY, with mandatory attribution. It is openly licensed, not public domain. |
| `kjv` | Known continuing UK publication rights; omitted for this conservative catalog rather than advertising an unqualified worldwide public-domain claim. The historic text's US status is different. [Publisher/distributor explanation](https://ebible.org/engkjvcpb/copyright.htm). |
| `cuv`, `cuvs` | Provider records territory-specific assertions in Hong Kong/Macau. Omitted pending a more specific release/territory determination. |
| `kgy` | Japan Bible Society confirms expiry for the 1955 edition under Japanese law. That alone is not evidence of unrestricted distribution in every launch/use jurisdiction or the exact API dataset's provenance. [Publisher notice](https://www.bible.or.jp/read/bible_copyright.html). |
| `kor` | API notice describes a 1911 old version while its displayed name is the Korean revised version; publisher documentation distinguishes a 1961 edition. Omitted until edition/source and applicable rights are established. [Publisher information](https://www.bskorea.or.kr/bbs/content.php?co_id=subpage2_3_4_1). |
| `vi1934` | Provider asserts expired copyright, but the available audit did not establish a sufficient edition-specific US-rights basis. Omitted pending that evidence; no infringement is asserted. |

## Client and server behavior

- Settings and local service use the same reviewed IDs; direct unsupported service requests fail before any network call. Unknown/removed cached selections display WEB. The settings explanation and Help disclose that fallback; existing scripture references remain intact.
- Migration `202611030003` changes only the Bible preference allowlist/function and replaces removed profile selections with WEB. It does not delete blessings or references. RPC validation and the table constraint both reject unsupported selections and null input; caller scope remains enforced.
- API content must return the exact requested version, book, chapter and verse range, nonempty verses and the exact reviewed rights notice (checked by its SHA-256 fingerprint). A changed notice needs another release review. Aliased, incomplete, differently licensed or creditless responses are not displayed/cached. This matters because [the API documents fallback aliases](https://api.midvash.com/docs).
- Full provider credit appears with in-app passage/selection previews. Widgets carry the provider credit in their snapshot and spoken description, with a compact version/Midvash source label alongside displayed text. Previous snapshots decode without the new optional credit/version fields; old uncredited or no-longer-approved verse bodies are hidden while their reference stays visible until an approved refresh.
- Requests disable cookie handling and carry no manna account token, account ID or post body. Midvash still receives the requested passage/version and ordinary network information. Widget passage refreshes also make these requests. Provider-specific retention has not been independently established; do not invent a log-retention period or equate the provider's own website/app SDKs with this JSON client.

## App Store Content Rights

Owner-approved answer (saved in Chrome App Store Connect on November 3, 2026): **Yes, the app contains/shows/accesses third-party content, and it has the necessary rights or is otherwise permitted to use it.** Public domain is a lawful-use basis; it does not make externally sourced text first-party content.

[Apple's field reference](https://developer.apple.com/help/app-store-connect/reference/app-information/app-information) allows necessary rights or another lawful basis in every distribution country. [Guideline 5.2](https://developer.apple.com/app-store/review/guidelines/#intellectual-property) also addresses intellectual property and access to third-party services. Keep the version list, source notices, provider terms and sample reference path available for review; Apple may ask for supporting evidence. A generic API subscription/permission is not proof of rights in every translation, and a royalty is not automatically created by selecting Yes. Content Rights, age rating and data-collection/privacy answers are separate questions.

Suggested review explanation: “Bible passages are fetched from Midvash using a fixed release-reviewed list of public-domain translations. The app rejects unknown versions and provider substitutions, preserves version credits, and stores the user's Bible reference rather than copying verse text into the circle database. Version-specific public-domain evidence and the provider's terms are documented in the release rights record.”

The Content Rights field was changed to Yes and its Saved state verified in Chrome. Proof in the Bible worktree: `build/bible-license-audit/app-store-content-rights-yes.png`. On November 4, combined integration also saved the App Store Connect draft as **0.6.0**, Prepare for Submission, with no selected build (`build/release060/app-store-version-060.png` in the main worktree). No build was uploaded or submitted.

## Verification and rollout

- `BibleTextServiceTests`: approved/excluded IDs, old-preference fallback, blocked direct requests, matching identity/range/credit, alias-cache poisoning prevention, retry, invalid reference and private request boundaries.
- Guide tests explain the catalog, fallback, provider and disclosure; normal/largest-dark local UI tests exercise real verse tagging and visible provider credit using synthetic text, without calling Midvash.
- Full disposable migration-chain tests seed all 20 prior preferences, apply the migration, verify retained/removed results, reject unsupported/null/direct writes and check caller isolation.
- [Provider contract evidence](bible-release-evidence/provider-contract.json): one public John 3:16 request per retained ID; 12/12 returned matching version/reference and a credit. This is availability/identity evidence, not independent copyright certification. No user content or tokens are included.
- Before hosted rollout: obtain a recoverable database backup, inspect aggregate affected-preference counts, review exact migration predecessors, run bounded hosted rollback acceptance, and deploy through the normal reviewed process. No hosted migration or live account preference has been changed here.
- Public website privacy/support text still needs the matching Midvash disclosure. Review the final Store labels for actual API practices. Do not mark the entire privacy/compliance gate closed based on this app change alone.
