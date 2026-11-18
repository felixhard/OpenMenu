# Contributing to OpenMenu

Bug reports, documentation fixes, and code contributions are welcome. Search
[open and closed issues](https://github.com/felixhard/OpenMenu/issues?q=is%3Aissue)
before opening a new one. For a larger feature or a change to the app's behavior,
open an issue first so we can agree on the scope.

## Build and test

[Fork the repository](https://github.com/felixhard/OpenMenu/fork) and clone your
fork. Follow the [build instructions](README.md#build-from-source) from the root
of that checkout. Create a branch from `main` for your change. Edit `project.yml`
for project settings and rerun `xcodegen generate` after adding or moving app files.

Run the test suite for the package you touched. GitHub Actions builds the app
and runs these four suites on pull requests.

```sh
swift test --package-path Packages/OpenMenuCore
swift test --package-path Packages/Clipboard
swift test --package-path Packages/WindowManager
swift test --package-path Packages/WindowSwitcher
```

Test changes that depend on macOS permissions or window behavior in the running
app. If your change depends on multiple displays or Spaces, include the setup you
tested. Use a temporary directory and sample files when testing disk cleanup.

## Open a pull request

Keep the pull request focused on one change and target `main`. Describe the
behavior it changes, link the related issue, and list the tests or manual checks
you ran. Include a screenshot or short recording for visible changes if it helps
review. Use sample clipboard content and redact personal information from logs
and screenshots.

Contributions are covered by the project's [MIT license](LICENSE). Please follow
the [code of conduct](CODE_OF_CONDUCT.md) and use the private reporting process
in the [security policy](SECURITY.md) for vulnerabilities.
