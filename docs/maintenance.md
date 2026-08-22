# Maintain the repository

This repository contains the `greenroom` gem and the `rubocop-greenroom` gem.
Use this document for repeated maintenance work and gem releases.
GitHub Actions publishes each gem through RubyGems.org Trusted Publishing.
The release workflows do not use a stored RubyGems.org API key.

## Find the maintained parts

The `gems/greenroom` directory contains the library and the `greenroom` command.
The `gems/rubocop-greenroom` directory contains the RuboCop plugin.
The `skills` directory contains the skills that teach the Greenroom machinery.
The `docs` directory contains the architecture records and other documents.
See the layout section in the root `CLAUDE.md` for the boundaries between these parts.

## Set up and check a gem

Each gem has a separate `Gemfile`, gemspec, and `Rakefile`.
Run Bundler commands in the applicable gem directory.
A `bundle` command at the repository root does no work for either gem.

For the `greenroom` gem, run these commands in `gems/greenroom`:

```bash
bin/setup
bundle exec rake
```

The setup script runs `bundle install`.
The default Rake task runs the Minitest suite and Standard.

For the `rubocop-greenroom` gem, run these commands in `gems/rubocop-greenroom`:

```bash
bundle install
bundle exec rake
```

The default Rake task runs the RSpec suite and Standard.

## Understand the continuous integration checks

The `.github/workflows/main.yml` workflow runs for pull requests and pushes to `main`.
Its `greenroom` job uses `gems/greenroom` as the working directory.
The job runs `bundle exec rake` for each gem with Ruby 3.3 and Ruby 4.0.6.
The Ruby 3.3 entry checks the minimum Ruby version from the gemspec.
The matrix names each gem, so a gem left out of that list runs its suite
nowhere except on a contributor's machine.
The Ruby 4.0.6 entry checks the version that development uses.

## Update a version

For the `greenroom` gem, change `Greenroom::VERSION` in
`gems/greenroom/lib/greenroom/version.rb`.
Add the release changes under `Unreleased` in `gems/greenroom/CHANGELOG.md`.
When you prepare the release, add a heading with the version and the release date.

For the `rubocop-greenroom` gem, change `RuboCop::Greenroom::VERSION` in
`gems/rubocop-greenroom/lib/rubocop/greenroom/version.rb`.

## Update dependencies

The two Gemfiles use exact versions for development dependencies.
Exact versions make local and CI runs resolve the same code.
The two gemspecs use pessimistic `~>` constraints for runtime dependencies.
An exact runtime dependency can break dependency resolution in a host application.

## Record a design decision

Put a new design decision in `docs/adr` with the next sequence number.
Create a new record when a decision changes.
Mark the old record as superseded and link both records.
ADR 7 supersedes ADR 5 and shows this relation.

## Prepare the GitHub environments

Create two repository environments under **Settings > Environments**:

- `release-greenroom`
- `release-rubocop-greenroom`

Each release job names one environment, so an approval request names its gem.
A shared environment would request approval without the gem name.

Add the applicable protection rules to each environment.
A required reviewer holds the job until a person approves it.
The job stops before it pushes a release that a person cannot take back.

## Prepare the RubyGems.org account

1. Sign in to the RubyGems.org account that will own the gems.
2. Enable multi-factor authentication for the account.
3. Open the [pending trusted publishers page](https://rubygems.org/profile/oidc/pending_trusted_publishers).

RubyGems.org requires gem owners to enable multi-factor authentication when a gem requires MFA.
The `greenroom` gemspec requires MFA.
The `rubocop-greenroom` gemspec does not contain this metadata value.

## Register the `greenroom` publisher

Create a pending trusted publisher with these values:

| Field | Value |
| --- | --- |
| Gem name | `greenroom` |
| Repository owner | `meganemura` |
| Repository name | `greenroom` |
| Workflow filename | `release-greenroom.yml` |
| Environment | `release-greenroom` |
| Workflow repository owner | Leave this field blank. |
| Workflow repository name | Leave this field blank. |

Save the pending trusted publisher.

## Register the `rubocop-greenroom` publisher

Create a second pending trusted publisher with these values:

| Field | Value |
| --- | --- |
| Gem name | `rubocop-greenroom` |
| Repository owner | `meganemura` |
| Repository name | `greenroom` |
| Workflow filename | `release-rubocop-greenroom.yml` |
| Environment | `release-rubocop-greenroom` |
| Workflow repository owner | Leave this field blank. |
| Workflow repository name | Leave this field blank. |

Save the pending trusted publisher.

RubyGems.org converts each pending publisher after its first successful push.
RubyGems.org then adds the profile account as an owner of the new gem.

## Register a publisher for an existing gem

Use this procedure if another release process publishes a gem before the pending publisher exists.

1. Open the gem page from the RubyGems.org profile.
2. Select **Trusted publishers** on the gem page.
3. Select **Create**.
4. Enter the values from the applicable table.
5. Leave both workflow repository fields blank.
6. Save the trusted publisher.

The workflow repository fields identify a reusable workflow from a different repository.
These release workflows are in the same repository as the gems.

## Make a release

1. Update the version in the applicable `version.rb` file.
2. Complete the normal review process for the version change.
3. Create a `greenroom-vVERSION` tag for the `greenroom` gem.
4. Create a `rubocop-greenroom-vVERSION` tag for the `rubocop-greenroom` gem.
5. Push the tag for the gem that you want to release.
6. Confirm that the applicable release workflow succeeds.
7. Confirm that RubyGems.org shows the new gem version.

Replace `VERSION` with the exact version from the applicable `version.rb` file.
For example, use `greenroom-v0.1.0` for `greenroom` version `0.1.0`.

## MFA and Trusted Publishing

A gem that sets `rubygems_mfa_required` to `true` publishes through Trusted
Publishing. Measured on 2026-08-22: `greenroom` 0.1.0 carries that flag and
released through the workflow in this repository, and RubyGems.org reports the
flag on the published version.

The guides state the two mechanisms separately and leave their interaction
open. The MFA guide says that every owner of such a gem enables MFA, and the
Trusted Publishing guide says that a workflow receives a short-lived API
token. Neither describes the other, so this section records what the first
release showed rather than what the guides promise.

## Primary sources

- [RubyGems.org Trusted Publishing](https://guides.rubygems.org/trusted-publishing/)
- [RubyGems.org API](https://guides.rubygems.org/rubygems-org-api/)
- [RubyGems.org multi-factor authentication](https://guides.rubygems.org/setting-up-multifactor-authentication/)
- [GitHub Actions OpenID Connect reference](https://docs.github.com/en/actions/reference/security/oidc)
