# Lucee OSGi Extension

OSGi support (Apache Felix) for Lucee 9, moved out of the Lucee core (LDEV-6627).

The extension provides the `lucee.runtime.osgi.OSGiService` implementation. The OSGi framework is started when the first bundle is needed, not at startup of Lucee.

* `source/java/src/org/lucee/extension/osgi/OSGiServiceImpl.java`: the service, registered with `META-INF/services/lucee.runtime.osgi.OSGiService`
* `source/java/src/resources/default.properties`: the Felix configuration (boot delegation, system packages), the same as it was in the core

The extension is installed automatically when Lucee needs OSGi (LDEV-6829), extensions can also declare it as a dependency (LDEV-6808).

## Build

```
mvn clean install
```

builds `target/osgi-extension-{version}.lex` (and the `.lite.lex`).

## Versioning and releases

Works like Lucee core (LDEV-6516) and the other extensions: every code change gets its own version number, the version is not
edited by hand. `pom.xml` uses a CI-friendly `${revision}` built from `extension.version.base` (`1.0.0`), a build number and
`extension.version.qualifier` (`-SNAPSHOT`).

* **Every push to `main`** (a merged PR or a direct commit) takes the highest existing build of the base, from the git tags,
  Maven Central, the Central snapshot repository and [maven.lucee-services.com](https://maven.lucee-services.com/), adds 1,
  builds, tests, publishes that version (e.g. `1.0.0.1-SNAPSHOT`) to maven.lucee-services.com and creates the tag `1.0.0.1`.
* Pushes to `main` and manual deploys share one workflow concurrency group, so a manual deploy and a push cannot get the same number.
* PR builds, forks and runs without the deploy secrets build and test `1.0.0.0-SNAPSHOT`, never publish and never use up a number.
  Pull requests from forks have no repository variables, the tests then run with a fixed 9.0 build.
* **Pre-release or final release**: run the workflow by hand on `main` (Actions > Java CI > Run workflow), tick `deploy` and pick
  `ALPHA`, `BETA`, `RC` or `release` as qualifier. That publishes the current code once with the next build number, without a commit.
  * `ALPHA`, `BETA`, `RC` and `SNAPSHOT` go to maven.lucee-services.com only, never to Maven Central. `ALPHA`, `BETA` and `RC`
    also get a GitHub pre-release with the `.lex` files. The `.lex` files are the ones that were built and tested.
  * `release` (no qualifier) is the final: Maven Central, maven.lucee-services.com and a GitHub release. maven.lucee-services.com
    and GitHub get the tested `.lex`; Maven Central gets a signed rebuild of the same commit.
* To start a new line change `extension.version.base`.
