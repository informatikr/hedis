# Contribution policy

## Did you find a bug?

- Please create a [new issue](https://github.com/informatikr/hedis/issues/new) with description.
- It would be nice if you provide more details such as Redis version, GHC version, cabal-install version (or other build tool title and version) or other important infrastructure details.
- Reproducible case will be appreciated.

## Do you want to contribute a new feature/fix or any other improvement?

1. Please ensure that the corresponding issue exists prior opening a new pull request.
1. **Fork the repository** and create your branch from `main`.
1. **Clone your fork** and set up the project locally, see setting up section.
1. **Make your changes** with clear, descriptive commit messages.
1. **Open a Pull Request** describing your changes and referencing any related issues.

## Code of conduct

Project follows the same code conventions as cardano project [Contributor Covenant][cc-homepage].

## LLM Contribution Policy

### Common

- Scope of contribution matches exactly with exactly a single feature. Each commit should target one area such as: new functionality, fix, documentation change. Multiple areas are allowed as long as they fit the feature being added.
- Avoid over-generalisation, provide a clear description of what has been included in the patch, why this contribution should be accepted, what problem it solves.
- Strip LLM-suggested "improvements" that fall outside your stated scope.
- Run tests and benchmarks

Avoid:

- Touching unrelated modules with styling changes.
- Submitting cleanup or idiomatic fixes unless explicitly requested.

### Metadata

- LLM usage must be disclosed. Traceability protects you, the project, and future of Haskell Open Source. Undisclosed LLM usage or any suspicion of it will be rejected.
- Provide following details:
  - Model name configuration and provideri, request prompt(s).
  - Additional data such timestamps, model response, or full trace could be provided but not required.

## Setting up the build tools

### Using cabal

In order to work with the project you need to install [GHC](https://www.haskell.org/ghc/) and [cabal](https://www.haskell.org/cabal/) tools, we suggest installing them using [GHCup](https://www.haskell.org/ghcup/) project. For working with
this project you need to have GHC>=9.6 and cabal>=3.10

To install ghcup follow the instructions on site. After installing run

```sh
ghcup tui
```

And select recommended versions of GHC an cabal.

## Building the project

To build the project in the project directory run command:

``` sh
cabal build all
```

## Testing

When implementing new test suites, make sure to add them to the 'Run tests' step in `.github/workflows/haskell-ci.yml`.

Before running tests ensure that appropriate version of Redis is run.

To run tests in the project directory run command:

``` sh
cabal test all
```

For cluster tests ensure that redis cluster is running and run:

``` sh
cabal test -fcluster all
```

## License

By contributing, you agree that your contributions will be licensed under the project's license.

Thank you for helping improve hedis!

[cc-homepage]: https://www.contributor-covenant.org
