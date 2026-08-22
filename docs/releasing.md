# Release the gems

This repository contains the `greenroom` gem and the `rubocop-greenroom` gem.
GitHub Actions publishes each gem through RubyGems.org Trusted Publishing.
The workflows do not use a stored RubyGems.org API key.

## Prepare the GitHub environments

Create two repository environments under **Settings > Environments**:

- `release-greenroom`
- `release-rubocop-greenroom`

Each release job names one of them, so an approval request says which gem it
gates. A single shared environment would ask a reviewer to approve a release
without naming the gem going out.

Add the protection rules each gem deserves. A required reviewer holds the job
until a person approves it, and the job stops at that point rather than after
a push that nobody can take back.

## Prepare the RubyGems.org account

1. Sign in to the RubyGems.org account that will own the gems.
2. Enable multi-factor authentication for the account.
3. Open the [pending trusted publishers page](https://rubygems.org/profile/oidc/pending_trusted_publishers).

RubyGems.org requires gem owners to enable multi-factor authentication when a gem requires MFA.
The `greenroom` gemspec currently requires MFA.
The `rubocop-greenroom` gemspec does not currently contain this metadata value.

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
4. Enter the repository owner, repository name, workflow filename, and environment from the applicable table.
5. Leave both workflow repository fields blank.
6. Save the trusted publisher.

The workflow repository fields apply to a reusable workflow from a different repository.
These release workflows are in the same repository as the gems.

## Make a release

1. Update the version in the applicable `version.rb` file.
2. Complete the normal review process for the version change.
3. Create a `greenroom-vVERSION` tag for the `greenroom` gem.
4. Create a `rubocop-greenroom-vVERSION` tag for the `rubocop-greenroom` gem.
5. Push only the tag for the gem that you want to release.
6. Confirm that the applicable release workflow succeeds.
7. Confirm that RubyGems.org shows the new gem version.

Replace `VERSION` with the exact version from the applicable `version.rb` file.
For example, use `greenroom-v0.1.0` for `greenroom` version `0.1.0`.

## MFA compatibility status

The RubyGems.org guides do not explicitly state whether Trusted Publishing works with `rubygems_mfa_required` set to `true`.
The MFA guide states that all gem owners must enable MFA for a gem that requires MFA.
The Trusted Publishing guide states that the workflow uses a short-lived API token.
The guides do not state how that token interacts with the gem MFA requirement.

## Primary sources

- [RubyGems.org Trusted Publishing](https://guides.rubygems.org/trusted-publishing/)
- [RubyGems.org API](https://guides.rubygems.org/rubygems-org-api/)
- [RubyGems.org multi-factor authentication](https://guides.rubygems.org/setting-up-multifactor-authentication/)
- [GitHub Actions OpenID Connect reference](https://docs.github.com/en/actions/reference/security/oidc)
